#!/usr/bin/bash
# athena_daemon_msafe.sh — memory-safe daemon manager (OpenAPPA-focused).
#
# Purpose: keep the daemon running persistently on a low-RAM device
# (~1.8GB, ~700MB available) without triggering Android's OOM/SIGKILL.
#
# Enigma/Bombe Principle Applied: "Feed results back and redesign."
#
# DESIGN: Instead of all 13 persistent workers, start only the essential
# layers required for OpenAPPA telemetry — openappa, archestra, vera_cpu —
# plus the light heartbeat/attention/archive layers. Everything else is run
# on-demand via one-shot. The start gate refuses to launch if <400MB free.
#
# Usage:
#   athena_daemon_msafe.sh start      — launch essential layers only
#   athena_daemon_msafe.sh stop       — stop all daemons (SIGTERM)
#   athena_daemon_msafe.sh status     — show daemon PIDs + freshness
#   athena_daemon_msafe.sh logs       — tail all log files
#   athena_daemon_msafe.sh one-shot   — run ALL layers once and exit
#   athena_daemon_msafe.sh feedback   — show layer performance stats
#   athena_daemon_msafe.sh degraded   — show degradation state
#   athena_daemon_msafe.sh session    — set session mode (active/idle/quiet)
#
# Essential persistent layers (memory-safe):
#   openappa  — openappa_update.sh poll  (default 240s)
#   archestra — archestra_update.sh poll  (default 120s)
#   vera_cpu  — vera_cpu_update.sh poll   (default 180s)
#   heartbeat — heartbeat_update.sh check (default 120s)
#   attention — attention_update.sh read  (default 60s)
#   archive   — archive_maintenance.sh    (default 1800s)
#
# Optional heavy layers can be added back on-demand:
#   body, emotions, continuity, introspection, doubt, volition, memory

set -o pipefail

# --- resource limits: hard guard against RAM exhaustion -------------------
# Max 50% virtual memory per process (prevents runaway bash/python3 forks).
# Max 200 user processes system-wide (keeps PID table lean).
ulimit -v 524288 2>/dev/null || true      # 512MB vmem cap / worker
ulimit -u 200 2>/dev/null || true         # PID count cap

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

# --- layer startup with degradation awareness -----------------------

start_subshell() {
    local name="$1" cmd="$2" interval="$3"
    local pidfile="$DATA/${name}.pid"
    local adaptive="${4:-true}"  # Enable event-driven scheduling by default

    # Stop existing if any — kill by pidfile only
    local old_pid
    old_pid=$(cat "$pidfile" 2>/dev/null)
    if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
        kill_tree_by_pid "$old_pid"
    fi
    rm -f "$pidfile" "$pidfile.wrapper" 2>/dev/null

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
    local pid
    pid=$(cat "$pidfile" 2>/dev/null)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        kill_tree_by_pid "$pid"
        echo "  $name: stopped (was PID $pid)"
    else
        [ -n "$pid" ] && echo "  $name: not running (stale PID $pid)"
        [ -z "$pid" ] && echo "  $name: no PID file"
    fi
    rm -f "$pidfile" "$pidfile.wrapper"
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

case "${1:-help}" in
    start)
        echo "=== Athena Daemon: Memory-safe mode (essential OpenAPPA layers) ==="
        echo "  Persistent layers: openappa, archestra, vera_cpu, heartbeat, attention, archive"
        echo "  Heavy layers (body, emotions, continuity, introspection, doubt, volition, memory): on-demand only, run via one-shot"
        echo ""

        # --- memory-safe start gate: refuse if <400MB free (512000KB) ---
        avail_kb=$(grep MemAvailable /proc/meminfo 2>/dev/null | awk '{print $2}')
        if [ -z "$avail_kb" ] || [ "$avail_kb" -lt 512000 ]; then
            echo "  START BLOCKED: only ${avail_kb:-0}KB available (need >=512000KB = 500MB)."
            echo "  Free RAM (close other apps) and run this command again."
            return 1
        fi
        echo "  Memory gate OK: ${avail_kb}KB available."

        # --- deprioritize daemon so openclaude stays responsive ---
        nice -n 19 "$0" stop >/dev/null 2>&1
        sleep 1

        echo "=== Athena Daemon: Starting essential layers ==="
        echo "  Scheduling mode: $(get_session_mode)"

        # Clean up any orphaned processes from previous crashes/restarts
        for name in openappa archestra vera_cpu heartbeat attention archive; do
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

        # Set global event-driven interval floor so persistent workers never
        # poll faster than MIN_EVENT_INTERVAL (prevents fork-storm OOM).
        export MIN_EVENT_INTERVAL=3
        echo "  Event-driven polling floor: $MIN_EVENT_INTERVALs/worker (prevents OOM)"

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

        # Load degradation config
        apply_degradation

        # Compile gate: verify the essential self-modification-prone scripts
        # before loading — full gate is expensive (~13 scripts), so msafe only
        # checks the layers it actually launches.
        echo "  Running compile gate on essential layer scripts..."
        for _script in "$BIN/openappa_update.sh" "$BIN/archestra_update.sh" "$BIN/vera_cpu_update.sh" "$BIN/heartbeat_update.sh" "$BIN/attention_update.sh" "$BIN/archive_maintenance.sh"; do
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

        # Launch essential OpenAPPA layers only — small persistent footprint.
        # Each worker is a single persistent bash+python3 process (~6-8MB each)
        # with a hard 512MB vmem cap (ulimit -v above). Launch sequentially,
        # no sleep needed between — msafe is already nice'd and gated on RAM.
        if [ "$local_degraded" = "normal" ] || [ "$local_degraded" = "conserve" ]; then
            # OpenAPPA telemetry layers (the reason this daemon exists)
            start_subshell "openappa" "$BIN/openappa_update.sh poll" "${INTERVAL_OPENAPPA:-240}"
            start_subshell "archestra" "$BIN/archestra_update.sh poll" "${INTERVAL_ARCHESTRA:-120}"
            start_subshell "vera_cpu" "$BIN/vera_cpu_update.sh poll" "${INTERVAL_VERA_CPU:-180}"

            # Essential housekeeping layers (small footprint)
            start_subshell "heartbeat" "$BIN/heartbeat_update.sh check" "${INTERVAL_HB:-120}"
            start_subshell "attention" "$BIN/attention_update.sh read" "${INTERVAL_ATTN:-60}"
            start_subshell "archive" "$BIN/archive_maintenance.sh" "${INTERVAL_ARCHIVE:-1800}"

            echo "=== Essential OpenAPPA layers started (memory-safe) ==="
        else
            # degraded/minimal: keep only the lightest monitor
            start_subshell "attention" "$BIN/attention_update.sh read" "${INTERVAL_ATTN:-60}"
            echo "=== Minimal layer daemons started ==="
        fi

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
        echo "=== Athena Daemon: Stopping essential layers ==="
        release_wake_lock

        for name in openappa archestra vera_cpu heartbeat attention archive; do
            stop_subshell "$name"
        done

        if [ -f "$DATA/sense_poll.pid" ]; then
            spid=$(cat "$DATA/sense_poll.pid" 2>/dev/null)
            if [ -n "$spid" ] && kill -0 "$spid" 2>/dev/null; then
                kill_tree_by_pid "$spid"
                echo "  senses: stopped (was PID $spid)"
            fi
            rm -f "$DATA/sense_poll.pid"
        fi

        if [ -f "$DATA/sd_health_monitor.pid" ]; then
            sdpid=$(cat "$DATA/sd_health_monitor.pid" 2>/dev/null)
            if [ -n "$sdpid" ] && kill -0 "$sdpid" 2>/dev/null; then
                kill_tree_by_pid "$sdpid"
                echo "  sd_health_monitor: stopped (was PID $sdpid)"
            fi
            rm -f "$DATA/sd_health_monitor.pid"
        fi

        echo "=== Essential layer daemons stopped ==="
        ;;

    status)
        echo "=== Athena Daemon Status ==="
        echo ""
        echo "--- Session Mode ---"
        echo "  Mode: $(get_session_mode)"
        echo "  Degradation: $(get_degradation_state)"
        echo ""
        echo "--- Layer daemons (essential OpenAPPA) ---"
        for name in openappa archestra vera_cpu heartbeat attention archive; do
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
        echo ""
        echo "--- Layer data freshness (essential OpenAPPA) ---"
        for name in openappa archestra vera_cpu heartbeat attention archive; do
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
        echo "=== Running ALL layers once (on-demand, for heavy layers) ==="
        echo "  This pulls in body/emotions/continuity/introspection/doubt/volition/memory once."
        "$BIN/body_update.sh" poll >/dev/null 2>&1 && echo "  body: ok"
        "$BIN/emotions_update.sh" read >/dev/null 2>&1 && echo "  emotions: ok"
        "$BIN/continuity_update.sh" read >/dev/null 2>&1 && echo "  continuity: ok"
        "$BIN/sense_poll.sh" one-shot >/dev/null 2>&1 && echo "  senses: ok"
        "$BIN/introspection_update.sh" report >/dev/null 2>&1 && echo "  introspection: ok"
        "$BIN/doubt_update.sh" decay >/dev/null 2>&1 && echo "  doubt: ok"
        "$BIN/volition.sh" read >/dev/null 2>&1 && echo "  volition: ok"
        "$BIN/memory_consolidation.sh" consolidate >/dev/null 2>&1 && echo "  memory: ok"
        echo "=== Done ==="
        ;;

    health)
        echo "=== Athena Storage Health ==="
        bash "$BIN/sdcard_health.sh" status
        echo ""
        echo "--- Layer data freshness ---"
        for name in openappa archestra vera_cpu heartbeat attention archive; do
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
        echo ""
        echo "Enigma/Bombe: intervals adapt based on success/failure feedback."
        ;;
esac
