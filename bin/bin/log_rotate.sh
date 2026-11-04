#!/usr/bin/bash
# log_rotate.sh — rotate daemon logs into archive/logs/
# Called by athena_daemon.sh archive daemon (every 1800s)

set -u

DATA_DIR="/opt/athena/state"
LOG_DIR="$DATA_DIR/daemon_logs"
ARCHIVE_DIR="$DATA_DIR/archive/logs"
MAX_BYTES=52428800  # 50MB per log before rotation

mkdir -p "$ARCHIVE_DIR"

for logfile in "$LOG_DIR"/*.log; do
    [ -f "$logfile" ] || continue
    name=$(basename "$logfile")
    size=$(stat -c %s "$logfile" 2>/dev/null || echo 0)
    if [ "$size" -gt "$MAX_BYTES" ]; then
        ts=$(date +%Y%m%d_%H%M%S)
        archived="$ARCHIVE_DIR/${name%.log}_${ts}.log.gz"
        gzip -c "$logfile" > "$archived"
        > "$logfile"  # truncate original
        echo "$(date): Rotated $name → $archived" 2>/dev/null
    fi
done

# Also rotate senses.log into logs/rotated/
SENSES_LOG="$DATA_DIR/senses.log"
SENSES_ARCHIVE="$DATA_DIR/logs/rotated"
mkdir -p "$SENSES_ARCHIVE"
if [ -f "$SENSES_LOG" ]; then
    size=$(stat -c %s "$SENSES_LOG" 2>/dev/null || echo 0)
    if [ "$size" -gt 1048576 ]; then  # 1MB
        ts=$(date +%Y%m%d_%H%M%S)
        cp "$SENSES_LOG" "$SENSES_ARCHIVE/senses_${ts}.log"
        gzip -c "$SENSES_ARCHIVE/senses_${ts}.log" > "$SENSES_ARCHIVE/senses_${ts}.log.gz"
        rm "$SENSES_ARCHIVE/senses_${ts}.log"
        > "$SENSES_LOG"
    fi
fi
