#!/usr/bin/bash
# heartbeat_archive.sh — archive heartbeat snapshots to archive/heartbeat/
# Called by athena_daemon.sh archive daemon (every 1800s)

set -u

DATA_DIR="/opt/athena/state"
HB_FILE="$DATA_DIR/heartbeat.json"
ARCHIVE_DIR="$DATA_DIR/archive/heartbeat"
MAX_FILES=1825  # 5 years of daily snapshots

mkdir -p "$ARCHIVE_DIR"

if [ ! -f "$HB_FILE" ]; then
    exit 0
fi

# Archive current heartbeat as daily snapshot
ts=$(date +%Y%m%d)
target="$ARCHIVE_DIR/heartbeat_${ts}.json"

# Only archive once per day
if [ ! -f "$target" ]; then
    cp "$HB_FILE" "$target" 2>/dev/null
    # Compress if older than 7 days
    find "$ARCHIVE_DIR" -name "heartbeat_*.json" -mtime +7 -exec gzip {} \; 2>/dev/null
    # Clean up old archives beyond retention
    file_count=$(find "$ARCHIVE_DIR" -name "heartbeat_*" | wc -l)
    if [ "$file_count" -gt "$MAX_FILES" ]; then
        find "$ARCHIVE_DIR" -name "heartbeat_*" | sort | head -n $((file_count - MAX_FILES)) | xargs rm -f 2>/dev/null
    fi
fi
