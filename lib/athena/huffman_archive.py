#!/usr/bin/env python3
"""
Huffman Archive Utilities for Athena Consciousness System.

Provides high-level functions for compressing log files and JSONL data
using domain-specific Huffman codecs.
"""

import json
import os
import sys
import struct
from pathlib import Path
from typing import Dict, List, Any, Optional, Iterator

sys.path.insert(0, os.path.dirname(__file__))
from huffman_codec import HuffmanCodec, StreamingHuffmanEncoder, StreamingHuffmanDecoder, build_log_codec, build_json_codec


def compress_log_file(
    input_path: str,
    output_path: str,
    codec_path: Optional[str] = None,
    sample_bytes: int = 100000,
    chunk_size: int = 65536
) -> Dict[str, Any]:
    """
    Compress a log file using Huffman coding.

    Args:
        input_path: Path to input log file
        output_path: Path to output .huf file
        codec_path: Path to save/load codec (defaults to output_path + '.codec')
        sample_bytes: Bytes to sample for building frequency table
        chunk_size: Streaming chunk size

    Returns:
        Dict with compression stats
    """
    if codec_path is None:
        codec_path = output_path + '.codec'

    # Build codec from sample
    codec = build_log_codec(input_path, sample_bytes=sample_bytes)
    codec.save(codec_path)

    # Compress
    encoder = StreamingHuffmanEncoder(codec, chunk_size=chunk_size)

    orig_size = 0
    with open(input_path, 'rb') as f_in, open(output_path, 'wb') as f_out:
        # Write header: magic + version
        f_out.write(b'ATH_LOG_HUF')
        f_out.write(struct.pack('>I', 1))  # version

        while True:
            chunk = f_in.read(chunk_size)
            if not chunk:
                break
            orig_size += len(chunk)
            compressed = encoder.encode_chunk(chunk)
            if compressed:
                f_out.write(struct.pack('>I', len(compressed)))
                f_out.write(compressed)

        # Flush remaining
        final = encoder.finish()
        if final:
            f_out.write(struct.pack('>I', len(final)))
            f_out.write(final)

    new_size = os.path.getsize(output_path)

    return {
        'original_size': orig_size,
        'compressed_size': new_size,
        'ratio': orig_size / new_size if new_size > 0 else 0,
        'codec_path': codec_path
    }


def decompress_log_file(
    input_path: str,
    output_path: str,
    codec_path: Optional[str] = None
) -> Dict[str, Any]:
    """
    Decompress a Huffman-compressed log file.

    Args:
        input_path: Path to .huf file
        output_path: Path to output decompressed file
        codec_path: Path to codec file (defaults to input_path + '.codec')

    Returns:
        Dict with decompression stats
    """
    if codec_path is None:
        codec_path = input_path + '.codec'

    codec = HuffmanCodec.load(codec_path)

    with open(input_path, 'rb') as f_in, open(output_path, 'wb') as f_out:
        # Read header
        magic = f_in.read(12)
        if magic != b'ATH_LOG_HUF\x00':
            raise ValueError(f"Invalid magic: {magic}")

        version = struct.unpack('>I', f_in.read(4))[0]

        # Read and decode each frame
        while True:
            header = f_in.read(4)
            if len(header) < 4:
                break
            frame_len = struct.unpack('>I', header)[0]
            frame = f_in.read(frame_len)
            if len(frame) < frame_len:
                break
            # Decode frame directly (not streaming)
            decompressed = codec.decode(frame)
            f_out.write(decompressed)

    return {
        'output_size': os.path.getsize(output_path)
    }


def compress_jsonl_file(
    input_path: str,
    output_path: str,
    codec_path: Optional[str] = None,
    sample_limit: int = 1000,
    chunk_size: int = 65536
) -> Dict[str, Any]:
    """
    Compress a JSONL file using Huffman coding (per-line compression).

    Args:
        input_path: Path to input .jsonl file
        output_path: Path to output .huf file
        codec_path: Path to save/load codec
        sample_limit: Number of lines to sample for codec training
        chunk_size: Streaming chunk size (for batching lines)

    Returns:
        Dict with compression stats
    """
    if codec_path is None:
        codec_path = output_path + '.codec'

    # Sample lines for codec training
    samples = []
    with open(input_path, 'r') as f:
        for i, line in enumerate(f):
            if i >= sample_limit:
                break
            samples.append(json.loads(line.strip()))

    if not samples:
        return {'error': 'No samples found'}

    # Build codec
    codec = HuffmanCodec.build_from_json_samples(samples)
    codec.save(codec_path)

    # Compress line by line
    orig_size = 0
    line_count = 0
    with open(input_path, 'rb') as f_in, open(output_path, 'wb') as f_out:
        # Write header: magic + line count placeholder + version
        f_out.write(b'ATH_JSONL_HUF')
        line_count_pos = f_out.tell()
        f_out.write(struct.pack('>I', 0))  # placeholder
        f_out.write(struct.pack('>I', 1))  # version

        for line_bytes in f_in:
            line = line_bytes.strip()
            if not line:
                continue
            orig_size += len(line_bytes)
            compressed = codec.encode(line_bytes)
            f_out.write(struct.pack('>I', len(compressed)))
            f_out.write(compressed)
            line_count += 1

        # Update line count
        current_pos = f_out.tell()
        f_out.seek(line_count_pos)
        f_out.write(struct.pack('>I', line_count))
        f_out.seek(current_pos)

    new_size = os.path.getsize(output_path)

    return {
        'original_size': orig_size,
        'compressed_size': new_size,
        'ratio': orig_size / new_size if new_size > 0 else 0,
        'line_count': line_count,
        'codec_path': codec_path
    }


def decompress_jsonl_file(
    input_path: str,
    output_path: str,
    codec_path: Optional[str] = None
) -> Dict[str, Any]:
    """
    Decompress a Huffman-compressed JSONL file.

    Args:
        input_path: Path to .huf file
        output_path: Path to output .jsonl file
        codec_path: Path to codec file

    Returns:
        Dict with decompression stats
    """
    if codec_path is None:
        codec_path = input_path + '.codec'

    codec = HuffmanCodec.load(codec_path)

    line_count = 0
    with open(input_path, 'rb') as f_in, open(output_path, 'w') as f_out:
        # Read header
        magic = f_in.read(14)
        if magic != b'ATH_JSONL_HUF\x00':
            raise ValueError(f"Invalid magic: {magic}")

        expected_lines = struct.unpack('>I', f_in.read(4))[0]
        version = struct.unpack('>I', f_in.read(4))[0]

        # Read frames
        while True:
            header = f_in.read(4)
            if len(header) < 4:
                break
            frame_len = struct.unpack('>I', header)[0]
            frame = f_in.read(frame_len)
            if len(frame) < frame_len:
                break
            decompressed = codec.decode(frame)
            f_out.write(decompressed.decode('utf-8'))
            line_count += 1

    return {
        'line_count': line_count,
        'output_size': os.path.getsize(output_path)
    }


def compress_directory(
    directory: str,
    pattern: str = "*.log",
    threshold_mb: float = 50.0,
    archive_subdir: str = "archive"
) -> List[Dict[str, Any]]:
    """
    Compress all files matching pattern in directory that exceed threshold.

    Args:
        directory: Target directory
        pattern: Glob pattern for files
        threshold_mb: Minimum file size to compress (MB)
        archive_subdir: Subdirectory for compressed archives

    Returns:
        List of compression results
    """
    import glob

    threshold_bytes = threshold_mb * 1024 * 1024
    archive_dir = os.path.join(directory, archive_subdir)
    os.makedirs(archive_dir, exist_ok=True)

    results = []
    for filepath in glob.glob(os.path.join(directory, pattern)):
        if not os.path.isfile(filepath):
            continue

        size = os.path.getsize(filepath)
        if size < threshold_bytes:
            continue

        basename = os.path.basename(filepath)
        timestamp = __import__('datetime').datetime.now().strftime("%Y%m%d_%H%M%S")

        if basename.endswith('.log'):
            archive_name = f"{basename[:-4]}_{timestamp}.huf"
            codec_name = f"{basename[:-4]}_{timestamp}.huf.codec"
            archive_path = os.path.join(archive_dir, archive_name)
            codec_path = os.path.join(archive_dir, codec_name)

            result = compress_log_file(filepath, archive_path, codec_path)
            result['input'] = filepath
            result['output'] = archive_path

        elif basename.endswith('.jsonl'):
            archive_name = f"{basename[:-6]}_{timestamp}.huf"
            codec_name = f"{basename[:-6]}_{timestamp}.huf.codec"
            archive_path = os.path.join(archive_dir, archive_name)
            codec_path = os.path.join(archive_dir, codec_name)

            result = compress_jsonl_file(filepath, archive_path, codec_path)
            result['input'] = filepath
            result['output'] = archive_path

        else:
            continue

        # Remove original if compression ratio is good
        if result.get('ratio', 0) > 1.2:
            os.remove(filepath)
            result['original_removed'] = True
        else:
            os.remove(result['output'])
            if os.path.exists(codec_path):
                os.remove(codec_path)
            result['original_removed'] = False
            result['reverted'] = True

        results.append(result)

    return results


def cleanup_old_archives(directory: str, days: int = 30, archive_subdir: str = "archive") -> int:
    """
    Remove archive files older than specified days.

    Args:
        directory: Parent directory
        days: Age threshold in days
        archive_subdir: Archive subdirectory name

    Returns:
        Number of files removed
    """
    import time

    archive_dir = os.path.join(directory, archive_subdir)
    if not os.path.exists(archive_dir):
        return 0

    cutoff = time.time() - (days * 86400)
    removed = 0

    for fname in os.listdir(archive_dir):
        fpath = os.path.join(archive_dir, fname)
        if os.path.isfile(fpath) and os.path.getmtime(fpath) < cutoff:
            os.remove(fpath)
            removed += 1

    return removed


if __name__ == '__main__':
    import argparse

    parser = argparse.ArgumentParser(description='Huffman archive utilities')
    subparsers = parser.add_subparsers(dest='command')

    # Compress log
    p_log = subparsers.add_parser('compress-log', help='Compress log file')
    p_log.add_argument('input')
    p_log.add_argument('output')
    p_log.add_argument('--codec', default=None)
    p_log.add_argument('--sample', type=int, default=100000)

    # Decompress log
    p_dlog = subparsers.add_parser('decompress-log', help='Decompress log file')
    p_dlog.add_argument('input')
    p_dlog.add_argument('output')
    p_dlog.add_argument('--codec', default=None)

    # Compress JSONL
    p_jsonl = subparsers.add_parser('compress-jsonl', help='Compress JSONL file')
    p_jsonl.add_argument('input')
    p_jsonl.add_argument('output')
    p_jsonl.add_argument('--codec', default=None)
    p_jsonl.add_argument('--sample', type=int, default=1000)

    # Decompress JSONL
    p_djsonl = subparsers.add_parser('decompress-jsonl', help='Decompress JSONL file')
    p_djsonl.add_argument('input')
    p_djsonl.add_argument('output')
    p_djsonl.add_argument('--codec', default=None)

    # Compress directory
    p_dir = subparsers.add_parser('compress-dir', help='Compress directory')
    p_dir.add_argument('directory')
    p_dir.add_argument('--pattern', default='*.log')
    p_dir.add_argument('--threshold-mb', type=float, default=50.0)

    # Cleanup
    p_clean = subparsers.add_parser('cleanup', help='Cleanup old archives')
    p_clean.add_argument('directory')
    p_clean.add_argument('--days', type=int, default=30)

    args = parser.parse_args()

    if args.command == 'compress-log':
        result = compress_log_file(args.input, args.output, args.codec, args.sample)
        print(json.dumps(result, indent=2))
    elif args.command == 'decompress-log':
        result = decompress_log_file(args.input, args.output, args.codec)
        print(json.dumps(result, indent=2))
    elif args.command == 'compress-jsonl':
        result = compress_jsonl_file(args.input, args.output, args.codec, args.sample)
        print(json.dumps(result, indent=2))
    elif args.command == 'decompress-jsonl':
        result = decompress_jsonl_file(args.input, args.output, args.codec)
        print(json.dumps(result, indent=2))
    elif args.command == 'compress-dir':
        results = compress_directory(args.directory, args.pattern, args.threshold_mb)
        print(json.dumps(results, indent=2))
    elif args.command == 'cleanup':
        removed = cleanup_old_archives(args.directory, args.days)
        print(f"Removed {removed} files")
    else:
        parser.print_help()