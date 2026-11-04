#!/bin/bash
# Athena Master Control Panel

STATUS_FILE="/opt/athena/state/daemon.log"
DAEMON_PROC=$(pgrep -f xenobiological_daemon.py)

show_status() {
    echo "--- Athena System Status ---"
    if [ -n "$DAEMON_PROC" ]; then
        echo "Daemon: RUNNING (PID: $DAEMON_PROC)"
    else
        echo "Daemon: STOPPED"
    fi
    echo "State Store: /opt/athena/state/"
    echo "Latest Decision: $(grep "decision" /opt/athena/state/volition_decision.json | cut -d'"' -f4)"
    echo "---------------------------"
}

start_daemon() {
    if [ -n "$DAEMON_PROC" ]; then
        echo "Daemon is already running."
    else
        nohup python3 /opt/athena/lib/athena/xenobiological_daemon.py > /opt/athena/state/daemon.log 2>&1 &
        echo "Daemon started."
    fi
}

stop_daemon() {
    if [ -n "$DAEMON_PROC" ]; then
        kill $DAEMON_PROC
        echo "Daemon stopped."
    else
        echo "Daemon is not running."
    fi
}

run_reflection() {
    echo "Triggering reflection cycle..."
    /opt/athena/bin/athena_reflect.py
}

run_reasoning() {
    echo "Triggering reasoning cycle..."
    /opt/athena/bin/athena_reasoning_loop.py
}

case "$1" in
    direct) read -p "Enter directive: " dir; /opt/athena/bin/athena_directive.sh "$dir" ;;
    archive) /opt/athena/bin/athena_archive.sh ;;
    status) show_status ;;
    start) start_daemon ;;
    stop) stop_daemon ;;
    reflect) run_reflection ;;
    reason) run_reasoning ;;
    dash) /opt/athena/bin/athena_dashboard.sh ;;
    *) echo "Usage: athena_ctrl {status|start|stop|reflect|reason|dash}" ;;
esac
