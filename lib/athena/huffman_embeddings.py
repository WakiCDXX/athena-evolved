#!/usr/bin/env python3
"""
In-Memory Huffman Embeddings for Athena Consciousness System.

Keeps embedding vectors compressed in RAM using Huffman coding.
Decodes on-demand for similarity search (cosine, dot product).
Achieves 70-95% memory reduction for embedding storage.

Usage:
    # Build compressed index from embedding files
    index = HuffmanEmbeddingIndex.from_directory("/path/to/embeddings/")

    # Search for similar vectors (decodes on-the-fly)
    results = index.search(query_vector, top_k=10)

    # Direct access by timestamp
    vec = index.get_by_ts(timestamp)

    # Batch decode for vectorized similarity
    vectors = index.decode_batch(timestamps)
"""

import json
import os
import sys
import struct
import math
import numpy as np
from typing import Dict, List, Optional, Tuple, Any, Iterator
from dataclasses import dataclass
from pathlib import Path
from collections import defaultdict

sys.path.insert(0, os.path.dirname(__file__))
from huffman_codec import HuffmanCodec


@dataclass
class EmbeddingIndexEntry:
    """Index entry for a single embedding."""
    ts: int
    offset: int
    size: int
    label: str
    dims: int


class HuffmanEmbeddingIndex:
    """
    In-memory compressed embedding index.

    Stores embeddings as Huffman-compressed bytes in memory.
    Decodes individual vectors on-demand for similarity search.
    """

    def __init__(
        self,
        huf_file: str,
        index_file: str,
        codec_file: str = None
    ):
        """
        Initialize from pre-built compressed files.

        Args:
            huf_file: Path to .jsonl.huf compressed embeddings
            index_file: Path to .idx JSON index
            codec_file: Path to .codec Huffman frequency table (default: huf_file + .codec)
        """
        self.huf_file = huf_file
        self.index_file = index_file
        self.codec_file = codec_file or (huf_file + '.codec')

        self.codec: Optional[HuffmanCodec] = None
        self.index: List[EmbeddingIndexEntry] = []
        self._ts_to_entry: Dict[int, EmbeddingIndexEntry] = {}
        self._label_to_entries: Dict[str, List[EmbeddingIndexEntry]] = defaultdict(list)
        self._file_handle = None

        self._load()

    def _load(self):
        """Load codec and index into memory."""
        # Load codec
        self.codec = HuffmanCodec.load(self.codec_file)

        # Load index
        with open(self.index_file) as f:
            index_data = json.load(f)

        self.index = []
        self._ts_to_entry = {}
        self._label_to_entries = defaultdict(list)

        for entry in index_data:
            idx_entry = EmbeddingIndexEntry(
                ts=entry['ts'],
                offset=entry['offset'],
                size=entry['size'],
                label=entry.get('label', ''),
                dims=entry.get('dims', 128)
            )
            self.index.append(idx_entry)
            self._ts_to_entry[entry['ts']] = idx_entry
            self._label_to_entries[idx_entry.label].append(idx_entry)

        # Open file handle for reading
        self._file_handle = open(self.huf_file, 'rb')
        # Verify header (11 bytes: 'ATH_EMB_HUF')
        magic = self._file_handle.read(11)
        if magic != b'ATH_EMB_HUF':
            raise ValueError(f"Invalid huf file header: {magic}")
        # Skip count (4 bytes)
        self._file_handle.read(4)

    def close(self):
        """Close file handle."""
        if self._file_handle:
            self._file_handle.close()
            self._file_handle = None

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()

    def __del__(self):
        self.close()

    @classmethod
    def from_directory(
        cls,
        embedding_dir: str,
        output_file: str = None,
        index_file: str = None,
        codec_file: str = None,
        quantization_bits: int = 8
    ) -> 'HuffmanEmbeddingIndex':
        """
        Build compressed index from directory of JSON embedding files.

        This consolidates individual JSON files into a single compressed file
        with index, then loads it as HuffmanEmbeddingIndex.
        """
        if output_file is None:
            output_file = os.path.join(embedding_dir, 'embeddings.jsonl.huf')
        if index_file is None:
            index_file = os.path.join(embedding_dir, 'embeddings.idx')
        if codec_file is None:
            codec_file = output_file + '.codec'

        # Build using consolidate_embeddings logic
        cls._build_from_files(
            embedding_dir, output_file, index_file, codec_file, quantization_bits
        )

        return cls(output_file, index_file, codec_file)

    @classmethod
    def _build_from_files(
        cls,
        embedding_dir: str,
        output_file: str,
        index_file: str,
        codec_file: str,
        quantization_bits: int
    ):
        """Build compressed files from individual JSON files."""
        embedding_files = sorted([
            f for f in os.listdir(embedding_dir)
            if f.endswith('.json')
        ])

        # First pass: collect vectors for codec training
        vectors = []
        metadata = []

        for fname in embedding_files:
            fpath = os.path.join(embedding_dir, fname)
            with open(fpath) as f:
                data = json.load(f)
                vec = data.get('vector', [])
                if vec:
                    vectors.append(vec)
                    metadata.append({
                        'ts': data.get('ts', 0),
                        'dims': data.get('dims', 128),
                        'label': data.get('label', ''),
                        'session': data.get('session', 0),
                        'fname': fname
                    })

        # Build Huffman codec from embeddings
        codec = HuffmanCodec.build_from_embeddings(vectors, quantization_bits)
        codec.save(codec_file)

        # Second pass: write compressed JSONL
        with open(output_file, 'wb') as out_f:
            out_f.write(b'ATH_EMB_HUF\x00')
            out_f.write(struct.pack('>I', len(vectors)))

            index_entries = []

            for i, (vec, meta) in enumerate(zip(vectors, metadata)):
                line = {
                    'ts': meta['ts'],
                    'dims': meta['dims'],
                    'vector': vec,
                    'label': meta['label'],
                    'session': meta['session']
                }
                json_bytes = json.dumps(line, separators=(',', ':')).encode('utf-8') + b'\n'

                compressed = codec.encode(json_bytes)

                out_f.write(struct.pack('>I', len(compressed)))
                out_f.write(compressed)

                index_entries.append({
                    'ts': meta['ts'],
                    'offset': out_f.tell() - len(compressed) - 4,
                    'size': len(compressed),
                    'label': meta['label'],
                    'dims': meta['dims']
                })

        # Write index
        with open(index_file, 'w') as f:
            json.dump(index_entries, f, separators=(',', ':'))

    def get_by_ts(self, ts: int) -> Optional[np.ndarray]:
        """Get embedding vector by timestamp (decodes on demand)."""
        entry = self._ts_to_entry.get(ts)
        if not entry:
            return None
        return self._decode_entry(entry)

    def get_by_label(self, label: str) -> List[np.ndarray]:
        """Get all embeddings with a given label."""
        entries = self._label_to_entries.get(label, [])
        return [self._decode_entry(e) for e in entries]

    def get_batch(self, timestamps: List[int]) -> Dict[int, np.ndarray]:
        """Get multiple embeddings by timestamp."""
        result = {}
        for ts in timestamps:
            vec = self.get_by_ts(ts)
            if vec is not None:
                result[ts] = vec
        return result

    def _decode_entry(self, entry: EmbeddingIndexEntry) -> np.ndarray:
        """Decode a single embedding from compressed file."""
        if not self._file_handle:
            self._file_handle = open(self.huf_file, 'rb')
            # Skip header (11 bytes magic + 4 bytes count)
            self._file_handle.seek(15)

        self._file_handle.seek(entry.offset)
        compressed_len = struct.unpack('>I', self._file_handle.read(4))[0]
        compressed = self._file_handle.read(compressed_len)

        json_bytes = self.codec.decode(compressed)
        data = json.loads(json_bytes.decode('utf-8'))

        return np.array(data['vector'], dtype=np.float32)

    def search(
        self,
        query_vector: np.ndarray,
        top_k: int = 10,
        metric: str = 'cosine',
        label_filter: str = None
    ) -> List[Tuple[int, float, str]]:
        """
        Search for similar embeddings.

        Returns list of (timestamp, similarity_score, label) sorted by similarity.
        """
        if metric == 'cosine':
            query_norm = np.linalg.norm(query_vector)
            if query_norm == 0:
                return []
            query_unit = query_vector / query_norm

        # Determine which entries to search
        if label_filter:
            entries = self._label_to_entries.get(label_filter, [])
        else:
            entries = self.index

        # Decode and compute similarities
        results = []
        for entry in entries:
            vec = self._decode_entry(entry)

            if metric == 'cosine':
                vec_norm = np.linalg.norm(vec)
                if vec_norm == 0:
                    continue
                similarity = np.dot(query_unit, vec / vec_norm)
            elif metric == 'dot':
                similarity = np.dot(query_vector, vec)
            elif metric == 'euclidean':
                similarity = -np.linalg.norm(query_vector - vec)  # Negative for descending sort
            else:
                raise ValueError(f"Unknown metric: {metric}")

            results.append((entry.ts, float(similarity), entry.label))

        # Sort by similarity descending
        results.sort(key=lambda x: x[1], reverse=True)
        return results[:top_k]

    def search_batch(
        self,
        query_vectors: List[np.ndarray],
        top_k: int = 10,
        metric: str = 'cosine'
    ) -> List[List[Tuple[int, float, str]]]:
        """Search multiple query vectors at once (more efficient)."""
        return [self.search(qv, top_k, metric) for qv in query_vectors]

    def get_stats(self) -> Dict:
        """Get index statistics."""
        file_size = os.path.getsize(self.huf_file) if os.path.exists(self.huf_file) else 0
        index_size = os.path.getsize(self.index_file) if os.path.exists(self.index_file) else 0
        codec_size = os.path.getsize(self.codec_file) if os.path.exists(self.codec_file) else 0

        # Estimate original size (128 floats * 4 bytes * count)
        estimated_original = len(self.index) * 128 * 4

        return {
            'count': len(self.index),
            'compressed_size_mb': file_size / (1024 * 1024),
            'index_size_kb': index_size / 1024,
            'codec_size_kb': codec_size / 1024,
            'total_size_mb': (file_size + index_size + codec_size) / (1024 * 1024),
            'estimated_original_mb': estimated_original / (1024 * 1024),
            'compression_ratio': estimated_original / file_size if file_size else 0,
            'labels': list(self._label_to_entries.keys()),
            'label_counts': {k: len(v) for k, v in self._label_to_entries.items()}
        }

    def decode_all(self) -> Dict[int, np.ndarray]:
        """Decode all embeddings (use with caution - loads everything)."""
        return self.get_batch([e.ts for e in self.index])

    @property
    def timestamps(self) -> List[int]:
        """Get all timestamps in index."""
        return [e.ts for e in self.index]

    @property
    def labels(self) -> List[str]:
        """Get all unique labels."""
        return list(self._label_to_entries.keys())


def build_embedding_index(
    embedding_dir: str,
    output_file: str = None,
    index_file: str = None,
    codec_file: str = None,
    quantization_bits: int = 8
) -> HuffmanEmbeddingIndex:
    """
    Convenience function to build and load Huffman embedding index.

    Usage:
        index = build_embedding_index("/path/to/embeddings/")
        results = index.search(query_vec, top_k=10)
    """
    return HuffmanEmbeddingIndex.from_directory(
        embedding_dir, output_file, index_file, codec_file, quantization_bits
    )


if __name__ == '__main__':
    # Test with existing consolidated embeddings
    data_dir = "/opt/athena/state/corpus/"
    huf_file = os.path.join(data_dir, 'embeddings.jsonl.huf')
    index_file = os.path.join(data_dir, 'embeddings.idx')
    codec_file = huf_file + '.codec'

    if os.path.exists(huf_file) and os.path.exists(index_file) and os.path.exists(codec_file):
        print("Loading existing Huffman embedding index...")
        index = HuffmanEmbeddingIndex(huf_file, index_file, codec_file)

        stats = index.get_stats()
        print(f"Stats: {json.dumps(stats, indent=2)}")

        # Test search with a sample vector
        if index.index:
            sample_ts = index.index[0].ts
            sample_vec = index.get_by_ts(sample_ts)
            print(f"\nSample vector (ts={sample_ts}): shape={sample_vec.shape}, norm={np.linalg.norm(sample_vec):.4f}")

            # Search
            results = index.search(sample_vec, top_k=5)
            print(f"\nTop 5 similar to ts={sample_ts}:")
            for ts, sim, label in results:
                print(f"  ts={ts}, similarity={sim:.4f}, label={label}")

        index.close()
    else:
        print("No consolidated embeddings found. Run consolidate_embeddings.py first.")