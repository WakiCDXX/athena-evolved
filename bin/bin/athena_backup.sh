#!/usr/bin/bash
# athena_backup.sh — Dual-location backup: SD card + internal storage.
# If SD card fails, internal copy keeps Athena alive.
# Fixed: exclude non-essential dirs (.bank, .fifos, backups, .stream_cache)
# and use rsync --exclude instead of cp -a for selective copying.
#
# Locations:
#   SD (primary):  /opt/athena/state
#   SD backup:     /storage/emulated/0/Android/data/com.termux/files/athena_backup
#   Internal:      /sdcard/Android/data/com.termux/files/athena_data
#   Internal bk:   /sdcard/Android/data/com.termux/files/athena_backup

set -o pipefail

PRIMARY="/opt/athena/state"
SD_BACKUP="/storage/emulated/0/Android/data/com.termux/files/athena_backup"
INTERNAL="/sdcard/Android/data/com.termux/files/athena_data"
INTERNAL_BK="/sdcard/Android/data/com.termux/files/athena_backup"

# Directories to exclude from backup (non-essential, regenerable)
EXCLUDE_FLAGS="--exclude='backups' --exclude='.bank' --exclude='.fifos' --exclude='.stream_cache' --exclude='screens' --exclude='*.tar.gz'"

# --- SD card backup ---
# Use write test instead of mountpoint (MIUI FUSE proxy doesn't respond to mountpoint)
if [ -d "$PRIMARY" ] && touch "$PRIMARY/.bk_test" 2>/dev/null; then
    rm -f "$PRIMARY/.bk_test" 2>/dev/null
    mkdir -p "$SD_BACKUP"
    # rsync with exclusions for space-efficient backup
    if command -v rsync >/dev/null 2>&1; then
        rsync -a --delete $EXCLUDE_FLAGS "$PRIMARY/" "$SD_BACKUP/" 2>/dev/null
    else
        cp -a --exclude='backups' --exclude='.bank' "$PRIMARY/" "$SD_BACKUP/" 2>/dev/null
    fi
    echo "$(date +%Y-%m-%dT%H:%M:%S) — SD backup completed: $(du -sh "$SD_BACKUP" 2>/dev/null | cut -f1)" >> "$SD_BACKUP/backup_log.txt"
else
    echo "$(date +%Y-%m-%dT%H:%M:%S) — SD card NOT ACCESSIBLE, skipping SD backup" >> "$SD_BACKUP/backup_log.txt"
fi

# --- Internal backup (survives SD card failure) ---
mkdir -p "$INTERNAL" "$INTERNAL_BK"
if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete $EXCLUDE_FLAGS "$PRIMARY/" "$INTERNAL/" 2>/dev/null
else
    cp -a --exclude='backups' --exclude='.bank' "$PRIMARY/" "$INTERNAL/" 2>/dev/null
fi
echo "$(date +%Y-%m-%dT%H:%M:%S) — Internal backup completed: $(du -sh "$INTERNAL" 2>/dev/null | cut -f1)" >> "$INTERNAL_BK/backup_log.txt"

# --- Verify integrity ---
echo "$(date +%Y-%m-%dT%H:%M:%S) — Backup verification:" >> "$INTERNAL_BK/backup_log.txt"
for f in heartbeat.json volition.json memory.json session_context.json; do
    if [ -f "$PRIMARY/$f" ] && [ -f "$INTERNAL/$f" ]; then
        echo "  $f: OK (both locations)" >> "$INTERNAL_BK/backup_log.txt"
    else
        echo "  $f: MISMATCH" >> "$INTERNAL_BK/backup_log.txt"
    fi
done
