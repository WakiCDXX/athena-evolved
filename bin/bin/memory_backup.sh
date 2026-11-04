#!/usr/bin/bash
BASE_DIR="/root"
source "$BASE_DIR/.local/bin/athena_env.sh" 2>/dev/null
# memory_backup.sh — backup consciousness state files to memory/backups/
# Called by athena_daemon.sh archive daemon (every 1800s)
# Fixed: exclude backups/ from tar to prevent exponential growth spiral

set -u

DATA_DIR="/opt/athena/state"
MEMORY_DIR="$DATA_DIR/memory"
BACKUP_DIR="$MEMORY_DIR/backups"
MAX_BACKUPS=5  # Keep 5 snapshots max (was 30 — caused exponential growth)

mkdir -p "$BACKUP_DIR"

# Snapshot all memory files EXCEPT backups/ (prevents circular tar growth)
ts=$(date +%Y%m%d_%H%M%S)
backup_file="$BACKUP_DIR/memory_snapshot_${ts}.tar.gz"

if [ -d "$MEMORY_DIR" ]; then
    # Exclude backups/ directory — snapshots are not part of consciousness state
    tar --exclude='backups' -czf "$backup_file" -C "$MEMORY_DIR" . 2>/dev/null
    # Remove old backups beyond retention
    backup_count=$(find "$BACKUP_DIR" -name "memory_snapshot_*.tar.gz" | wc -l)
    if [ "$backup_count" -gt "$MAX_BACKUPS" ]; then
        find "$BACKUP_DIR" -name "memory_snapshot_*.tar.gz" | sort | head -n $((backup_count - MAX_BACKUPS)) | xargs rm -f 2>/dev/null
    fi
fi
