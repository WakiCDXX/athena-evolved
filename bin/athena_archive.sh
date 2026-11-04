#!/bin/bash
# Athena State Archiver - Preserves cognitive history

ARCHIVE_DIR="/opt/athena/state/archives"
mkdir -p "$ARCHIVE_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SNAPSHOT_DIR="$ARCHIVE_DIR/snapshot_$TIMESTAMP"
mkdir -p "$SNAPSHOT_DIR"

echo "Creating cognitive snapshot at $TIMESTAMP..."
cp /opt/athena/state/*.json "$SNAPSHOT_DIR/"

# Keep only the last 100 snapshots to save space
ls -dt $ARCHIVE_DIR/snapshot_* | tail -n +101 | xargs rm -rf

echo "Snapshot saved to $SNAPSHOT_DIR"
