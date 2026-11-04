#!/usr/bin/env python3
"""
Huffman Archive Decoder for Athena Consciousness System.

Reads Huffman-compressed archives produced by consolidate_rea_analyses.py
and huffman_archive.py. Supports random-access extraction of individual
entries via the companion .idx index file.

Archive format:
    Magic:      b'ATH_JSONL_HUF\x00'   (14 bytes)
    File count: uint32 big-endian       (4 bytes)
    Version:    uint32 big-endian       (4 bytes)
    Frames:     repeated [uint32 frame_len][compressed bytes]
                where compressed bytes are HuffmanCodec.encode() output
                (9-byte inner header + bitstream).

Index format:
    JSON array of entries, each with:
        ts:          modification timestamp (float)
        offset:      byte offset of frame_len in archive (int)
        size:        compressed frame size in bytes (int)
        fname:       source directory name (str)
        line_count:  optional line count (int)
"""

import json
import os
import struct
import bisect
from typing import Dict, List, Any, Optional, Iterator

from huffman_codec import HuffmanCodec

MAGIC = b'ATH_JSONL_HUF\x00'
MAGIC_LEN = len(MAGIC)
HEADER_LEN = MAGIC_LEN + 4 + 4  # 22 bytes


class HuffmanArchiveReader:
    """
    Reader for Huffman-compressed JSONL archives.

    Supports sequential iteration and random-access extraction by index.
    """

    def __init__(self, archive_path: str, codec_path: Optional[str] = None,
                 index_path: Optional[str] = None):
        """
        Args:
            archive_path: Path to the .huf archive file
            codec_path: Path to the .codec frequency table (defaults to
                        archive_path + '.codec')
            index_path: Path to the .idx index file (defaults to
                        archive_path with .huf replaced by .idx)
        """
        self.archive_path = archive_path
        self.codec_path = codec_path or archive_path + '.codec'
        if index_path is None:
            # Try several candidate index paths: archive_path with .huf -> .idx,
            # and the basename minus extension + .idx (e.g. analysis_output.jsonl.huf
            # -> analysis_output.idx, matching consolidate_rea_analyses.py defaults)
            base = archive_path
            if base.endswith('.huf'):
                base = base[:-4]
            # Strip any intermediate .jsonl suffix to match consolidation defaults
            if base.endswith('.jsonl'):
                base = base[:-6]
            self.index_path = base + '.idx'
        else:
            self.index_path = index_path

        self._codec: Optional[HuffmanCodec] = None
        self._index: Optional[List[Dict]] = None
        self._file_count: int = 0
        self._version: int = 0
        self._header_verified: bool = False

    @property
    def codec(self) -> HuffmanCodec:
        if self._codec is None:
            self._codec = HuffmanCodec.load(self.codec_path)
        return self._codec

    @property
    def index(self) -> List[Dict]:
        if self._index is None:
            if os.path.exists(self.index_path):
                with open(self.index_path) as f:
                    self._index = json.load(f)
            else:
                self._index = []
        return self._index

    def _verify_header(self) -> None:
        """Read and validate the archive header."""
        if self._header_verified:
            return
        with open(self.archive_path, 'rb') as f:
            magic = f.read(MAGIC_LEN)
            if magic != MAGIC:
                raise ValueError(f'Invalid magic: {magic!r}, expected {MAGIC!r}')
            self._file_count = struct.unpack('>I', f.read(4))[0]
            self._version = struct.unpack('>I', f.read(4))[0]
        self._header_verified = True

    def file_count(self) -> int:
        self._verify_header()
        return self._file_count

    def version(self) -> int:
        self._verify_header()
        return self._version

    def _read_frame(self, f, pos: int) -> bytes:
        """Read a single compressed frame at the given position."""
        f.seek(pos)
        outer_len = struct.unpack('>I', f.read(4))[0]
        compressed = f.read(outer_len)
        if len(compressed) != outer_len:
            raise ValueError(
                f'Truncated frame at pos {pos}: expected {outer_len} bytes, '
                f'got {len(compressed)}'
            )
        return compressed

    def decode_frame(self, compressed: bytes) -> bytes:
        """Decode a single compressed frame to raw bytes."""
        return self.codec.decode(compressed)

    def get_entry(self, index: int) -> bytes:
        """
        Decode and return the raw bytes of the entry at the given index.

        Args:
            index: Zero-based entry index

        Returns:
            Raw decompressed bytes for that entry
        """
        self._verify_header()
        if index < 0 or index >= self._file_count:
            raise IndexError(f'Entry index {index} out of range [0, {self._file_count})')

        with open(self.archive_path, 'rb') as f:
            # Walk from the start to find the frame at this index
            pos = HEADER_LEN
            for i in range(index):
                outer_len = struct.unpack('>I', f.read(4))[0]
                f.seek(outer_len, os.SEEK_CUR)
                pos = f.tell()
            compressed = self._read_frame(f, pos)
        return self.codec.decode(compressed)

    def get_entry_by_index_entry(self, entry: Dict) -> bytes:
        """
        Decode and return raw bytes using an index entry dict.

        Args:
            entry: Index entry with 'offset' and 'size' keys

        Returns:
            Raw decompressed bytes
        """
        with open(self.archive_path, 'rb') as f:
            compressed = self._read_frame(f, entry['offset'])
        return self.codec.decode(compressed)

    def iter_entries(self) -> Iterator[tuple]:
        """
        Iterate over (index, raw_bytes) for all entries in the archive.

        Yields:
            (index, decoded_bytes) tuples
        """
        self._verify_header()
        with open(self.archive_path, 'rb') as f:
            pos = HEADER_LEN
            for i in range(self._file_count):
                compressed = self._read_frame(f, pos)
                decoded = self.codec.decode(compressed)
                yield i, decoded
                pos = f.tell()

    def get_all(self) -> List[bytes]:
        """Decode and return all entries as a list of raw bytes."""
        return [data for _, data in self.iter_entries()]

    def find_by_ts(self, ts: float) -> Optional[Dict]:
        """
        Binary search the index for an entry matching the given timestamp.

        Args:
            ts: Timestamp to search for

        Returns:
            Matching index entry dict, or None if not found
        """
        idx = self.index
        if not idx:
            return None
        # Build list of timestamps for bisect
        timestamps = [e['ts'] for e in idx]
        pos = bisect.bisect_left(timestamps, ts)
        if pos < len(idx) and idx[pos]['ts'] == ts:
            return idx[pos]
        return None

    def get_stats(self) -> Dict[str, Any]:
        """Get archive statistics."""
        self._verify_header()
        archive_size = os.path.getsize(self.archive_path)
        codec_stats = self.codec.get_stats()
        index_entries = len(self.index)
        return {
            'archive_path': self.archive_path,
            'archive_size_bytes': archive_size,
            'file_count': self._file_count,
            'version': self._version,
            'index_entries': index_entries,
            'codec': codec_stats,
        }


def decode_archive(archive_path: str, codec_path: Optional[str] = None,
                   output_dir: Optional[str] = None) -> List[str]:
    """
    Decode an entire archive to individual files.

    Args:
        archive_path: Path to the .huf archive
        codec_path: Path to the .codec file
        output_dir: Directory to write decoded files (defaults to
                    archive_path + '_decoded/')

    Returns:
        List of output file paths
    """
    if output_dir is None:
        output_dir = archive_path + '_decoded'
    os.makedirs(output_dir, exist_ok=True)

    reader = HuffmanArchiveReader(archive_path, codec_path)
    index = reader.index

    output_paths = []
    for i, data in reader.iter_entries():
        if i < len(index):
            fname = index[i].get('fname', f'entry_{i:04d}')
        else:
            fname = f'entry_{i:04d}'
        out_path = os.path.join(output_dir, fname)
        # Ensure unique filename
        base, ext = os.path.splitext(out_path)
        counter = 1
        while os.path.exists(out_path):
            out_path = f'{base}_{counter}{ext}'
            counter += 1
        with open(out_path, 'wb') as f:
            f.write(data)
        output_paths.append(out_path)

    return output_paths


def decode_entry(archive_path: str, entry_index: int,
                 codec_path: Optional[str] = None) -> bytes:
    """
    Convenience function: decode a single entry by index.

    Args:
        archive_path: Path to the .huf archive
        entry_index: Zero-based entry index
        codec_path: Path to the .codec file

    Returns:
        Raw decompressed bytes
    """
    reader = HuffmanArchiveReader(archive_path, codec_path)
    return reader.get_entry(entry_index)


if __name__ == '__main__':
    import sys

    if len(sys.argv) < 2:
        print('Usage: huffman_archive_decoder.py <archive.huf> [entry_index]')
        print('  Decodes entire archive, or a single entry if index is given')
        sys.exit(1)

    archive_path = sys.argv[1]
    codec_path = archive_path + '.codec'

    if len(sys.argv) >= 3:
        entry_index = int(sys.argv[2])
        data = decode_entry(archive_path, entry_index, codec_path)
        print(f'Entry {entry_index}: {len(data)} bytes')
        print(data.decode('utf-8', errors='replace'))
    else:
        reader = HuffmanArchiveReader(archive_path, codec_path)
        stats = reader.get_stats()
        print(f'Archive: {stats["archive_path"]}')
        print(f'Size: {stats["archive_size_bytes"]} bytes')
        print(f'Entries: {stats["file_count"]}')
        print(f'Version: {stats["version"]}')
        print(f'Index entries: {stats["index_entries"]}')
        print(f'Codec symbols: {stats["codec"]["symbols"]}')
        print(f'Codec efficiency: {stats["codec"]["efficiency"]:.2%}')

        # Decode first entry as preview
        try:
            first = reader.get_entry(0)
            print(f'\nFirst entry preview ({len(first)} bytes):')
            print(first[:500].decode('utf-8', errors='replace'))
        except Exception as e:
            print(f'Preview error: {e}')