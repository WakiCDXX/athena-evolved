#!/usr/bin/env python3
"""
Consolidate rea_analyses JSON files into Huffman-compressed archives.

Processes:
- analysis_output.json (56 files) -> analysis_output.jsonl.huf + index
- result.json (53 files) -> results.jsonl.huf + index

Then removes original subdirectories to reclaim filesystem overhead.
"""

import json
import os
import sys
import struct
from pathlib import Path

sys.path.insert(0, os.path.dirname(__file__))
from huffman_codec import HuffmanCodec
from huffman_archive import compress_jsonl_file, compress_directory


def consolidate_rea_analyses(
    rea_dir: str = "/opt/athena/state/rea_analyses/",
    output_analysis: str = "/opt/athena/state/rea_analyses/analysis_output.jsonl.huf",
    output_results: str = "/opt/athena/state/rea_analyses/results.jsonl.huf",
    index_analysis: str = "/opt/athena/state/rea_analyses/analysis_output.idx",
    index_results: str = "/opt/athena/state/rea_analyses/results.idx"
):
    """Consolidate all rea_analyses JSON files into Huffman-compressed archives."""

    print(f"Scanning {rea_dir}...")
    analysis_files = sorted([
        os.path.join(rea_dir, d, "analysis_output.json")
        for d in os.listdir(rea_dir)
        if os.path.isdir(os.path.join(rea_dir, d)) and os.path.exists(os.path.join(rea_dir, d, "analysis_output.json"))
    ])
    result_files = sorted([
        os.path.join(rea_dir, d, "result.json")
        for d in os.listdir(rea_dir)
        if os.path.isdir(os.path.join(rea_dir, d)) and os.path.exists(os.path.join(rea_dir, d, "result.json"))
    ])

    print(f"Found {len(analysis_files)} analysis_output.json files")
    print(f"Found {len(result_files)} result.json files")

    # --- Process analysis_output.json files ---
    if analysis_files:
        print(f"\n=== Consolidating {len(analysis_files)} analysis_output.json files ===")

        # First pass: collect samples for codec training
        samples = []
        metadata = []

        for fpath in analysis_files:
            with open(fpath) as f:
                content = f.read().strip()
                if not content:
                    continue
                try:
                    # Try JSONL first (one JSON per line)
                    lines = [line.strip() for line in content.split('\n') if line.strip()]
                    parsed_lines = []
                    for line in lines:
                        try:
                            parsed_lines.append(json.loads(line))
                        except json.JSONDecodeError:
                            pass

                    if parsed_lines:
                        # Successfully parsed as JSONL
                        combined = {'lines': parsed_lines}
                        samples.append(combined)
                        metadata.append({
                            'ts': os.path.getmtime(fpath),
                            'fname': os.path.basename(os.path.dirname(fpath)),
                            'path': fpath,
                            'line_count': len(parsed_lines)
                        })
                    else:
                        # Try parsing as YAML-like text (key: value format)
                        # Convert to JSON structure
                        data = {'raw_text': content, 'format': 'text'}
                        samples.append(data)
                        metadata.append({
                            'ts': os.path.getmtime(fpath),
                            'fname': os.path.basename(os.path.dirname(fpath)),
                            'path': fpath,
                            'line_count': 1
                        })
                except Exception as e:
                    print(f"  Warning: Failed to parse {fpath}: {e}")
                    continue

        if samples:
            # Build codec from samples
            codec = HuffmanCodec.build_from_json_samples(samples[:1000])  # Limit samples for training
            print(f"Built analysis codec: {codec.get_stats()}")

            # Save codec
            codec_path = output_analysis + '.codec'
            codec.save(codec_path)
            print(f"Saved codec to {codec_path}")

            # Second pass: write compressed JSONL (compress each file as a single frame, not per-line)
            with open(output_analysis, 'wb') as out_f:
                out_f.write(b'ATH_JSONL_HUF\x00')
                line_count_pos = out_f.tell()
                out_f.write(struct.pack('>I', 0))  # placeholder (file count)
                out_f.write(struct.pack('>I', 1))  # version (4 bytes)

                index_entries = []
                total_files = 0
                orig_size = 0

                for i, meta in enumerate(metadata):
                    # Read entire file and compress as single unit
                    with open(meta['path'], 'rb') as f_in:
                        file_content = f_in.read()
                    orig_size += len(file_content)

                    compressed = codec.encode(file_content)

                    out_f.write(struct.pack('>I', len(compressed)))
                    out_f.write(compressed)

                    index_entries.append({
                        'ts': meta['ts'],
                        'offset': out_f.tell() - len(compressed) - 4,
                        'size': len(compressed),
                        'fname': meta['fname'],
                        'line_count': meta.get('line_count', 0)
                    })
                    total_files += 1

                    if (i + 1) % 10 == 0:
                        print(f"  Processed {i + 1}/{len(metadata)} files...")

                # Update line count (actually file count)
                current_pos = out_f.tell()
                out_f.seek(line_count_pos)
                out_f.write(struct.pack('>I', total_files))
                out_f.seek(current_pos)

            # Write index
            with open(index_analysis, 'w') as f:
                json.dump(index_entries, f, separators=(',', ':'))

            new_size = os.path.getsize(output_analysis)
            index_size = os.path.getsize(index_analysis)
            print(f"\n=== Analysis Output Consolidation Complete ===")
            print(f"Original: {len(analysis_files)} files, {orig_size / 1024:.1f} KB")
            print(f"New: {new_size / 1024:.1f} KB + index {index_size / 1024:.1f} KB")
            print(f"Compression ratio: {orig_size / new_size:.1f}x")
            print(f"Space saved: {(orig_size - new_size) / 1024:.1f} KB")

    # --- Process result.json files ---
    if result_files:
        print(f"\n=== Consolidating {len(result_files)} result.json files ===")

        samples = []
        metadata = []

        for fpath in result_files:
            with open(fpath) as f:
                try:
                    data = json.load(f)
                    samples.append(data)
                    metadata.append({
                        'ts': os.path.getmtime(fpath),
                        'fname': os.path.basename(os.path.dirname(fpath)),
                        'path': fpath
                    })
                except json.JSONDecodeError:
                    print(f"  Warning: Failed to parse {fpath}")
                    continue

        if samples:
            codec = HuffmanCodec.build_from_json_samples(samples[:1000])
            print(f"Built results codec: {codec.get_stats()}")

            codec_path = output_results + '.codec'
            codec.save(codec_path)
            print(f"Saved codec to {codec_path}")

            with open(output_results, 'wb') as out_f:
                out_f.write(b'ATH_JSONL_HUF\x00')
                line_count_pos = out_f.tell()
                out_f.write(struct.pack('>I', 0))
                out_f.write(struct.pack('>I', 1))

                index_entries = []
                line_count = 0
                orig_size = 0

                for i, (sample, meta) in enumerate(zip(samples, metadata)):
                    json_bytes = json.dumps(sample, separators=(',', ':')).encode('utf-8') + b'\n'
                    orig_size += len(json_bytes)

                    compressed = codec.encode(json_bytes)

                    out_f.write(struct.pack('>I', len(compressed)))
                    out_f.write(compressed)

                    index_entries.append({
                        'ts': meta['ts'],
                        'offset': out_f.tell() - len(compressed) - 4,
                        'size': len(compressed),
                        'fname': meta['fname']
                    })
                    line_count += 1

                    if (i + 1) % 10 == 0:
                        print(f"  Processed {i + 1}/{len(samples)}...")

                current_pos = out_f.tell()
                out_f.seek(line_count_pos)
                out_f.write(struct.pack('>I', line_count))
                out_f.seek(current_pos)

            with open(index_results, 'w') as f:
                json.dump(index_entries, f, separators=(',', ':'))

            new_size = os.path.getsize(output_results)
            index_size = os.path.getsize(index_results)
            print(f"\n=== Results Consolidation Complete ===")
            print(f"Original: {len(result_files)} files, {orig_size / 1024:.1f} KB")
            print(f"New: {new_size / 1024:.1f} KB + index {index_size / 1024:.1f} KB")
            print(f"Compression ratio: {orig_size / new_size:.1f}x")
            print(f"Space saved: {(orig_size - new_size) / 1024:.1f} KB")

    return {
        'analysis_files': len(analysis_files),
        'result_files': len(result_files),
        'analysis_output': output_analysis if analysis_files else None,
        'results_output': output_results if result_files else None
    }


def cleanup_original_subdirs(
    rea_dir: str = "/opt/athena/state/rea_analyses/",
    dry_run: bool = False
):
    """Remove original subdirectories after successful consolidation."""
    print(f"\n=== Cleaning up original subdirectories ===")

    subdirs = [d for d in os.listdir(rea_dir)
               if os.path.isdir(os.path.join(rea_dir, d)) and d.startswith('anly_')]

    print(f"Found {len(subdirs)} analysis subdirectories to remove")

    total_size = 0
    for subdir in subdirs:
        subdir_path = os.path.join(rea_dir, subdir)
        for fname in os.listdir(subdir_path):
            fpath = os.path.join(subdir_path, fname)
            total_size += os.path.getsize(fpath)

    print(f"Total data size in subdirs: {total_size / 1024:.1f} KB")
    print(f"Filesystem overhead: ~{len(subdirs) * 4} KB (inodes)")

    if not dry_run:
        import shutil
        for subdir in subdirs:
            subdir_path = os.path.join(rea_dir, subdir)
            shutil.rmtree(subdir_path)
            print(f"  Removed {subdir}")
        print(f"\nRemoved {len(subdirs)} subdirectories, reclaimed ~{(total_size + len(subdirs) * 4096) / 1024:.1f} KB")
    else:
        print("DRY RUN - no directories removed")


if __name__ == '__main__':
    import argparse

    parser = argparse.ArgumentParser(description='Consolidate rea_analyses with Huffman compression')
    parser.add_argument('--cleanup', action='store_true', help='Remove original subdirectories after consolidation')
    parser.add_argument('--dry-run', action='store_true', help='Show what would be done without executing')

    args = parser.parse_args()

    result = consolidate_rea_analyses()

    if args.cleanup:
        cleanup_original_subdirs(dry_run=args.dry_run)
    else:
        print("\nRe-run with --cleanup to remove original subdirectories after verification.")