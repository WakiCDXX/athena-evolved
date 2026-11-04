#!/usr/bin/bash
# Phase 2: Add xenobiological layers incrementally

set -o pipefail

BASE_DIR="/root"
BIN_DIR="$BASE_DIR/.local/bin"
DATA_DIR="/opt/athena/state"
PRIMARY="/opt/athena/state"
INTERNAL="/sdcard/Android/data/com.termux/files/athena_data"
FAILOVER_FILE="/root/.local/share/athena_failover"
source "$BIN_DIR/athena_env.sh" 2>/dev/null
BASE="$BASE_DIR"
BIN="$BIN_DIR"
DATA="$PRIMARY"

if [ -f "$FAILOVER_FILE" ]; then
    DATA="$INTERNAL"
fi

_is_layer_worker() {
    local pid="$1"
    [ -d "/proc/$pid" ] || return 1
    tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -q "layer_worker"
}

kill_tree_by_pid() {
    local pid="$1"
    pids=$(ps -o PID --no-headers --ppid "$pid" 2>/dev/null; echo "$pid")
    for p in $pids; do
        kill -TERM "$p" 2>/dev/null
    done
    sleep 0.5
    for p in $pids; do
        kill -KILL "$p" 2>/dev/null
    done
}

start_layer() {
    local entry="$1"
    local name="${entry%%:*}"
    local rest="${entry#*:}"
    local cmd="${rest%:*}"
    local interval="${rest##*:}"
    
    local pidfile="$DATA/${name}.pid"
    
    # Stop existing
    old_pid=$(cat "$pidfile" 2>/dev/null)
    if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null && _is_layer_worker "$old_pid"; then
        kill_tree_by_pid "$old_pid"
    fi
    rm -f "$pidfile" "$pidfile.wrapper" 2>/dev/null
    
    # Extract script and args
    local script_path="$(echo "$cmd" | awk '{print $1}')"
    local cmd_args="$(echo "$cmd" | awk '{for(i=2;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ *$//')"
    [ -z "$cmd_args" ] && cmd_args="poll"
    
    # Launch persistent worker
    setsid bash -c "exec '$BIN/layer_worker.sh' '$name' '$script_path' '$cmd_args' '$interval' '$pidfile' '$DATA'" &
    local new_pid=$!
    echo "$new_pid" > "$pidfile"
    echo "$new_pid" > "$pidfile.wrapper"
    echo "  $name: started (PID $new_pid, ${interval}s)"
}

check_memory() {
    local avail_kb=$(grep MemAvailable /proc/meminfo 2>/dev/null | awk '{print $2}')
    echo "${avail_kb:-0}"
}

# Xenobiological layers - add one at a time with memory checks - SLOW intervals for 1.8GB RAM
XENO_LAYERS=(
    "attention_tropical:$BIN/attention_tropical.sh allocate:300"
    "memory_padic:$BIN/memory_padic.sh consolidate:300"
    "perception_nsa:$BIN/perception_nsa.sh process:300"
    "bioelectric_coupling:$BIN/bioelectric_coupling.sh step:300"
    "multiway_volition:$BIN/multiway_volition.sh evolve:300"
    "memory_xna:$BIN/memory_xna.sh consolidate:600"
    "shadow_detector:$BIN/shadow_detector.sh scan:600"
    "aihs_healing:$BIN/aihs_healing.sh heal:300"
    "metabolic_attention:$BIN/metabolic_attention.sh process:300"
    "chiral_continuity:$BIN/chiral_continuity.sh validate:300"
)

echo "=== Phase 2: Adding Xenobiological Layers Incrementally ==="
avail=$(check_memory)
echo "  Starting memory: $((avail/1024)) MB"

for entry in "${XENO_LAYERS[@]}"; do
    start_layer "$entry"
    sleep 4
    avail=$(check_memory)
    echo "  Memory after layer: $((avail/1024)) MB"
    if [ "$avail" -lt 200000 ]; then
        echo "  WARNING: Low memory ($((avail/1024)) MB), stopping here"
        break
    fi
done

echo ""
echo "=== Phase 2 complete. Run Phase 3 to add workflow/OpenAPPA layers ==="
echo "  Usage: $0 phase3"
