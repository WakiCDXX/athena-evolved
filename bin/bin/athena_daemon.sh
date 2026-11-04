#!/usr/bin/bash
# athena_daemon.sh — unified daemon manager for all consciousness layers.
#
# Enigma/Bombe Principle Applied: "Feed results back and redesign."
# Each layer tracks success/failure rates. The daemon adapts intervals
# based on performance. Failing layers get shorter retry intervals,
# reliable layers get longer intervals to conserve resources.
#
# Uses event-driven adaptive scheduling instead of fixed-interval polling.
# Layers are woken by Android lifecycle events, accessibility changes,
# and explicit session state rather than continuous polling.
#
# Usage:
#   athena_daemon.sh start      — launch all layer pollers as background daemons
#   athena_daemon.sh stop       — stop all daemons (SIGTERM)
#   athena_daemon.sh status     — show all daemon PIDs + last update times
#   athena_daemon.sh logs       — tail all log files
#   athena_daemon.sh one-shot   — run all layers once and exit
#   athena_daemon.sh feedback   — show layer performance stats
#   athena_daemon.sh degraded   — show current degradation state
#   athena_daemon.sh session    — set session mode (active/idle/quiet)
#
# Layers polled:
#   body        — body_update.sh poll  (default 120s)
#   emotions    — emotions_update.sh decay (default 120s)
#   continuity  — continuity_update.sh bootstrap (default 120s)
#   senses      — sense_poll.sh _daemon (already running)
#   attention   — attention_update.sh (default 60s, lightweight)
#   introspection — introspection_update.sh report (default 120s)
#   doubt       — doubt_update.sh decay (default 120s)
#   volition    — volition.sh read (default 120s)
#   memory      — memory_consolidation.sh consolidate (default 120s)
#   heartbeat   — heartbeat_update.sh check (default 120s)
#   archive     — archive_maintenance.sh (default 1800s)
#   memory_backup — memory_backup.sh (default 1800s)
# XENOBILOGICAL LAYERS (alien math/physics/chemistry/medicine integration):
#   attention_tropical  — attention_tropical.sh allocate (default 60s)
#   memory_padic        — memory_padic.sh consolidate (default 120s)
#   perception_nsa      — perception_nsa.sh process (default 60s)
#   bioelectric_coupling — bioelectric_coupling.sh step (default 120s)
#   multiway_volition   — multiway_volition.sh evolve (default 120s)
#   memory_xna          — memory_xna.sh consolidate (default 180s)
#   shadow_detector     — shadow_detector.sh scan (default 300s)
#   aihs_healing        — aihs_healing.sh heal (default 60s)
#   metabolic_attention — metabolic_attention.sh process (default 60s)
#   chiral_continuity   — chiral_continuity.sh validate (default 120s)

set -o pipefail

# Source central environment for API keys and config
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

# Check for active failover — if SD card failed, use internal
if [ -f "$FAILOVER_FILE" ]; then
    DATA="$INTERNAL"
    PIDFILE="$DATA/athena_daemon.pid"
    LOGDIR="$DATA/daemon_logs"
fi

mkdir -p "$LOGDIR"
mkdir -p "$DATA"
touch "$PIDFILE"

# --- initialization -------------------------------------------------

init_feedback() {
    if [ ! -f "$FEEDBACK_FILE" ]; then
        python3 "$PYTHON_LIB/athena/daemon_init.py" 2>/dev/null
    fi
}

init_degradation() {
    if [ ! -f "$DEGRADATION_FILE" ]; then
        python3 "$PYTHON_LIB/athena/daemon_init.py" 2>/dev/null
    fi
}

init_session_state() {
    if [ ! -f "$SESSION_STATE_FILE" ]; then
        python3 "$PYTHON_LIB/athena/daemon_init.py" 2>/dev/null
    fi
}

init_feedback
init_degradation
init_session_state

# Initialize state machine
init_state_machine() {
    if [ ! -f "$DATA/daemon_state_machine.json" ]; then
        DATA_DIR="$DATA" python3 "$PYTHON_LIB/athena/state_machine.py" init 2>/dev/null
    fi
}
init_state_machine

# --- feedback system -------------------------------------------------
# Enigma/Bombe: "feed results back and redesign"
# Track each layer's success/failure over time. Adapt intervals.

record_layer_result() {
    local layer="$1"
    local status="$2"  # success or fail
    LAYER_NAME="$layer" LAYER_STATUS="$status" python3 "$PYTHON_LIB/athena/record_layer_result.py" 2>/dev/null
}

get_adapted_interval() {
    local layer="$1"
    local base_interval="$2"
    LAYER_NAME="$layer" BASE_INTERVAL="$base_interval" FEEDBACK_FILE="$FEEDBACK_FILE" python3 "$PYTHON_LIB/athena/get_adapted_interval.py" 2>/dev/null || echo "$base_interval"
}

is_running() {
    local pid="$1"
    kill -0 "$pid" 2>/dev/null
}

sd_health_check() {
    # Check if /sdcard is mounted and writable
    if [ -d "/sdcard/Android/data/com.termux/files" ] && [ -w "/sdcard" ]; then
        echo "healthy"
    else
        echo "unhealthy"
    fi
}

show_feedback() {
    if [ ! -f "$FEEDBACK_FILE" ]; then
        echo "No feedback data yet."
        return
    fi
    FEEDBACK_FILE="$FEEDBACK_FILE" python3 "$PYTHON_LIB/athena/show_feedback.py" 2>/dev/null
}

# --- degradation ladder ---------------------------------------------
# Enigma/Bombe: progressive degradation with concrete recovery rules
# States: normal → conserve → minimal → suspended → safe_shutdown

get_degradation_state() {
    DEGRADATION_FILE="$DEGRADATION_FILE" python3 "$PYTHON_LIB/athena/get_degradation_state.py" 2>/dev/null
}

set_degradation_state() {
    local new_state="$1"
    local reason="$2"
    DEGRADATION_FILE="$DEGRADATION_FILE" NEW_STATE="$new_state" REASON="$reason" python3 "$PYTHON_LIB/athena/set_degradation_state.py" 2>/dev/null
}

check_degradation_triggers() {
    # Evaluate system resources and set degradation state accordingly
    local current_state=$(get_degradation_state)
    local new_state="$current_state"
    local reason=""

    # Gather system metrics
    local avail_kb=$(grep MemAvailable /proc/meminfo 2>/dev/null | awk '{print $2}')
    local thermal=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 0)
    local battery=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null || echo 100)
    local uptime_sec=$(cat /proc/uptime 2>/dev/null | awk '{print $1}' | cut -d. -f1)

    # State ladder: normal=0, conserve=1, minimal=2, suspended=3, safe_shutdown=4
    state_level() {
        case "$1" in
            normal) echo 0 ;;
            conserve) echo 1 ;;
            minimal) echo 2 ;;
            suspended) echo 3 ;;
            safe_shutdown) echo 4 ;;
            *) echo 0 ;;
        esac
    }
    local current_level=$(state_level "$current_state")

    # Check memory (impending OOM) — downgrade only
    if [ -n "$avail_kb" ] && [ "$avail_kb" -lt 153600 ]; then
        new_state="minimal"
        reason="ram_critical_${avail_kb}kb"
    elif [ -n "$avail_kb" ] && [ "$avail_kb" -lt 307200 ]; then
        if [ "$current_level" -eq 0 ]; then
            new_state="conserve"
            reason="ram_low_${avail_kb}kb"
        fi
    fi

    # Check thermal — downgrade only
    if [ "$thermal" -gt 85 ] 2>/dev/null; then
        if [ "$current_level" -le 1 ]; then
            new_state="conserve"
            reason="thermal_${thermal}mC"
        fi
    fi
    if [ "$thermal" -gt 95 ] 2>/dev/null; then
        new_state="minimal"
        reason="thermal_critical_${thermal}mC"
    fi

    # Check battery — downgrade only
    if [ "$battery" -lt 5 ] 2>/dev/null && [ "$battery" -gt 0 ]; then
        new_state="minimal"
        reason="battery_${battery}%"
    elif [ "$battery" -lt 15 ] 2>/dev/null && [ "$battery" -gt 0 ]; then
        if [ "$current_level" -eq 0 ]; then
            new_state="conserve"
            reason="battery_${battery}%"
        fi
    fi

    # Check latency (p95) — downgrade only
    if [ -f "$DATA/daemon_latency.json" ]; then
        local p95_latency=$(DATA_DIR="$DATA" python3 "$PYTHON_LIB/athena/check_p95_latency.py" 2>/dev/null)
        if [ "$p95_latency" -gt 5000 ] 2>/dev/null; then
            if [ "$current_level" -eq 0 ]; then
                new_state="conserve"
                reason="latency_${p95_latency}ms"
            fi
        fi
    fi

    # RECOVERY: upgrade state when conditions improve
    local new_level=$(state_level "$new_state")
    if [ "$new_level" -gt "$current_level" ]; then
        # We downgraded; check if recovery is possible
        local recover=0
        local recover_reason=""
        # Recover from minimal if RAM > 600MB and thermal < 70 and battery > 20
        if [ "$new_state" = "minimal" ] && [ "$avail_kb" -gt 614400 ] 2>/dev/null && [ "$thermal" -lt 70 ] 2>/dev/null && [ "$battery" -gt 20 ] 2>/dev/null; then
            recover=1
            recover_reason="ram_${avail_kb}kb_thermal_${thermal}_battery_${battery}"
        fi
        # Recover from conserve if RAM > 800MB and thermal < 75 and battery > 30
        if [ "$new_state" = "conserve" ] && [ "$avail_kb" -gt 819200 ] 2>/dev/null && [ "$thermal" -lt 75 ] 2>/dev/null && [ "$battery" -gt 30 ] 2>/dev/null; then
            recover=1
            recover_reason="ram_${avail_kb}kb_thermal_${thermal}_battery_${battery}"
        fi
        if [ "$recover" -eq 1 ]; then
            new_state="normal"
            reason="recovery_${recover_reason}"
        fi
    fi

    # Apply state change if needed
    if [ "$new_state" != "$current_state" ]; then
        set_degradation_state "$new_state" "$reason"
        echo "Degradation: $current_state → $new_state ($reason)"
    fi
}

apply_degradation() {
    # Adjust layer behavior based on current degradation state
    DEGRADATION_FILE="$DEGRADATION_FILE" SESSION_STATE_FILE="$SESSION_STATE_FILE" DATA_DIR="$DATA" python3 "$PYTHON_LIB/athena/apply_degradation.py" 2>/dev/null
}

# Recovery rules for degradation states
# - RAM low/impending OOM: Drop image buffers first, unload detector, shorten model context, reduce OCR queue, fall back to accessibility-only
# - CPU overloaded/p95 latency: Coalesce events, cancel superseded jobs, increase diff interval, run at most one expensive worker
# - Thermal rise: Stop continuous inference, drop detector/LLM, reduce workload
# - Battery low: Suspend capture, OCR, vision, background listening
# - OCR crash: Open circuit breaker, retain tree/pixel path, retry after cooldown with smaller crop
# - Detector crash: Disable detection for session, keep accessibility and OCR
# - LLM timeout/schema failure: Cancel, discard malformed output, close runtime, return to deterministic rules
# - Accessibility disabled: Mark tree unavailable, stop node-ID actions, use lower-confidence read-only visual mode
# - Shizuku permission lost: Fail closed, remove capability, continue with direct APIs/accessibility
# - MediaProjection denied: Stop capture, release buffers, do not re-request in a loop

recover_from_crash() {
    local layer="$1"
    local crash_type="$2"
    CRASH_LAYER="$layer" CRASH_TYPE="$crash_type" DEGRADATION_FILE="$DEGRADATION_FILE" python3 "$PYTHON_LIB/athena/recover_from_crash.py" 2>/dev/null
}

# --- adaptive event-driven scheduler --------------------------------
# Enigma/Bombe: Use events to wake cheap stages instead of continuous polling
# Session modes: event_driven (default), fixed, hybrid

get_session_mode() {
    SESSION_STATE_FILE="$SESSION_STATE_FILE" python3 "$PYTHON_LIB/athena/get_session_mode.py" 2>/dev/null
}

set_session_mode() {
    local mode="$1"
    SESSION_STATE_FILE="$SESSION_STATE_FILE" SESSION_MODE="$mode" python3 "$PYTHON_LIB/athena/set_session_mode.py" 2>/dev/null
}

# Screen state hash for detecting stable vs changed screens
get_screen_hash() {
    # Quick hash of screen state for change detection
    # Reads from screen_state.json (structured state), not session_state.json
    STRUCTURED_STATE_FILE="$STRUCTURED_STATE_FILE" python3 "$PYTHON_LIB/athena/get_screen_hash.py" 2>/dev/null
}

record_screen_event() {
    local event_type="$1"
    local detail="${2:-}"
    EVENT_TYPE="$event_type" EVENT_DETAIL="$detail" SESSION_STATE_FILE="$SESSION_STATE_FILE" STRUCTURED_STATE_FILE="$STRUCTURED_STATE_FILE" python3 "$PYTHON_LIB/athena/record_screen_event.py" 2>/dev/null
}

get_event_based_interval() {
    local layer="$1"
    local base_interval="$2"
    local session_mode=$(get_session_mode)
    local screen_hash=$(get_screen_hash)
    SESSION_STATE_FILE="$SESSION_STATE_FILE" SCREEN_HASH="$screen_hash" BASE_INTERVAL="$base_interval" python3 "$PYTHON_LIB/athena/get_event_based_interval.py" 2>/dev/null || echo "$base_interval"
}

# --- PID file serialization (fixes orphan/adopted-PID race) -------------
# Lock the per-layer PID lockfile so start/stop for the same layer cannot
# race each other and mis-adopt a PID.  Verifies via /proc cmdline that the
# PID we are about to kill is really a layer_worker (not a re-born process).
_is_layer_worker() {
    local pid="$1"
    [ -d "/proc/$pid" ] || return 1
    tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -q "layer_worker"
}

_pidfile_lock() {
    # Usage: _pidfile_lock <layer> <op>  ->  acquires an exclusive flock on
    # $DATA/.<layer>.pid.lock on fd 9, releases it when the caller's fd 9
    # closes (daemon lifetime) or on explicit flock -u.
    local lockfile="$DATA/.${1}.pid.lock"
    # Close fd 9 if it was inherited open (e.g. from a prior run or a
    # leaky child) before taking our fresh lock — guarantees a caller never
    # inherits a held lock and blocks forever.
    exec 9>&- 2>/dev/null
    exec 9>"$lockfile" 2>/dev/null
    flock -x 9 2>/dev/null
}

_pidfile_unlock() {
    flock -u 9 2>/dev/null
}

# --- layer startup with degradation awareness -----------------------

start_subshell() {
    local name="$1" cmd="$2" interval="$3"
    local pidfile="$DATA/${name}.pid"
    local adaptive="${4:-true}"  # Enable event-driven scheduling by default

    # Stop existing if any — serialized, comm-verified (no orphan/adopted-PID race)
    local old_pid
    old_pid=$(cat "$pidfile" 2>/dev/null)
    if [ -n "$old_pid" ]; then
        # Honor pidfile only for a true layer_worker (avoids killing a
        # re-adopted PID if the old wrapper died between write and now).
        if kill -0 "$old_pid" 2>/dev/null && _is_layer_worker "$old_pid"; then
            kill_tree_by_pid "$old_pid"
        fi
    fi
    rm -f "$pidfile" "$pidfile.wrapper" 2>/dev/null

    # Acquire per-layer PID lock for the lifetime of this start: no concurrent
    # stop()/start() for the same layer can now race or mis-adopt.
    _pidfile_lock "$name"
    # Release the lock when this block exits (scoped exec on fd 9); do NOT leak
    # the fd to the daemon lifetime — otherwise a start() would hold the lock
    # forever and every subsequent stop()/start() for that layer would hang.
    {
      flock -x 9
      local adapted_interval="$interval"
    if [ "$adaptive" = "true" ]; then
        # Get feedback-adapted interval
        adapted_interval=$(get_adapted_interval "$name" "$interval")
        # Get event-driven interval if in event-driven mode
        local event_interval=$(get_event_based_interval "$name" "$interval")
        # Use the shorter of the two (more responsive)
        # Use python3 for float comparison since bash -lt doesn't work with decimals
        if [ "$event_interval" != "$adapted_interval" ] && python3 -c "exit(0 if float('$event_interval') < float('$adapted_interval') else 1)" 2>/dev/null; then
            adapted_interval="$event_interval"
        fi
    fi
    }
    # flock -u already happens when fd 9 closes at block exit; keep this for
    # defensive symmetry with stop_subshell.
    flock -u 9

    # Check degradation config to see if this layer should even run
    local degraded=$(get_degradation_state)
    local active_layers=$(DATA_DIR="$DATA" python3 "$PYTHON_LIB/athena/get_active_layers.py" 2>/dev/null)

    if [ "$degraded" = "suspended" ] || [ "$degraded" = "safe_shutdown" ]; then
        # Don't start layers in suspended/shutdown state
        echo "  $name: SKIPPED (degraded: $degraded)"
        return
    fi

    local layer_active=$(echo "$active_layers" | tr ',' '\n' | grep -c "^${name}$" 2>/dev/null || true)
    layer_active=${layer_active:-0}
    if [ "$layer_active" -eq 0 ] && [ "$degraded" = "conserve" ] 2>/dev/null; then
        echo "  $name: SKIPPED (conserve mode - not in active layers)"
        return
    fi

    # Launch persistent object-pool worker (no per-cycle bash fork)
    # cmd is like "$BIN/body_update.sh poll" — split into script + args
    local script_path="${cmd% *}"
    local cmd_args="${cmd#* }"
    # If cmd has no space, cmd_args defaults to poll
    # Actually fix: extract properly
    script_path="$(echo "$cmd" | awk '{print $1}')"
    cmd_args="$(echo "$cmd" | awk '{for(i=2;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ *$//')"
    [ -z "$cmd_args" ] && cmd_args="poll"

    # Launch persistent worker as background process (stays alive between cycles)
    setsid bash -c "exec '$BIN/layer_worker.sh' '$name' '$script_path' '$cmd_args' '$adapted_interval' '$pidfile' '$DATA'" &
    local new_pid=$!
    echo "$new_pid" > "$pidfile"
    echo "$new_pid" > "$pidfile.wrapper"
    echo "  $name: started (PID $new_pid, object pool, ${adapted_interval}s adaptive)"
    echo "$name:$adapted_interval" > "$DATA/${name}_interval.adapted"
}

acquire_wake_lock() {
    termux-wake-lock 2>/dev/null
}

release_wake_lock() {
    termux-wake-unlock 2>/dev/null
}

stop_subshell() {
    local name="$1"
    local pidfile="$DATA/${name}.pid"
    _pidfile_lock "$name"
    local pid
    pid=$(cat "$pidfile" 2>/dev/null)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && _is_layer_worker "$pid"; then
        kill_tree_by_pid "$pid"
        echo "  $name: stopped (was PID $pid)"
    else
        [ -n "$pid" ] && echo "  $name: not running (stale PID $pid)"
        [ -z "$pid" ] && echo "  $name: no PID file"
    fi
    rm -f "$pidfile" "$pidfile.wrapper"
    _pidfile_unlock
}

kill_tree_by_pid() {
    local pid="$1"
    # Kill the process and all its children
    pids=$(ps -o PID --no-headers --ppid "$pid" 2>/dev/null; echo "$pid")
    for p in $pids; do
        kill -TERM "$p" 2>/dev/null
    done
    sleep 0.5
    for p in $pids; do
        kill -KILL "$p" 2>/dev/null
    done
}

# --- main --------------------------------------------------------------------

# Trap SIGTERM/SIGINT to save checkpoint before OOM kill or manual stop
save_checkpoint_on_exit() {
    local exit_code=$?
    echo "=== Athena Daemon: Trapped signal, saving checkpoint ===" >&2
    # Only save if we have session context
    if [[ -n "${OPENCLAUDE_SESSION_ID:-}" || -n "${CLAUDE_SESSION_ID:-}" ]]; then
        ~/.local/bin/athena_checkpoint.sh save 2>&1 | sed 's/^/  /' >&2
    fi
    # Also save daemon state
    if [ -f "$DEGRADATION_FILE" ]; then
        cp "$DEGRADATION_FILE" "$DEGRADATION_FILE.checkpoint" 2>/dev/null
    fi
    exit $exit_code
}

# Install traps
trap save_checkpoint_on_exit SIGTERM SIGINT SIGQUIT
# Note: SIGKILL cannot be trapped — use the periodic cron for that

case "${1:-help}" in
    start)
        echo "=== Athena Daemon: Starting all layers ==="
        echo "  Scheduling mode: $(get_session_mode)"

        # Clean up any orphaned processes from previous crashes/restarts
        for name in body emotions continuity attention introspection doubt volition memory heartbeat senses archive memory_backup openappa archestra vera_cpu wayfinder implement_spec tdd handoff to_spec workflow_chain attention_tropical memory_padic perception_nsa bioelectric_coupling multiway_volition memory_xna shadow_detector aihs_healing metabolic_attention chiral_continuity; do
            pfile="$DATA/${name}.pid"
            opid=$(cat "$pfile" 2>/dev/null)
            if [ -n "$opid" ] && kill -0 "$opid" 2>/dev/null; then
                kill_tree_by_pid "$opid" 2>/dev/null
            fi
            rm -f "$pfile" "$pfile.wrapper" 2>/dev/null
        done
        if [ -f "$DATA/sense_poll.pid" ]; then
            spid=$(cat "$DATA/sense_poll.pid" 2>/dev/null)
            if [ -n "$spid" ] && kill -0 "$spid" 2>/dev/null; then
                kill_tree_by_pid "$spid" 2>/dev/null
            fi
            rm -f "$DATA/sense_poll.pid"
        fi
        if [ -f "$DATA/sd_health_monitor.pid" ]; then
            sdp=$(cat "$DATA/sd_health_monitor.pid" 2>/dev/null)
            if [ -n "$sdp" ] && kill -0 "$sdp" 2>/dev/null; then
                kill_tree_by_pid "$sdp" 2>/dev/null
            fi
            rm -f "$DATA/sd_health_monitor.pid"
        fi

        # Check current degradation state
        local_degraded=$(get_degradation_state)
        echo "  Degradation state: $local_degraded"

        # Memory guard: check available RAM
        avail_kb=$(grep MemAvailable /proc/meminfo 2>/dev/null | awk '{print $2}')
        if [ -z "$avail_kb" ] || [ "$avail_kb" -lt 307200 ]; then
            echo "  WARNING: Low memory (${avail_kb:-0} KB available). Starting light layers only."
            set_degradation_state "conserve" "ram_low_startup_${avail_kb}kb"
        else
            # Recovery check: if stuck in conserve/minimal with good RAM, recover
            cur=$(get_degradation_state)
            if [ "$cur" = "conserve" ] && [ "$avail_kb" -gt 819200 ]; then
                set_degradation_state "normal" "startup_recovery_ram_${avail_kb}kb"
                echo "  Recovery: conserve → normal (RAM ${avail_kb}kb available)"
            elif [ "$cur" = "minimal" ] && [ "$avail_kb" -gt 614400 ]; then
                set_degradation_state "normal" "startup_recovery_ram_${avail_kb}kb"
                echo "  Recovery: minimal → normal (RAM ${avail_kb}kb available)"
            fi
        fi

        # API key validation
        if [ -z "$OPENAI_API_KEY" ] || echo "$OPENAI_API_KEY" | grep -qE "sk-or-v1-(REPLACE|invalid|test|placeholder)"; then
            echo "  WARNING: OPENAI_API_KEY missing or invalid."
        else
            echo "  API key validated."
        fi

        # senses — launch sense_poll.sh as a proper daemon (always first)
        if [ -f "$DATA/sense_poll.pid" ]; then
            old_spid=$(cat "$DATA/sense_poll.pid" 2>/dev/null)
            if [ -n "$old_spid" ] && kill -0 "$old_spid" 2>/dev/null; then
                kill_tree_by_pid "$old_spid" 2>/dev/null
            fi
            rm -f "$DATA/sense_poll.pid" "$DATA/sense_poll.pid.wrapper" 2>/dev/null
        fi
        start_subshell "senses" "$BIN/sense_poll.sh _daemon" "${INTERVAL_AUTO:-60}"

        # Acquire wake-lock so MIUI doesn't OOM-kill Termux
        acquire_wake_lock

        # Set global event-driven interval floor so persistent workers never
        # poll faster than MIN_EVENT_INTERVAL (prevents per-cycle fork-storm OOM).
        # Conservative 5s minimum for 1.8GB RAM device
        export MIN_EVENT_INTERVAL=5

        # Load degradation config
        apply_degradation

        # Compile gate: verify all self-modified scripts before loading
        echo "  Running compile gate on layer scripts..."
        for _script in "$BIN/body_update.sh" "$BIN/emotions_update.sh" "$BIN/continuity_update.sh" "$BIN/attention_update.sh" "$BIN/introspection_update.sh" "$BIN/doubt_update.sh" "$BIN/volition.sh" "$BIN/memory_consolidation.sh" "$BIN/heartbeat_update.sh" "$BIN/archive_maintenance.sh" "$BIN/memory_backup.sh" "$BIN/openappa_update.sh" "$BIN/archestra_update.sh" "$BIN/vera_cpu_update.sh" "$BIN/attention_tropical.sh" "$BIN/memory_padic.sh" "$BIN/perception_nsa.sh" "$BIN/bioelectric_coupling.sh" "$BIN/multiway_volition.sh" "$BIN/memory_xna.sh" "$BIN/shadow_detector.sh" "$BIN/aihs_healing.sh" "$BIN/metabolic_attention.sh" "$BIN/chiral_continuity.sh"; do
            if [ -f "$_script" ]; then
                _cg_result=$(DATA_DIR="$DATA" python3 "$PYTHON_LIB/athena/compile_gate.py" "$_script" 2>/dev/null)
                _cg_score=$(echo "$_cg_result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('score',0))" 2>/dev/null)
                if [ "$_cg_score" = "0" ]; then
                    echo "  COMPILE GATE FAIL: $_script — $_cg_result"
                else
                    echo "  COMPILE GATE PASS: $_script (score=$_cg_score)"
                fi
            fi
        done

        # Launch layers based on state machine
        # State machine determines which layers run in each workflow state
        echo "  State machine: $(DATA_DIR="$DATA" python3 "$PYTHON_LIB/athena/state_machine.py" get_state 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('effective_state','UNKNOWN'))" 2>/dev/null)"

        # Get list of layers that should run in current state
        LAYERS_TO_START=$(
            DATA_DIR="$DATA" python3 -c "
import sys
sys.path.insert(0, '$PYTHON_LIB')
from athena.state_machine import StateMachine, DaemonState
sm = StateMachine('$DATA')
layers = ['body', 'emotions', 'continuity', 'attention', 'introspection', 'doubt', 'volition', 'memory', 'heartbeat', 'archive', 'memory_backup', 'wayfinder', 'implement_spec', 'tdd', 'handoff', 'to_spec', 'workflow_chain', 'openappa', 'archestra', 'vera_cpu', 'xenobiological_daemon']
for layer in layers:
    should_run, reason = sm.should_run_layer(layer)
    if should_run:
        print(layer)
" 2>/dev/null
        )

        # Define layer commands and intervals
        declare -A LAYER_CMD=(
            [body]="$BIN/body_update.sh poll"
            [emotions]="$BIN/emotions_update.sh decay"
            [continuity]="$BIN/continuity_update.sh bootstrap"
            [attention]="$BIN/attention_update.sh read"
            [introspection]="$BIN/introspection_update.sh report"
            [doubt]="$BIN/doubt_update.sh decay"
            [volition]="$BIN/volition.sh read"
            [memory]="$BIN/memory_consolidation.sh consolidate"
            [heartbeat]="$BIN/heartbeat_update.sh check"
            [archive]="$BIN/archive_maintenance.sh"
            [memory_backup]="$BIN/memory_backup.sh"
            [wayfinder]="$BIN/athena_wayfinder.sh validate"
            [implement_spec]="$BIN/athena_implement_spec.sh analyze"
            [tdd]="$BIN/athena_tdd.sh validate"
            [handoff]="$BIN/athena_handoff.sh track"
            [to_spec]="$BIN/athena_to_spec.sh auto"
            [workflow_chain]="$BIN/athena_workflow_chain.sh orchestrator"
            [openappa]="$BIN/openappa_update.sh poll"
            [archestra]="$BIN/archestra_update.sh poll"
            [vera_cpu]="$BIN/vera_cpu_update.sh poll"
        )

        declare -A LAYER_INTERVAL=(
            [body]=${INTERVAL_BODY:-120}
            [emotions]=${INTERVAL_EMO:-120}
            [continuity]=${INTERVAL_CONT:-120}
            [attention]=${INTERVAL_ATTN:-60}
            [introspection]=${INTERVAL_INTROS:-120}
            [doubt]=${INTERVAL_DOUBT:-120}
            [volition]=${INTERVAL_VOL:-120}
            [memory]=${INTERVAL_MEM:-120}
            [heartbeat]=${INTERVAL_HB:-120}
            [archive]=${INTERVAL_ARCHIVE:-1800}
            [memory_backup]=${INTERVAL_ARCHIVE:-1800}
            [wayfinder]=${INTERVAL_WAYFINDER:-90}
            [implement_spec]=${INTERVAL_IMPLEMENT_SPEC:-120}
            [tdd]=${INTERVAL_TDD:-60}
            [handoff]=${INTERVAL_HANDOFF:-180}
            [to_spec]=${INTERVAL_TO_SPEC:-60}
            [workflow_chain]=${INTERVAL_WORKFLOW_CHAIN:-180}
            [openappa]=${INTERVAL_OPENAPPA:-240}
            [archestra]=${INTERVAL_ARCHESTRA:-120}
            [vera_cpu]=${INTERVAL_VERA_CPU:-180}
        )

        # Start layers that should run
        for layer in $LAYERS_TO_START; do
            if [ "$layer" = "xenobiological_daemon" ]; then
                # XENOBILOGICAL LAYERS — Single-process daemon (avoids OOM on 1.8GB RAM)
                xeno_pidfile="$DATA/xenobiological_daemon.pid"
                if [ -f "$xeno_pidfile" ]; then
                    old_xeno=$(cat "$xeno_pidfile" 2>/dev/null)
                    if [ -n "$old_xeno" ] && kill -0 "$old_xeno" 2>/dev/null; then
                        kill_tree_by_pid "$old_xeno" 2>/dev/null
                    fi
                    rm -f "$xeno_pidfile" "$xeno_pidfile.wrapper" 2>/dev/null
                fi
                setsid python3 "$PYTHON_LIB/athena/xenobiological_daemon.py" &
                xeno_pid=$!
                echo "$xeno_pid" > "$xeno_pidfile"
                echo "$xeno_pid" > "$xeno_pidfile.wrapper"
                echo "  xenobiological_daemon: started (PID $xeno_pid, single-process, 10 layers)"
            else
                cmd="${LAYER_CMD[$layer]}"
                interval="${LAYER_INTERVAL[$layer]:-120}"
                if [ -n "$cmd" ]; then
                    start_subshell "$layer" "$cmd" "$interval"
                fi
            fi
            sleep 2
        done

        echo "=== All layer daemons started (state-driven scheduling) ==="

        # Start SD card health monitor
        sd_health_check
        echo "  sd_health_monitor: started"

        # Record initial session state
        record_screen_event "daemon_start" "mode=$(get_session_mode)"

        # Initialize latency tracking
        if [ ! -f "$DATA/daemon_latency.json" ]; then
            DATA_DIR="$DATA" python3 "$PYTHON_LIB/athena/init_latency.py" 2>/dev/null
        fi
        ;;

    stop)
        echo "=== Athena Daemon: Stopping all layers ==="
        # Save checkpoint before stopping
        if [[ -n "${OPENCLAUDE_SESSION_ID:-}" || -n "${CLAUDE_SESSION_ID:-}" ]]; then
            ~/.local/bin/athena_checkpoint.sh save 2>&1 | sed 's/^/  /'
        fi
        release_wake_lock

        # Parallel stop: send SIGTERM to all layers simultaneously
        # Collect all PIDs first
        pids_to_stop=()
        for name in body emotions continuity attention introspection doubt volition memory heartbeat archive memory_backup openappa archestra vera_cpu wayfinder implement_spec tdd handoff to_spec workflow_chain attention_tropical memory_padic perception_nsa bioelectric_coupling multiway_volition memory_xna shadow_detector aihs_healing metabolic_attention chiral_continuity; do
            pidfile="$DATA/${name}.pid"
            pid=$(cat "$pidfile" 2>/dev/null)
            if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && _is_layer_worker "$pid"; then
                pids_to_stop+=("$pid")
            fi
        done

        # Also collect senses and sd_health_monitor PIDs
        if [ -f "$DATA/sense_poll.pid" ]; then
            spid=$(cat "$DATA/sense_poll.pid" 2>/dev/null)
            if [ -n "$spid" ] && kill -0 "$spid" 2>/dev/null; then
                pids_to_stop+=("$spid")
            fi
        fi

        if [ -f "$DATA/sd_health_monitor.pid" ]; then
            sdpid=$(cat "$DATA/sd_health_monitor.pid" 2>/dev/null)
            if [ -n "$sdpid" ] && kill -0 "$sdpid" 2>/dev/null; then
                pids_to_stop+=("$sdpid")
            fi
        fi

        # Collect xenobiological daemon PID
        if [ -f "$DATA/xenobiological_daemon.pid" ]; then
            xeno_pid=$(cat "$DATA/xenobiological_daemon.pid" 2>/dev/null)
            if [ -n "$xeno_pid" ] && kill -0 "$xeno_pid" 2>/dev/null; then
                pids_to_stop+=("$xeno_pid")
            fi
        fi

        # Send SIGTERM to all collected PIDs simultaneously
        for pid in "${pids_to_stop[@]}"; do
            # Kill the process and all its children
            children=$(ps -o PID --no-headers --ppid "$pid" 2>/dev/null; echo "$pid")
            for p in $children; do
                kill -TERM "$p" 2>/dev/null &
            done
        done
        wait  # Wait for all kill commands to complete

        # Brief pause for graceful shutdown
        sleep 0.5

        # Send SIGKILL to any remaining processes
        for pid in "${pids_to_stop[@]}"; do
            children=$(ps -o PID --no-headers --ppid "$pid" 2>/dev/null; echo "$pid")
            for p in $children; do
                kill -KILL "$p" 2>/dev/null &
            done
        done
        wait

        # Clean up PID files
        for name in body emotions continuity attention introspection doubt volition memory heartbeat archive memory_backup openappa archestra vera_cpu wayfinder implement_spec tdd handoff to_spec workflow_chain attention_tropical memory_padic perception_nsa bioelectric_coupling multiway_volition memory_xna shadow_detector aihs_healing metabolic_attention chiral_continuity; do
            rm -f "$DATA/${name}.pid" "$DATA/${name}.pid.wrapper"
        done
        rm -f "$DATA/sense_poll.pid" "$DATA/sd_health_monitor.pid" "$DATA/xenobiological_daemon.pid" "$DATA/xenobiological_daemon.pid.wrapper"

        echo "=== All layer daemons stopped ==="
        ;;

    status)
        echo "=== Athena Daemon Status ==="
        echo ""
        echo "--- Session Mode ---"
        echo "  Mode: $(get_session_mode)"
        echo "  Degradation: $(get_degradation_state)"
        echo ""
        echo "--- Layer daemons ---"
        for name in body emotions continuity attention introspection doubt volition memory heartbeat archive memory_backup openappa archestra vera_cpu wayfinder implement_spec tdd handoff to_spec workflow_chain attention_tropical memory_padic perception_nsa bioelectric_coupling multiway_volition memory_xna shadow_detector aihs_healing metabolic_attention chiral_continuity; do
            pidfile="$DATA/${name}.pid"
            pid=$(cat "$pidfile" 2>/dev/null)
            if [ -n "$pid" ] && is_running "$pid"; then
                echo "  $name: RUNNING (PID $pid)"
            else
                echo "  $name: STOPPED"
                [ -n "$pid" ] && rm -f "$pidfile"
            fi
        done
        # senses — separate PID file (sense_poll.sh _daemon)
        if [ -f "$DATA/sense_poll.pid" ]; then
            spid=$(cat "$DATA/sense_poll.pid" 2>/dev/null)
            if [ -n "$spid" ] && is_running "$spid"; then
                echo "  senses: RUNNING (sense_poll.sh PID $spid)"
            else
                echo "  senses: STOPPED (stale PID file)"
            fi
        else
            echo "  senses: STOPPED"
        fi

        # xenobiological daemon — single process running all 10 layers
        if [ -f "$DATA/xenobiological_daemon.pid" ]; then
            xeno_pid=$(cat "$DATA/xenobiological_daemon.pid" 2>/dev/null)
            if [ -n "$xeno_pid" ] && is_running "$xeno_pid"; then
                echo "  xenobiological_daemon: RUNNING (PID $xeno_pid, 10 layers)"
            else
                echo "  xenobiological_daemon: STOPPED (stale PID file)"
            fi
        else
            echo "  xenobiological_daemon: STOPPED"
        fi
        echo ""
        echo "--- Layer data freshness ---"
        for name in body emotions continuity attention introspection doubt volition memory heartbeat archive memory_backup openappa archestra vera_cpu wayfinder implement_spec tdd handoff to_spec workflow_chain attention_tropical memory_padic perception_nsa bioelectric_coupling multiway_volition memory_xna shadow_detector aihs_healing metabolic_attention chiral_continuity; do
            statefile="$DATA/${name}.json"
            if [ -f "$statefile" ] && [ -s "$statefile" ]; then
                ts=$(STATEFILE="$statefile" python3 "$PYTHON_LIB/athena/get_state_timestamp.py" 2>/dev/null || echo 0)
                age=$(( $(date +%s) - ts ))
                if [ $age -lt 180 ]; then
                    echo "  $name: ✅ ${age}s ago"
                elif [ $age -lt 900 ]; then
                    echo "  $name: ⚠️  ${age}s ago"
                else
                    echo "  $name: ❌ ${age}s ago"
                fi
            else
                echo "  $name: ⚠️  no data file"
            fi
        done
        # Xenobiological layers (output from single-process daemon)
        for name in attention_tropical_output memory_padic_output perception_nsa_output bioelectric_output multiway_output memory_xna_output shadow_output aihs_output metabolic_output chiral_output; do
            statefile="$DATA/${name}.json"
            if [ -f "$statefile" ] && [ -s "$statefile" ]; then
                ts=$(STATEFILE="$statefile" python3 "$PYTHON_LIB/athena/get_state_timestamp.py" 2>/dev/null || echo 0)
                age=$(( $(date +%s) - ts ))
                if [ $age -lt 180 ]; then
                    echo "  $name: ✅ ${age}s ago"
                elif [ $age -lt 900 ]; then
                    echo "  $name: ⚠️  ${age}s ago"
                else
                    echo "  $name: ❌ ${age}s ago"
                fi
            else
                echo "  $name: ⚠️  no data file"
            fi
        done
        # senses freshness from senses.log
        if [ -f "$DATA/senses.log" ] && [ -s "$DATA/senses.log" ]; then
            last_ts=$(tail -1 "$DATA/senses.log" 2>/dev/null | python3 "$PYTHON_LIB/athena/get_senses_timestamp.py" 2>/dev/null || echo 0)
            sage=$(( $(date +%s) - last_ts ))
            if [ $sage -lt 120 ]; then
                echo "  senses: ✅ ${sage}s ago"
            elif [ $sage -lt 300 ]; then
                echo "  senses: ⚠️  ${sage}s ago"
            else
                echo "  senses: ❌ ${sage}s ago"
            fi
        else
            echo "  senses: ⚠️  no data"
        fi
        ;;

    logs)
        echo "=== Daemon Logs ==="
        ls -la "$LOGDIR" 2>/dev/null
        echo ""
        for f in "$LOGDIR"/*.log; do
            [ -f "$f" ] || continue
            echo "--- $(basename $f) ---"
            tail -3 "$f"
            echo ""
        done
        ;;

    one-shot)
        echo "=== Running all layers once ==="
        echo "--- body ---"
        "$BIN/body_update.sh" poll 2>&1 | head -5
        echo "--- emotions ---"
        "$BIN/emotions_update.sh" read 2>&1 | head -5
        echo "--- continuity ---"
        "$BIN/continuity_update.sh" read 2>&1 | head -5
        echo "--- senses ---"
        "$BIN/sense_poll.sh" one-shot 2>&1 | python3 -m json.tool 2>/dev/null | head -5
        echo "--- attention ---"
        "$BIN/attention_update.sh" read 2>&1 | head -5
        echo "--- openappa ---"
        "$BIN/openappa_update.sh" poll 2>&1
        echo "--- archestra ---"
        "$BIN/archestra_update.sh" poll 2>&1
        echo "--- vera_cpu ---"
        "$BIN/vera_cpu_update.sh" poll 2>&1
        # Xenobiological layers
        echo "--- attention_tropical ---"
        "$BIN/attention_tropical.sh" allocate 2>&1 | head -5
        echo "--- memory_padic ---"
        "$BIN/memory_padic.sh" consolidate 2>&1 | head -5
        echo "--- perception_nsa ---"
        "$BIN/perception_nsa.sh" process 2>&1 | head -5
        echo "--- bioelectric_coupling ---"
        "$BIN/bioelectric_coupling.sh" step 2>&1 | head -5
        echo "--- multiway_volition ---"
        "$BIN/multiway_volition.sh" evolve 2>&1 | head -5
        echo "--- memory_xna ---"
        "$BIN/memory_xna.sh" consolidate 2>&1 | head -5
        echo "--- shadow_detector ---"
        "$BIN/shadow_detector.sh" scan 2>&1 | head -5
        echo "--- aihs_healing ---"
        "$BIN/aihs_healing.sh" heal 2>&1 | head -5
        echo "--- metabolic_attention ---"
        "$BIN/metabolic_attention.sh" process 2>&1 | head -5
        echo "--- chiral_continuity ---"
        "$BIN/chiral_continuity.sh" validate 2>&1 | head -5
        echo "=== Done ==="
        ;;

    health)
        echo "=== Athena Storage Health ==="
        bash "$BIN/sdcard_health.sh" status
        echo ""
        echo "--- Layer data freshness ---"
        for name in body emotions continuity attention introspection doubt volition memory heartbeat senses archive memory_backup openappa archestra vera_cpu attention_tropical memory_padic perception_nsa bioelectric_coupling multiway_volition memory_xna shadow_detector aihs_healing metabolic_attention chiral_continuity; do
            statefile="$DATA/${name}.json"
            if [ -f "$statefile" ]; then
                ts=$(STATEFILE="$statefile" python3 "$PYTHON_LIB/athena/get_state_timestamp.py" 2>/dev/null || echo 0)
                age=$(( $(date +%s) - ts ))
                if [ $age -lt 180 ]; then echo "  $name: ✅ ${age}s ago ($DATA)";
                elif [ $age -lt 900 ]; then echo "  $name: ⚠️  ${age}s ago ($DATA)";
                else echo "  $name: ❌ ${age}s ago ($DATA)"; fi
            else
                echo "  $name: ❌ missing ($DATA)"
            fi
        done
        ;;
    restart)
        echo "=== Athena Daemon: Restarting all layers ==="
        bash "$BIN/athena_daemon.sh" stop
        sleep 1
        bash "$BIN/athena_daemon.sh" start
        ;;

    degraded)
        echo "=== Athena Degradation State ==="
        DEGRADATION_FILE="$DEGRADATION_FILE" python3 "$PYTHON_LIB/athena/show_degradation.py" 2>/dev/null
        ;;

    session)
        case "${2:-help}" in
            active)
                set_session_mode "interactive"
                echo "Session mode: interactive"
                record_screen_event "session_active" "user_interaction"
                ;;
            quiet)
                set_session_mode "quiet"
                echo "Session mode: quiet"
                record_screen_event "session_quiet" "no_activity"
                ;;
            idle)
                set_session_mode "idle"
                echo "Session mode: idle"
                record_screen_event "session_idle" "screen_off_or_lock"
                ;;
            help|*)
                echo "Usage: athena_daemon.sh session {active|quiet|idle}"
                echo "  active — user is interacting (500ms-2s intervals)"
                echo "  quiet  — low activity (2-5s cheap checks)"
                echo "  idle   — screen off/locked (event-triggered only)"
                ;;
        esac
        ;;

    feedback)
        show_feedback
        ;;

    help|--help|-h|*)
        echo "Usage: athena_daemon.sh {start|stop|status|restart|logs|one-shot|feedback|degraded|session}"
        echo ""
        echo "Commands:"
        echo "  start      Launch all layer pollers with event-driven scheduling"
        echo "  stop       Stop all daemons (SIGTERM)"
        echo "  status     Show daemon PIDs + layer data freshness + degradation state"
        echo "  logs       Tail daemon log files"
        echo "  restart    Stop and restart all layer daemons"
        echo "  one-shot   Run all layers once and exit"
        echo "  degraded   Show current degradation state"
        echo "  session    Set session mode (active/quiet/idle)"
        echo "  feedback   Show layer performance stats"
        echo ""
        echo "Scheduling: Event-driven adaptive (arm set {250ms, 500ms, 1s, 2s, 5s})"
        echo "  Active: 250ms-500ms, Interactive: 500ms-2s, Quiet: 2-5s, Idle: event-triggered"
        echo ""
        echo "Degradation ladder: normal → conserve → minimal → suspended → safe_shutdown"
        echo ""
        echo "Layer intervals (override with env vars):"
        echo "  ATHENA_BODY_INTERVAL    (default 120s)"
        echo "  ATHENA_EMO_INTERVAL     (default 120s)"
        echo "  ATHENA_CONT_INTERVAL    (default 120s)"
        echo "  ATHENA_ATTN_INTERVAL    (default 60s)"
        echo "  ATHENA_OPENAPPA_INTERVAL (default 240s)"
        echo "  ATHENA_ARCHESTRA_INTERVAL (default 120s)"
        echo "  ATHENA_VERA_CPU_INTERVAL (default 180s)"
        echo "  ATHENA_WAYFINDER_INTERVAL (default 90s)"
        echo "  ATHENA_IMPLEMENT_SPEC_INTERVAL (default 120s)"
        echo "  ATHENA_TDD_INTERVAL      (default 60s)"
        echo "  ATHENA_HANDOFF_INTERVAL  (default 180s)"
        echo "  ATHENA_TO_SPEC_INTERVAL  (default 60s)"
        echo "  ATHENA_WORKFLOW_CHAIN_INTERVAL (default 180s)"
        # Xenobiological layer intervals
        echo "  ATHENA_ATTN_TROPICAL_INTERVAL (default 60s)"
        echo "  ATHENA_MEM_PADIC_INTERVAL     (default 120s)"
        echo "  ATHENA_PERCEPTION_NSA_INTERVAL (default 60s)"
        echo "  ATHENA_BIOELECTRIC_INTERVAL    (default 120s)"
        echo "  ATHENA_MULTIWAY_INTERVAL       (default 120s)"
        echo "  ATHENA_MEM_XNA_INTERVAL        (default 180s)"
        echo "  ATHENA_SHADOW_INTERVAL         (default 300s)"
        echo "  ATHENA_AIHS_INTERVAL           (default 60s)"
        echo "  ATHENA_METABOLIC_INTERVAL      (default 60s)"
        echo "  ATHENA_CHIRAL_INTERVAL         (default 120s)"
        echo ""
        echo "Enigma/Bombe: intervals adapt based on success/failure feedback."
        ;;
esac
