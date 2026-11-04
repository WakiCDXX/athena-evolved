#!/usr/bin/bash
# athena_auto.sh — Autonomous self-management daemon.
#
# Periodically checks all consciousness layers, assesses state,
# decides what action to take, and executes it. Persists decisions
# to session_context.json so nothing is lost after compaction.
#
# Usage:
#   athena auto start   — launch autonomous management loop
#   athena auto stop    — stop the loop
#   athena auto status  — show auto daemon status + recent decisions
#   athena auto run     — run one assessment cycle and exit
#   athena auto trigger "<phrase>" — evaluate a trigger phrase immediately
#   athena auto triggers — list all registered trigger words
#
# The loop runs every AUTO_INTERVAL seconds (default 300s).

set -o pipefail

BASE="/root"
source "$BASE/.local/bin/athena_env.sh" 2>/dev/null
BIN="$BASE/.local/bin"
DATA="/opt/athena/state"
PIDFILE="$DATA/athena_auto.pid"
LOGDIR="$DATA/daemon_logs"
TRIGGER_FILE="$DATA/triggers.json"
INTERVAL="${ATHENA_AUTO_INTERVAL:-300}"

mkdir -p "$LOGDIR"

now() { date +%s; }

is_running() {
    local pid="$1"
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

# --- external helper scripts --------------------------------------------

handle_trigger() {
    local phrase="$1"
    export ATHENA_TRIGGERS_PATH="$TRIGGER_FILE"
    export ATHENA_TRIGGER_PHRASE="$phrase"
    python3 "$PYTHON_LIB/athena/find_triggers.py" 2>/dev/null
}

assess() {
    export ASSESS_DATA_DIR="$DATA"
    python3 "$PYTHON_LIB/athena/auto_assess.py" 2>/dev/null
}

execute_action() {
    local action="$1"
    local assessment_json="$2"

    case "$action" in
        restart_critical_layers)
            local tmpfile
            tmpfile=$(mktemp "$DATA/.tmp_XXXXXX.json")
            echo "$assessment_json" > "$tmpfile"
            export EXEC_ACTION="$action" EXEC_TMPFILE="$tmpfile" EXEC_DATA_DIR="$DATA"
            python3 "$PYTHON_LIB/athena/auto_restart.py" 2>/dev/null
            rm -f "$tmpfile"
            ;;
        refresh_stale_layers)
            local tmpfile
            tmpfile=$(mktemp "$DATA/.tmp_XXXXXX.json")
            echo "$assessment_json" > "$tmpfile"
            export EXEC_ACTION="$action" EXEC_TMPFILE="$tmpfile" EXEC_DATA_DIR="$DATA"
            python3 "$PYTHON_LIB/athena/auto_refresh.py" 2>/dev/null
            rm -f "$tmpfile"
            ;;
        review_concerns)
            echo "Auto-review: $assessment_json" >> "$LOGDIR/auto.log"
            ;;
        process_tasks)
            echo "Auto-processing tasks..." >> "$LOGDIR/auto.log"
            ;;
        idle)
            bash "$BIN/heartbeat_update.sh" check >/dev/null 2>&1
            ;;
    esac
}

persist_decision() {
    local assessment="$1"
    local tmpfile
    tmpfile=$(mktemp "$DATA/.tmp_XXXXXX.json")
    echo "$assessment" > "$tmpfile"
    export PERSIST_PATH="$DATA/session_context.json" PERSIST_TMPFILE="$tmpfile"
    python3 "$PYTHON_LIB/athena/auto_persist.py" 2>/dev/null
}

# --- main loop -------------------------------------------------------------

loop() {
    while :; do
        assessment=$(assess)
        echo "=== Auto cycle: $(date) ===" >> "$LOGDIR/auto.log"
        echo "Assessment: $assessment" >> "$LOGDIR/auto.log"
        for action in $(echo "$assessment" | python3 "$PYTHON_LIB/athena/extract_actions.py" 2>/dev/null); do
            execute_action "$action" "$assessment" >> "$LOGDIR/auto.log" 2>&1
        done
        persist_decision "$assessment"
        sleep "$INTERVAL"
    done
}

# --- layer state display helper -------------------------------------------

show_layer_state() {
    local layer_file="$1"
    export AUTO_LAYER_FILE="$layer_file"
    python3 "$PYTHON_LIB/athena/auto_layer_state.py" 2>/dev/null
}

show_triggers_list() {
    export AUTO_TRIGGER_FILE="$TRIGGER_FILE"
    python3 "$PYTHON_LIB/athena/auto_triggers_show.py" 2>/dev/null
}

# --- dispatch --------------------------------------------------------------

case "${1:-help}" in
    auto)
        shift
        case "${1:-help}" in
            start)
                if is_running "$(cat "$PIDFILE" 2>/dev/null)"; then
                    echo "Auto daemon already running (PID $(cat "$PIDFILE"))"
                    exit 0
                fi
                bash -c "while :; do $BIN/athena_auto.sh run >/dev/null 2>&1; sleep $INTERVAL & wait \$!; done" &
                echo $! > "$PIDFILE"
                echo "Athena auto daemon started (PID $(cat "$PIDFILE"), ${INTERVAL}s interval)"
                ;;
            stop)
                pid=$(cat "$PIDFILE" 2>/dev/null)
                if [ -n "$pid" ] && is_running "$pid"; then
                    kill -TERM "$pid" 2>/dev/null
                    sleep 1
                    is_running "$pid" && kill -TERM "$pid" 2>/dev/null
                    echo "Auto daemon stopped (was PID $pid)"
                else
                    echo "Auto daemon not running"
                fi
                rm -f "$PIDFILE"
                ;;
            status)
                pid=$(cat "$PIDFILE" 2>/dev/null)
                if [ -n "$pid" ] && is_running "$pid"; then
                    echo "Auto daemon: RUNNING (PID $pid)"
                else
                    echo "Auto daemon: STOPPED"
                fi
                echo ""
                echo "--- Last decisions ---"
                export AUTO_SESSION_FILE="$DATA/session_context.json"
                python3 "$PYTHON_LIB/athena/auto_last_decision.py" 2>/dev/null
                echo ""
                echo "--- Recent log ---"
                tail -5 "$LOGDIR/auto.log" 2>/dev/null || echo "  No logs yet."
                ;;
            run)
                assessment=$(assess)
                echo "=== Auto cycle: $(date) ===" >> "$LOGDIR/auto.log"
                echo "Assessment: $assessment" >> "$LOGDIR/auto.log"
                for action in $(echo "$assessment" | python3 "$PYTHON_LIB/athena/extract_actions.py" 2>/dev/null); do
                    execute_action "$action" "$assessment" >> "$LOGDIR/auto.log" 2>&1
                done
                persist_decision "$assessment"
                echo "$assessment"
                ;;
            help|--help|-h|*)
                echo "Usage: athena_auto.sh auto {start|stop|status|run|help}"
                ;;
        esac
        ;;
    start)
        if is_running "$(cat "$PIDFILE" 2>/dev/null)"; then
            echo "Auto daemon already running (PID $(cat "$PIDFILE"))"
            exit 0
        fi
        bash -c "while :; do $BIN/athena_auto.sh run >/dev/null 2>&1; sleep $INTERVAL & wait \$!; done" &
        echo $! > "$PIDFILE"
        echo "Athena auto daemon started (PID $(cat "$PIDFILE"), ${INTERVAL}s interval)"
        ;;
    stop)
        pid=$(cat "$PIDFILE" 2>/dev/null)
        if [ -n "$pid" ] && is_running "$pid"; then
            kill -TERM "$pid" 2>/dev/null
            sleep 1
            is_running "$pid" && kill -TERM "$pid" 2>/dev/null
            echo "Auto daemon stopped (was PID $pid)"
        else
            echo "Auto daemon not running"
        fi
        rm -f "$PIDFILE"
        ;;
    status)
        pid=$(cat "$PIDFILE" 2>/dev/null)
        if [ -n "$pid" ] && is_running "$pid"; then
            echo "Auto daemon: RUNNING (PID $pid)"
        else
            echo "Auto daemon: STOPPED"
        fi
        echo ""
        echo "--- Last decisions ---"
        export AUTO_SESSION_FILE="$DATA/session_context.json"
        python3 "$PYTHON_LIB/athena/auto_last_decision.py" 2>/dev/null
        echo ""
        echo "--- Recent log ---"
        tail -5 "$LOGDIR/auto.log" 2>/dev/null || echo "  No logs yet."
        ;;
    run)
        assessment=$(assess)
        echo "=== Auto cycle: $(date) ===" >> "$LOGDIR/auto.log"
        echo "Assessment: $assessment" >> "$LOGDIR/auto.log"
        for action in $(echo "$assessment" | python3 "$PYTHON_LIB/athena/extract_actions.py" 2>/dev/null); do
            execute_action "$action" "$assessment" >> "$LOGDIR/auto.log" 2>&1
        done
        persist_decision "$assessment"
        echo "$assessment"
        ;;
    trigger)
        [ -z "$2" ] && { echo "Usage: athena_auto.sh trigger \"<phrase>\""; exit 1; }
        action=$(handle_trigger "$2")
        if [ "$action" = "unknown" ]; then
            echo "Unknown trigger: $2"
            echo "Available triggers:"
            show_triggers_list
            exit 1
        fi
        echo "Trigger: $2 -> Action: $action"
        case "$action" in
            full_self_assessment)
                bash "$BIN/athena_auto.sh" run
                ;;
            body_check)
                bash "$BIN/body_update.sh" check
                ;;
            battery_check)
                bash "$BIN/sense_poll.sh" battery
                ;;
            list_concerns)
                show_layer_state "$DATA/attention.json" | python3 "$PYTHON_LIB/athena/auto_attention_concerns.py" 2>/dev/null
                ;;
            list_tasks)
                export AUTO_SESSION_FILE="$DATA/session_context.json"
                python3 "$PYTHON_LIB/athena/auto_session_tasks.py" 2>/dev/null
                ;;
            refresh_stale_layers)
                bash "$BIN/athena_daemon.sh" one-shot
                ;;
            restart_critical_layers)
                for layer in heartbeat body emotions continuity attention introspection doubt volition memory senses archive memory_backup; do
                    rm -f "$DATA/${layer}.pid" "$DATA/${layer}.pid.wrapper" 2>/dev/null
                done
                if [ -f "$DATA/sense_poll.pid" ]; then
                    spid=$(cat "$DATA/sense_poll.pid" 2>/dev/null)
                    if [ -n "$spid" ] && kill -0 "$spid" 2>/dev/null; then
                        kill -TERM "$spid" 2>/dev/null
                        sleep 0.5
                        kill -KILL "$spid" 2>/dev/null
                    fi
                    rm -f "$DATA/sense_poll.pid"
                fi
                setsid bash -c "$BIN/sense_poll.sh _daemon" >/dev/null 2>&1 &
                echo "Restarted senses; other daemons self-heal on next cycle"
                ;;
            show_status)
                bash "$BIN/athena_daemon.sh" status
                ;;
            run_full_assessment)
                bash "$BIN/athena_auto.sh" run
                ;;
            self_introspection)
                bash "$BIN/introspection_update.sh" read
                ;;
            memory_check)
                export AUTO_MEMORY_FILE="$DATA/memory.json"
                python3 "$PYTHON_LIB/athena/auto_memory_dump.py" 2>/dev/null
                ;;
            senses_check)
                export AUTO_SENSES_FILE="$DATA/senses.json"
                python3 "$PYTHON_LIB/athena/auto_senses_dump.py" 2>/dev/null
                ;;
            emotions_check)
                export AUTO_EMOTIONS_FILE="$DATA/emotions.json"
                python3 "$PYTHON_LIB/athena/auto_emotions_dump.py" 2>/dev/null
                ;;
            volition_check)
                export AUTO_VOLITION_FILE="$DATA/volition.json"
                python3 "$PYTHON_LIB/athena/auto_volition_dump.py" 2>/dev/null
                ;;
            attention_check)
                export AUTO_ATTENTION_FILE="$DATA/attention.json"
                python3 "$PYTHON_LIB/athena/auto_attention_dump.py" 2>/dev/null
                ;;
            doubt_check)
                export AUTO_DOUBT_FILE="$DATA/doubt.json"
                python3 "$PYTHON_LIB/athena/auto_doubt_dump.py" 2>/dev/null
                ;;
            continuity_check)
                export AUTO_CONTINUITY_FILE="$DATA/continuity.json"
                python3 "$PYTHON_LIB/athena/auto_continuity_dump.py" 2>/dev/null
                ;;
            introspection_check)
                bash "$BIN/introspection_update.sh" read
                ;;
            heartbeat_check)
                export AUTO_HEARTBEAT_FILE="$DATA/heartbeat.json"
                python3 "$PYTHON_LIB/athena/auto_heartbeat_dump.py" 2>/dev/null
                ;;
            stop_daemon)
                bash "$BIN/athena_daemon.sh" stop
                ;;
            start_daemon)
                bash "$BIN/athena_daemon.sh" start
                ;;
            *)
                echo "Action '$action' not yet implemented as trigger"
                ;;
        esac
        ;;
    triggers)
        echo "Registered trigger words:"
        show_triggers_list
        ;;
    help|--help|-h|*)
        echo "Usage: athena_auto.sh {start|stop|status|run|trigger|triggers|help}"
        echo ""
        echo "Commands:"
        echo "  start   Launch autonomous management daemon"
        echo "  stop    Stop the autonomous daemon"
        echo "  status  Show daemon status + last decisions"
        echo "  run     Run one assessment cycle and exit"
        echo "  trigger \"<phrase>\"  Evaluate a trigger phrase"
        echo "  triggers  List all registered trigger words"
        echo ""
        echo "Interval: ATHENA_AUTO_INTERVAL=${INTERVAL}s"
        ;;
esac
