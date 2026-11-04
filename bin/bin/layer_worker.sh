#!/usr/bin/bash
# layer_worker.sh — persistent object-pool worker for a single consciousness layer.
#
# Replaces the kill/respawn cycle in athena_daemon.sh start_subshell().
# Instead of forking a new bash + layer script every poll cycle
# (setsid bash -c "while true; do cmd; sleep ..."), this keeps ONE bash
# process alive indefinitely. The layer script is sourced each cycle
# (cheap — same process memory) and its case block executes with the
# requested command args.
#
# Usage (backgrounded by athena_daemon.sh):
#   layer_worker.sh <name> <script_path> <command_args> <interval> <pidfile> &
#
# Enigma/Bombe Principle: "A worker that never dies is cheaper than one that
# is constantly reborn." — Constraint: minimize process creation overhead.
# Only ONE bash process stays alive (vs N forks per cycle).

set -o pipefail

# Close any fd inherited from the launcher (e.g. the .pid.lock fd opened by
# _pidfile_lock in start_subshell). If left open, the worker holds the
# per-layer flock forever and any subsequent stop/start for this layer
# deadlocks. exec replaces the shell but keeps inherited fds open.
exec 9>&- 2>/dev/null

NAME="${1:-}"
SCRIPT="${2:-}"
CMD_ARGS="${3:-poll}"
INTERVAL="${4:-120}"
PIDFILE="${5:-}"
DATA="${6:-/opt/athena/state}"

# Bank switching: compressed state files live here
BANK_DIR="$DATA/.bank"
mkdir -p "$BANK_DIR"

[ -z "$NAME" ] && exit 1
[ -z "$SCRIPT" ] && exit 1
[ ! -f "$SCRIPT" ] && exit 1

# Source athena_env.sh for DMA prefetch and other helpers
BASE_DIR="/root"
source "$BASE_DIR/.local/bin/athena_env.sh" 2>/dev/null
# Initialize lookup tables (pre-computes adaptation curves, thresholds)
lut_ensure_ready 2>/dev/null

# Report our PID to the daemon
echo $$ > "$PIDFILE"

# Stagger this layer's cycle offset to avoid all 15+ layers
# hitting python3 processes simultaneously (causes OOM on low-RAM devices)
# Each layer gets a unique offset based on PID modulo 30s
CYCLE_OFFSET=$(( $$ % 30 ))
sleep "$CYCLE_OFFSET"

# Track stats for adaptive interval
SUCCESS=0
FAIL=0
CYCLE_COUNT=0

# --- EXIT instrumentation: capture exact failure mode of each worker ---
LAST_EXIT=0
EXIT_REASON="clean"
EXIT_TS="0"
EXIT_FRAME=""
_exit_instrument() {
    _ec=$?
    LAST_EXIT=$_ec
    EXIT_REASON="exit($_ec)"
    if [ $_ec -ne 0 ]; then
        EXIT_REASON="exit(!!$_ec)  frame='$EXIT_FRAME'  ts=$(date +%s)"
    fi
}
trap _exit_instrument EXIT

# Bank Switching: compress layer state to disk, replace with stub.
# Frees RAM by offloading inactive layer JSON to compressed .bank files.
# On wake, decompress back into place.
bank_swap_out() {
    local statefile="$DATA/${NAME}.json"
    local bankfile="$BANK_DIR/${NAME}.json.gz"
    if [ -f "$statefile" ]; then
        # Compress and replace with minimal stub
        gzip -c "$statefile" > "$bankfile" 2>/dev/null && rm -f "$statefile"
        # Write minimal stub so other scripts don't fail on missing file
        echo '{"banked":true,"timestamp":'$(date +%s)'}' > "$statefile" 2>/dev/null
    fi
}

bank_swap_in() {
    local statefile="$DATA/${NAME}.json"
    local bankfile="$BANK_DIR/${NAME}.json.gz"
    if [ -f "$bankfile" ]; then
        gunzip -c "$bankfile" > "$statefile" 2>/dev/null && rm -f "$bankfile"
    fi
}

# Main persistent loop — no bash fork per cycle, just source + case exec
while :; do
    # Check degradation state before each run
    export ATHENA_DATA_DIR="$DATA"
    current_state=$(python3 "$BASE_DIR/.local/lib/python/athena/degradation_state.py" 2>/dev/null || echo 'normal')

    if [ "$current_state" = "suspended" ] || [ "$current_state" = "safe_shutdown" ]; then
        # Bank out our state before sleeping
        bank_swap_out
        sleep 30
        continue
    fi

    # Bank switch IN: restore state from compressed .bank file
    bank_swap_in

    # DMA Pattern: prefetch this layer's JSON into page cache
    dma_prefetch "$NAME"

    # Source the layer script — its case "${1:-read}" block executes
    # with positional args set to CMD_ARGS
    set -- "$CMD_ARGS"
    source "$SCRIPT" >/dev/null 2>&1
    local source_result=$?
    if [ $source_result -eq 0 ]; then
        SUCCESS=$((SUCCESS + 1))
    else
        FAIL=$((FAIL + 1))
    fi

    # ==================== DECLARATIVE GUARDRAILS ====================
    # Validate layer output against schema guardrails
    local statefile="$DATA/${NAME}.json"
    if [ -f "$statefile" ] && [ -s "$statefile" ]; then
        # Check for layer-specific guardrail schema
        local guardrail_schema="/root/.local/share/athena/guardrails/${NAME}_schema.json"
        if [ ! -f "$guardrail_schema" ]; then
            # Try generic schema
            guardrail_schema="/root/.local/share/athena/guardrails/json_schema.json"
        fi

        if [ -f "$guardrail_schema" ]; then
            python3 -c "
import sys, json
sys.path.insert(0, '/root/.local/lib/python')
from athena.llm_gateway import GuardrailsEngine
engine = GuardrailsEngine('/root/.local/share/athena/guardrails')
with open('$statefile') as f:
    content = f.read()
# Try to parse as JSON and validate
try:
    data = json.loads(content)
    # Check if it's a schema validation rule
    result = engine.validate_output(json.dumps(data))
    if not result.get('passed', True):
        print('GUARDRAIL_FAILED:' + json.dumps(result), file=sys.stderr)
        sys.exit(1)
except json.JSONDecodeError:
    # Not JSON, skip schema validation
    pass
" 2>/dev/null || {
                # Guardrail failed - log and potentially retry
                echo "$(date +%s) GUARDRAIL_FAILED layer=$NAME" >> "$DATA/.guardrail_violations.log"
                FAIL=$((FAIL + 1))
            }
        fi
    fi

    # Workflow skill integration: run cross-skill hooks for this layer
    # Only run workflow hooks every N cycles to avoid overhead
    CYCLE_COUNT=$((CYCLE_COUNT + 1))
    if [ $((CYCLE_COUNT % 5)) -eq 0 ]; then
        # Run wayfinder exploration for this layer
        if [ -x "$ATHENA_WAYFINDER" ]; then
            "$ATHENA_WAYFINDER" explore "$SCRIPT" shallow simple "$DATA/.wayfinder_${NAME}.json" 2>/dev/null || true
        fi

        # Run handoff tracking for layer state transitions
        if [ -x "$ATHENA_HANDOFF" ]; then
            "$ATHENA_HANDOFF" track "${NAME}_cycle_$CYCLE_COUNT" "Layer $NAME cycle $CYCLE_COUNT" 1 "completed" "$NAME" "system" "normal" "$DATA/.handoff_${NAME}.json" 2>/dev/null || true
        fi

        # Run TDD validation on layer output
        if [ -x "$ATHENA_TDD" ] && [ -f "$DATA/${NAME}.json" ]; then
            "$ATHENA_TDD" validate "$DATA/${NAME}.json" pytest 50 5000 "$DATA/.tests" unit parallel "$DATA/.tdd_${NAME}.json" 2>/dev/null || true
        fi
    fi

    # Record result in daemon_feedback.json via external script
# Also outputs adapted_interval to stdout for capture
    export ATHENA_LAYER_NAME="$NAME"
    export ATHENA_LAYER_SCRIPT="$SCRIPT"
    export ATHENA_CMD_ARGS="$CMD_ARGS"
    export ATHENA_SUCCESS="$SUCCESS"
    export ATHENA_FAIL="$FAIL"
    EXIT_FRAME="source $SCRIPT 127.0.0.1; python3 layer_worker.py"
    adapted=$(python3 "$BASE_DIR/.local/lib/python/athena/layer_worker.py" 2>/dev/null || echo "$INTERVAL")
    EXIT_FRAME="sleep $adapted"

    # DISABLED: Event-driven interval override caused OOM kills on low-RAM device
    # Fixed intervals only — no per-cycle python3 forks for interval calculation
    MIN_EVENT_INTERVAL="${MIN_EVENT_INTERVAL:-60}"
    # adapted interval already computed from feedback LUT, use as-is

    # Bank switch OUT: compress state to disk before sleeping
    bank_swap_out

    # Ring Buffer: cap layer log files to prevent unbounded growth
    # Like SNES OAM / Mega Drive VDMAC — fixed-size buffer, wrap-around
    log_rotate_all 2>/dev/null

    # heartbeat log — lets us see which workers are still alive each cycle
    echo "$(date +%s%3N) name=$NAME success=$SUCCESS fail=$FAIL interval=$adapted pid=$$" >> "$DATA/.worker_heartbeat_$NAME.log" 2>/dev/null

    sleep "$adapted"
done
