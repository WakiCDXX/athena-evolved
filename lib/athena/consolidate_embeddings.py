#!/usr/bin/env python3
"""
Consolidate 8884 individual embedding JSON files into single compressed .jsonl.huf file.

Before: 8884 files × ~580 bytes = ~5 MB data + filesystem overhead = 36 MB on disk
After:  1 file × ~5 MB compressed = ~1-2 MB (with Huffman)
"""

import json
import os
import sys
import struct
from pathlib import Path

sys.path.insert(0, os.path.dirname(__file__))
from huffman_codec import HuffmanCodec


def consolidate_embeddings(
    embedding_dir: str = "/opt/athena/state/corpus/embeddings/",
    output_file: str = "/opt/athena/state/corpus/embeddings.jsonl.huf",
    index_file: str = "/opt/athena/state/corpus/embeddings.idx"
):
    """Consolidate all embedding JSON files into single Huffman-compressed JSONL file."""

    print(f"Scanning {embedding_dir}...")
    embedding_files = sorted([f for f in os.listdir(embedding_dir) if f.endswith('.json')])
    print(f"Found {len(embedding_files)} embedding files")

    # First pass: collect all vectors to build Huffman codec
    vectors = []
    metadata = []  # (ts, dims, label, session, file_offset)

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

    print(f"Loaded {len(vectors)} vectors for codec training")

    # Build Huffman codec from JSON samples (not just vectors)
    # We need a codec that understands JSON structure + quantized vectors
    json_samples = []
    for i, (vec, meta) in enumerate(zip(vectors, metadata)):
        line = {
            'ts': meta['ts'],
            'dims': meta['dims'],
            'vector': vec,
            'label': meta['label'],
            'session': meta['session']
        }
        json_samples.append(line)
        if len(json_samples) >= 1000:  # Sample limit for codec training
            break

    codec = HuffmanCodec.build_from_json_samples(json_samples)
    print(f"Built codec: {codec.get_stats()}")

    # Save codec for later use
    codec_path = output_file + '.codec'
    codec.save(codec_path)
    print(f"Saved codec to {codec_path}")

    # Second pass: write compressed JSONL
    with open(output_file, 'wb') as out_f:
        # Write header: magic + codec path reference
        out_f.write(b'ATH_EMB_HUF')
        out_f.write(struct.pack('>I', len(vectors)))  # count

        index_entries = []

        for i, (vec, meta) in enumerate(zip(vectors, metadata)):
            # Build JSONL line
            line = {
                'ts': meta['ts'],
                'dims': meta['dims'],
                'vector': vec,
                'label': meta['label'],
                'session': meta['session']
            }
            json_bytes = json.dumps(line, separators=(',', ':')).encode('utf-8') + b'\n'

            # Compress with Huffman
            compressed = codec.encode(json_bytes)

            # Write: length (4 bytes) + compressed data
            out_f.write(struct.pack('>I', len(compressed)))
            out_f.write(compressed)

            # Track index entry: (ts, file_offset, compressed_size)
            index_entries.append({
                'ts': meta['ts'],
                'offset': out_f.tell() - len(compressed) - 4,
                'size': len(compressed),
                'label': meta['label'],
                'dims': meta['dims']
            })

            if i % 1000 == 0:
                print(f"  Processed {i}/{len(vectors)}...")

    # Write index file
    with open(index_file, 'w') as f:
        json.dump(index_entries, f, separators=(',', ':'))

    # Report sizes
    original_size = sum(os.path.getsize(os.path.join(embedding_dir, f)) for f in embedding_files)
    new_size = os.path.getsize(output_file)
    index_size = os.path.getsize(index_file)

    print(f"\n=== Consolidation Complete ===")
    print(f"Original: {len(embedding_files)} files, {original_size / 1024 / 1024:.2f} MB")
    print(f"New: {new_size / 1024 / 1024:.2f} MB + index {index_size / 1024:.1f} KB")
    print(f"Compression ratio: {original_size / new_size:.1f}x")
    print(f"Space saved: {(original_size - new_size) / 1024 / 1024:.2f} MB")


def load_embedding_by_ts(ts: int, data_dir: str = "/opt/athena/state/corpus/") -> dict:
    """Load a single embedding by timestamp using index."""
    index_file = os.path.join(data_dir, 'embeddings.idx')
    huf_file = os.path.join(data_dir, 'embeddings.jsonl.huf')
    codec_file = huf_file + '.codec'

    # Load index
    with open(index_file) as f:
        index = json.load(f)

    # Binary search for timestamp
    lo, hi = 0, len(index) - 1
    while lo <= hi:
        mid = (lo + hi) // 2
        if index[mid]['ts'] == ts:
            entry = index[mid]
            break
        elif index[mid]['ts'] < ts:
            lo = mid + 1
        else:
            hi = mid - 1
    else:
        return None

    # Load codec
    codec = HuffmanCodec.load(codec_file)

    # Read compressed entry
    with open(huf_file, 'rb') as f:
        f.seek(entry['offset'])
        compressed_len = struct.unpack('>I', f.read(4))[0]
        compressed = f.read(compressed_len)

    # Decompress and parse
    json_bytes = codec.decode(compressed)
    return json.loads(json_bytes.decode('utf-8'))


def search_embeddings_by_label(label: str, data_dir: str = "/opt/athena/state/corpus/") -> list:
    """Search embeddings by label using index."""
    index_file = os.path.join(data_dir, 'embeddings.idx')
    with open(index_file) as f:
        index = json.load(f)

    return [e for e in index if e.get('label') == label]


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == 'search':
        label = sys.argv[2] if len(sys.argv) > 2 else 'normal'
        results = search_embeddings_by_label(label)
        print(f"Found {len(results)} embeddings with label '{label}'")
        for r in results[:5]:
            print(f"  ts={r['ts']}, offset={r['offset']}, size={r['size']}")
    else:
        consolidate_embeddings()