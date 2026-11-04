#!/usr/bin/bash
# xenobiological_log_rotate.sh — rotate + Huffman compress xenobiological daemon log
# Called by athena_daemon.sh or cron (every 1800s)

set -u

BASE_DIR="/root"
DATA_DIR="/opt/athena/state"
LOG_FILE="$DATA_DIR/xenobiological_daemon.log"
ARCHIVE_DIR="$DATA_DIR/archive/logs"
MAX_BYTES=52428800  # 50MB before rotation

mkdir -p "$ARCHIVE_DIR"

# Check if log exists and needs rotation
if [ -f "$LOG_FILE" ]; then
    size=$(stat -c %s "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$size" -gt "$MAX_BYTES" ]; then
        ts=$(date +%Y%m%d_%H%M%S)
        archived="$ARCHIVE_DIR/xenobiological_daemon_${ts}.log.huf"

        # Use Huffman codec for compression
        python3 -c "
import sys
sys.path.insert(0, '$BASE_DIR/.local/lib/python')
from athena.huffman_codec import HuffmanCodec, StreamingHuffmanEncoder

# Build codec from sample of log (first 100KB)
with open('$LOG_FILE', 'rb') as f:
    sample = f.read(100000)
codec = HuffmanCodec.build_from_samples([sample])

# Save codec
codec.save('$archived.codec')

# Stream compress
encoder = StreamingHuffmanEncoder(codec, chunk_size=65536)
with open('$LOG_FILE', 'rb') as f_in:
    with open('$archived', 'wb') as f_out:
        # Write header
        f_out.write(b'XENO_HUF\x00')
        while True:
            chunk = f_in.read(65536)
            if not chunk:
                break
            compressed = encoder.encode_chunk(chunk)
            if compressed:
                f_out.write(compressed)
        # Final flush
        final = encoder.finish()
        if final:
            f_out.write(final)
"
        if [ $? -eq 0 ]; then
            # Truncate original log
            > "$LOG_FILE"
            echo "$(date): Rotated xenobiological_daemon.log → $archived (Huffman)"
        else
            echo "$(date): ERROR: Huffman compression failed, falling back to gzip"
            ts=$(date +%Y%m%d_%H%M%S)
            archived="$ARCHIVE_DIR/xenobiological_daemon_${ts}.log.gz"
            gzip -c "$LOG_FILE" > "$archived"
            > "$LOG_FILE"
        fi
    fi
fi

# Also clean up old archives (keep last 30 days)
find "$ARCHIVE_DIR" -name "xenobiological_daemon_*.log.huf" -mtime +30 -delete
find "$ARCHIVE_DIR" -name "xenobiological_daemon_*.log.huf.codec" -mtime +30 -delete
find "$ARCHIVE_DIR" -name "xenobiological_daemon_*.log.gz" -mtime +30 -delete