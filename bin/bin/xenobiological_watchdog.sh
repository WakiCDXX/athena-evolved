#!/usr/bin/bash
# xenobiological_watchdog.sh — Health monitoring watchdog for xenobiological daemon
# Monitors the single-process xenobiological daemon and restarts if it dies or stalls
# Includes spin detection per The Rouge: 3+ zero-delta cycles, duplicate cycle_id, 30min no progress

set -o pipefail

BASE_DIR="/root"
BIN_DIR="$BASE_DIR/.local/bin"
DATA_DIR="/opt/athena/state"
PYTHON_LIB="${PYTHON_LIB:-$BASE_DIR/.local/lib/python}"

XENO_PIDFILE="$DATA_DIR/xenobiological_daemon.pid"
XENO_LOG="$DATA_DIR/daemon_logs/xenobiological_watchdog.log"
HEARTBEAT_FILE="$DATA_DIR/xenobiological_heartbeat.json"

mkdir -p "$DATA_DIR/daemon_logs"

# Function definitions first
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg" >> "$XENO_LOG"
    echo "$msg" >&2
}

is_xeno_running() {
    local pid
    pid=$(cat "$XENO_PIDFILE" 2>/dev/null)
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

check_heartbeat() {
    # Check if xenobiological daemon has updated outputs recently
    local now=$(date +%s)
    local stale_count=0

    # Key output files that should be updated by the daemon (use _output.json suffix)
    local output_files=(
        "attention_tropical_output.json"
        "memory_padic_output.json"
        "perception_nsa_output.json"
        "bioelectric_output.json"
        "multiway_output.json"
        "memory_xna_output.json"
        "shadow_output.json"
        "aihs_output.json"
        "metabolic_attention_output.json"
        "chiral_output.json"
    )

    for f in "${output_files[@]}"; do
        if [ -f "$DATA_DIR/$f" ] && [ -s "$DATA_DIR/$f" ]; then
            # Try to get timestamp from JSON content first (more accurate)
            local json_ts=$(python3 -c "
import json, sys
try:
    with open('$DATA_DIR/$f') as fp:
        data = json.load(fp)
    if isinstance(data, dict) and 'timestamp' in data:
        print(data['timestamp'])
    else:
        print(0)
except:
    print(0)
" 2>/dev/null)

            if [ -n "$json_ts" ] && [ "$json_ts" != "0" ]; then
                local age=$((now - json_ts))
            else
                # Fallback to file mtime
                local mtime=$(stat -c %Y "$DATA_DIR/$f" 2>/dev/null || echo 0)
                local age=$((now - mtime))
            fi

            # Longer threshold: 20 minutes for slow layers (600s interval + buffer)
            if [ "$age" -gt 1200 ]; then
                log "WARNING: $f is stale (${age}s old)"
                ((stale_count++))
            fi
        else
            log "WARNING: $f missing or empty"
            ((stale_count++))
        fi
    done

    # Return only the count to stdout (no stderr from log calls)
    echo "$stale_count"
}

# ==================== SPIN DETECTION (The Rouge pattern) ====================
# Detects: 3+ zero-delta cycles, duplicate cycle_id, 30min no progress

check_spin() {
    local layer="$1"
    local output_file="$DATA_DIR/${layer}_output.json"

    # Need at least the checkpoint history to detect spin
    # Use daemon_checkpoints.py if available
    if [ -f "$PYTHON_LIB/athena/daemon_checkpoints.py" ]; then
        # Get current result from output file
        local current_result="{}"
        if [ -f "$output_file" ] && [ -s "$output_file" ]; then
            current_result=$(cat "$output_file" 2>/dev/null || echo "{}")
        fi

        # Add layer and cycle_id to current_result for detection
        local cycle_id=$(echo "$current_result" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get('cycle_id', ''))
except:
    print('')
" 2>/dev/null)

        current_result=$(echo "$current_result" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    data['layer'] = '$layer'
    data['cycle_id'] = '$cycle_id'
    print(json.dumps(data))
except:
    print('{}')
" 2>/dev/null)

        # Call daemon_checkpoints.py for spin detection
        local spin_result=$(DATA_DIR="$DATA_DIR" python3 "$PYTHON_LIB/athena/daemon_checkpoints.py" detect_spin "$layer" "$current_result" 2>/dev/null)
        local spin_detected=$(echo "$spin_result" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print('true' if data.get('spin_detected') else 'false')
except:
    print('false')
" 2>/dev/null)

        if [ "$spin_detected" = "true" ]; then
            log "SPIN DETECTED: $layer - $spin_result"
            echo "spin"
            return 0
        fi
    fi

    echo "ok"
    return 1
}

restart_xeno() {
    log "Restarting xenobiological daemon..."

    # Kill old process if still alive
    local old_pid
    old_pid=$(cat "$XENO_PIDFILE" 2>/dev/null)
    if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
        # Kill tree
        pids=$(ps -o PID --no-headers --ppid "$old_pid" 2>/dev/null; echo "$old_pid")
        for p in $pids; do
            kill -TERM "$p" 2>/dev/null
        done
        sleep 1
        for p in $pids; do
            kill -KILL "$p" 2>/dev/null
        done
    fi
    rm -f "$XENO_PIDFILE" "$XENO_PIDFILE.wrapper" 2>/dev/null

    # Start new daemon
    log "Starting xenobiological_daemon.py..."
    setsid python3 "$PYTHON_LIB/athena/xenobiological_daemon.py" >> "$DATA_DIR/daemon_logs/xenobiological_daemon.log" 2>&1 &
    local new_pid=$!
    echo "$new_pid" > "$XENO_PIDFILE"
    echo "$new_pid" > "$XENO_PIDFILE.wrapper"
    log "Xenobiological daemon restarted (PID $new_pid)"
}

# Allow calling specific functions directly (e.g., ./xenobiological_watchdog.sh check_heartbeat)
if [ $# -gt 0 ]; then
    if declare -f "$1" >/dev/null; then
        "$@"
        exit 0
    else
        echo "Unknown function: $1" >&2
        exit 1
    fi
fi

# Only run main loop if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Main watchdog loop
    log "=== Xenobiological Watchdog Started ==="

    # Layer output files for spin detection
    SPIN_LAYERS=(
        "attention_tropical"
        "memory_padic"
        "perception_nsa"
        "bioelectric_coupling"
        "multiway_volition"
        "memory_xna"
        "shadow_detector"
        "aihs_healing"
        "metabolic_attention"
        "chiral_continuity"
    )

    while true; do
        log "DEBUG: Top of loop, checking process..."
        # Check if process is alive
        if ! is_xeno_running; then
            log "ALERT: Xenobiological daemon process dead"
            restart_xeno
        else
            # Process alive - check heartbeat (output freshness)
            # Don't redirect stderr - log calls in check_heartbeat need to write to log file
            log "DEBUG: Process alive, checking heartbeat..."
            stale=$(check_heartbeat)
            log "DEBUG: check_heartbeat returned: $stale"
            if [ "$stale" -gt 5 ]; then  # More than 5 stale outputs = likely stalled
                log "ALERT: $stale outputs stale, daemon may be stalled"
                restart_xeno
            elif [ "$stale" -gt 0 ]; then
                log "INFO: $stale outputs stale (process alive)"
            else
                log "DEBUG: All outputs fresh"
            fi

            # ==================== SPIN DETECTION ====================
            # Check each layer for spin conditions
            for layer in "${SPIN_LAYERS[@]}"; do
                spin_result=$(check_spin "$layer")
                if [ "$spin_result" = "spin" ]; then
                    log "ALERT: Spin detected in $layer - escalating"
                    # Could trigger escalation: restart specific layer, or full restart
                    # For now, log and continue - full restart if multiple layers spinning
                fi
            done
        fi

        log "DEBUG: Sleeping 60s..."
        sleep 60  # Check every minute
    done
fi