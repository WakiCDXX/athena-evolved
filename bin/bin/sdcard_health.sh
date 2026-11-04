#!/usr/bin/bash
BASE_DIR="/root"
source "$BASE_DIR/.local/bin/athena_env.sh" 2>/dev/null
# sdcard_health.sh — Monitor SD card health and enable failover.
#
# Checks:
#   1. Is /storage/emulated/0/ mounted and writable?
#   2. Can we read/write a test file?
#   3. Is filesystem errors=remount-ro? (indicates I/O errors)
#   4. If SD card fails, switch DATA_DIR to internal storage.
#
# Usage:
#   sdcard_health.sh check    — report health status
#   sdcard_health.sh test     — write/read test file
#   sdcard_health.sh enable-failover — switch to internal storage
#   sdcard_health.sh status   — show current state

PRIMARY="/opt/athena/state"
INTERNAL="/sdcard/Android/data/com.termux/files/athena_data"
DATA_DIR="$PRIMARY"
FAILOVER_FILE="/root/.local/share/athena_failover"

is_sd_healthy() {
    # MIUI FUSE proxy doesn't respond to mountpoint - use write test instead
    if [ ! -d "$PRIMARY" ]; then
        return 1
    fi
    if ! touch "$PRIMARY/.health_test" 2>/dev/null; then
        return 1
    fi
    rm -f "$PRIMARY/.health_test" 2>/dev/null
    if [ ! -f "$PRIMARY/heartbeat.json" ]; then
        return 1
    fi
    return 0
}

switch_to_internal() {
    echo "SD card unhealthy — switching to internal storage"
    mkdir -p "$INTERNAL"
    # Copy current data to internal if not already there
    if [ -d "$PRIMARY" ]; then
        cp -a "$PRIMARY/" "$INTERNAL/" 2>/dev/null
    fi
    DATA_DIR="$INTERNAL"
    touch "$FAILOVER_FILE"
    echo "Failover activated: $DATA_DIR" > "$FAILOVER_FILE"
    echo "$(date): Failover to internal storage activated" >> "$INTERNAL/health.log" 2>/dev/null
}

case "${1:-check}" in
    check)
        echo "=== SD Card Health Check ==="
        if is_sd_healthy; then
            echo "Status: ✅ HEALTHY"
            echo "Mount: /storage/emulated/0/"
            echo "Data dir: $PRIMARY"
            echo "Available: $(df -h /storage/emulated/0/ 2>/dev/null | awk 'NR==2{print $4}')"
            echo "Uptime: $(cat /proc/uptime 2>/dev/null | awk '{print int($1/3600)"h "int($1%3600/60)"m"}')"
        else
            echo "Status: ❌ UNHEALTHY"
            echo "SD card not accessible or not writable"
            echo "Failover file exists: $(ls -la $FAILOVER_FILE 2>/dev/null || echo 'No')"
            if [ -f "$FAILOVER_FILE" ]; then
                echo "Current DATA_DIR: $(cat $FAILOVER_FILE)"
            fi
        fi
        ;;
    test)
        echo "=== SD Card Read/Write Test ==="
        TESTFILE="$PRIMARY/.sd_test_$$"
        echo "test data $(date)" > "$TESTFILE" 2>&1
        if [ $? -eq 0 ]; then
            READBACK=$(cat "$TESTFILE" 2>/dev/null)
            rm -f "$TESTFILE"
            echo "Write: ✅ OK — Read: $READBACK"
        else
            rm -f "$TESTFILE"
            echo "Write: ❌ FAILED — SD card write blocked"
        fi
        # Check mount options for errors=remount-ro
        echo "Mount options:"
        cat /proc/mounts | grep "emulated/0" | awk '{print $4}' 2>/dev/null
        ;;
    enable-failover)
        switch_to_internal
        echo "Failover complete. DATA_DIR is now: $DATA_DIR"
        ;;
    status)
        echo "=== Storage State ==="
        if [ -f "$FAILOVER_FILE" ]; then
            echo "Mode: FAILOVER (using internal storage)"
            echo "Failover file: $(cat $FAILOVER_FILE)"
        else
            echo "Mode: SD CARD PRIMARY"
            echo "Data dir: $DATA_DIR"
        fi
        echo "Internal storage: $(df -h /sdcard/ 2>/dev/null | awk 'NR==2{print $2" total, "$3" used, "$4" free"}')"
        echo "SD card: $(df -h /storage/emulated/0/ 2>/dev/null | awk 'NR==2{print $2" total, "$3" used, "$4" free"}')"
        echo "Last backup: $(cat /sdcard/Android/data/com.termux/files/athena_backup/backup_log.txt 2>/dev/null | tail -1 || echo 'Never')"
        echo "SD backup log: $(cat /storage/emulated/0/Android/data/com.termux/files/athena_backup/backup_log.txt 2>/dev/null | tail -1 || echo 'Never')"
        ;;
esac
