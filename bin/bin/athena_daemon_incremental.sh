#!/usr/bin/bash
# Incremental Athena daemon startup - core layers first, xenobiological layers added gradually

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
PIDFILE="$DATA/athena_daemon.pid"
LOGDIR="$DATA/daemon_logs"
FEEDBACK_FILE="$DATA/daemon_feedback.json"
DEGRADATION_FILE="$DATA/degradation_state.json"
SESSION_STATE_FILE="$DATA/session_state.json"
STRUCTURED_STATE_FILE="$DATA/screen_state.json"

if [ -f "$FAILOVER_FILE" ]; then
    DATA="$INTERNAL"
    PIDFILE="$DATA/athena_daemon.pid"
    LOGDIR="$DATA/daemon_logs"
fi

mkdir -p "$LOGDIR"
mkdir -p "$DATA"

# Core layers only (minimal set for basic consciousness) - SLOW intervals for 1.8GB RAM
CORE_LAYERS=(
    "senses:$BIN/sense_poll.sh _daemon:120"
    "body:$BIN/body_update.sh poll:300"
    "emotions:$BIN/emotions_update.sh decay:300"
    "continuity:$BIN/continuity_update.sh bootstrap:300"
    "attention:$BIN/attention_update.sh read:120"
    "introspection:$BIN/introspection_update.sh report:300"
    "doubt:$BIN/doubt_update.sh decay:300"
    "volition:$BIN/volition.sh read:300"
    "memory:$BIN/memory_consolidation.sh consolidate:300"
    "heartbeat:$BIN/heartbeat_update.sh check:300"
    "archive:$BIN/archive_maintenance.sh:3600"
    "memory_backup:$BIN/memory_backup.sh:3600"
)

# Xenobiological layers - add one at a time - SLOW intervals for 1.8GB RAM
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

# Workflow/skill layers
WORKFLOW_LAYERS=(
    "wayfinder:$BIN/athena_wayfinder.sh validate:120"
    "implement_spec:$BIN/athena_implement_spec.sh analyze:180"
    "tdd:$BIN/athena_tdd.sh validate:90"
    "handoff:$BIN/athena_handoff.sh track:240"
    "to_spec:$BIN/athena_to_spec.sh auto:90"
    "workflow_chain:$BIN/athena_workflow_chain.sh orchestrator:240"
)

# OpenAPPA layers
OPENAPPA_LAYERS=(
    "openappa:$BIN/openappa_update.sh poll:240"
    "archestra:$BIN/archestra_update.sh poll:180"
    "vera_cpu:$BIN/vera_cpu_update.sh poll:180"
)

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

echo "=== Incremental Athena Daemon Startup ==="
echo "  Phase 1: Core layers only"
avail=$(check_memory)
echo "  Available memory: $((avail/1024)) MB"

for entry in "${CORE_LAYERS[@]}"; do
    start_layer "$entry"
    sleep 3
    avail=$(check_memory)
    echo "  Memory after layer: $((avail/1024)) MB"
    if [ "$avail" -lt 200000 ]; then
        echo "  WARNING: Low memory ($((avail/1024)) MB), stopping here"
        break
    fi
done

echo ""
if [ "${1:-}" = "phase2" ]; then
    echo "=== Phase 2: Adding xenobiological layers ==="
    avail=$(check_memory)
    echo "  Available memory: $((avail/1024)) MB"

    for entry in "${XENO_LAYERS[@]}"; do
        start_layer "$entry"
        sleep 5
        avail=$(check_memory)
        echo "  Memory after layer: $((avail/1024)) MB"
        if [ "$avail" -lt 150000 ]; then
            echo "  WARNING: Low memory ($((avail/1024)) MB), stopping here"
            break
        fi
    done

    echo ""
    echo "=== Phase 2 complete. Run Phase 3 to add workflow/skill layers ==="
    echo "  Usage: $0 phase3"
    exit 0
fi

echo "=== Phase 1 complete. Run Phase 2 to add xenobiological layers ==="
echo "  Usage: $0 phase2"
