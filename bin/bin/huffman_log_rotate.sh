#!/usr/bin/bash
#
# Huffman Log Rotation Script for Athena Consciousness System
#
# Applies Huffman compression to workflow_logs and training directories
# based on the xenobiological_daemon pattern.
#
# Usage: huffman_log_rotate.sh [--dir DIR] [--threshold-mb MB] [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_LIB="$SCRIPT_DIR/../lib/python/athena"

# Defaults
TARGET_DIRS=()
THRESHOLD_MB=50
DRY_RUN=false

usage() {
    cat <<EOF
Usage: $0 [options]
Options:
  --dir DIR           Target directory (can specify multiple)
  --threshold-mb MB   Compress files larger than MB (default: 50)
  --dry-run           Show what would be done without executing
  --help              Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --dir)
            TARGET_DIRS+=("$2")
            shift 2
            ;;
        --threshold-mb)
            THRESHOLD_MB="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
    esac
done

# Default directories if none specified
if [[ ${#TARGET_DIRS[@]} -eq 0 ]]; then
    TARGET_DIRS=(
        "/opt/athena/state/workflow_logs"
        "/opt/athena/state/corpus/training"
    )
fi

COMPRESSOR_SCRIPT="$PYTHON_LIB/huffman_archive.py"

if [[ ! -f "$COMPRESSOR_SCRIPT" ]]; then
    echo "Error: Compressor script not found at $COMPRESSOR_SCRIPT" >&2
    exit 1
fi

for dir in "${TARGET_DIRS[@]}"; do
    if [[ ! -d "$dir" ]]; then
        echo "Warning: Directory $dir does not exist, skipping" >&2
        continue
    fi

    echo "=== Processing $dir ==="

    # Find files larger than threshold
    find "$dir" -type f -name "*.log" -o -name "*.jsonl" | while IFS= read -r file; do
        size_mb=$(stat -c%s "$file" | awk "{print \$1/1024/1024}")

        # Use awk for float comparison
        if awk -v s="$size_mb" -v t="$THRESHOLD_MB" 'BEGIN {exit (s >= t) ? 0 : 1}'; then
            archive_dir="$dir/archive"
            mkdir -p "$archive_dir"

            timestamp=$(date +%Y%m%d_%H%M%S)
            basename=$(basename "$file")
            archive_name="${basename%.*}_${timestamp}.huf"
            archive_path="$archive_dir/$archive_name"
            codec_path="$archive_path.codec"

            echo "  Compressing $file ($size_mb MB) -> $archive_path"

            if [[ "$DRY_RUN" == "false" ]]; then
                python3 -c "
import sys
sys.path.insert(0, '$PYTHON_LIB')
from huffman_codec import build_log_codec, StreamingHuffmanEncoder
import struct

# Build codec from log sample
codec = build_log_codec('$file', sample_bytes=100000)
codec.save('$codec_path')

# Compress
encoder = StreamingHuffmanEncoder(codec, chunk_size=65536)
with open('$file', 'rb') as f_in, open('$archive_path', 'wb') as f_out:
    # Write header: magic + version
    f_out.write(b'ATH_LOG_HUF\x00')
    f_out.write(struct.pack('>I', 1))  # version

    while True:
        chunk = f_in.read(65536)
        if not chunk:
            break
        compressed = encoder.encode_chunk(chunk)
        if compressed:
            f_out.write(struct.pack('>I', len(compressed)))
            f_out.write(compressed)

    # Flush remaining
    final = encoder.finish()
    if final:
        f_out.write(struct.pack('>I', len(final)))
        f_out.write(final)

print('Compression complete')
"

                # Verify compression worked
                if [[ -f "$archive_path" ]]; then
                    orig_size=$(stat -c%s "$file")
                    new_size=$(stat -c%s "$archive_path")
                    ratio=$(awk -v o="$orig_size" -v n="$new_size" 'BEGIN {printf "%.1f", o/n}')
                    echo "    Original: $(awk -v s="$orig_size" 'BEGIN {printf "%.1f MB", s/1024/1024}')"
                    echo "    Compressed: $(awk -v s="$new_size" 'BEGIN {printf "%.1f MB", s/1024/1024}')"
                    echo "    Ratio: ${ratio}x"

                    # Remove original if compression ratio > 1.2x
                    if awk -v r="$ratio" 'BEGIN {exit (r > 1.2) ? 0 : 1}'; then
                        rm "$file"
                        echo "    Original removed (good compression)"
                    else
                        rm "$archive_path" "$codec_path"
                        echo "    Compression insufficient, reverted"
                    fi
                fi
            fi
        fi
    done

    # Cleanup old archives (>30 days)
    if [[ "$DRY_RUN" == "false" ]]; then
        find "$dir/archive" -type f -name "*.huf" -mtime +30 -delete 2>/dev/null || true
        find "$dir/archive" -type f -name "*.huf.codec" -mtime +30 -delete 2>/dev/null || true
    fi
done

echo "=== Done ==="