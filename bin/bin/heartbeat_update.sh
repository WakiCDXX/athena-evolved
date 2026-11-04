#!/usr/bin/bash
BASE_DIR="/root"
source "$BASE_DIR/.local/bin/athena_env.sh" 2>/dev/null
# heartbeat_update.sh — heartbeat/alert daemon for Athena.
# Usage:
#   heartbeat_update.sh check  → run health check, write heartbeat.json
#   heartbeat_update.sh read   → print heartbeat.json
#   heartbeat_update.sh alert  → show only active alerts

set -o pipefail

DATA="/opt/athena/state"
HEARTBEAT="$DATA/heartbeat.json"
STALE_THRESHOLD=900
CRITICAL_THRESHOLD=1800
export CRITICAL_THRESHOLD STALE_THRESHOLD

now() { date +%s; }

check() {
    export ATHENA_HEARTBEAT_PATH="$HEARTBEAT"
    export ATHENA_DATA_DIR="$DATA"
    export ATHENA_CRITICAL_THRESHOLD="$CRITICAL_THRESHOLD"
    export ATHENA_STALE_THRESHOLD="$STALE_THRESHOLD"
    python3 "$PYTHON_LIB/athena/heartbeat_check.py" 2>/dev/null
}

case "${1:-check}" in
    check)
        check
        ;;
    read)
        export JSON_SET_PATH="$HEARTBEAT" JSON_SET_KEY="last_updated" JSON_SET_VAL="$(now)"
        python3 "$PYTHON_LIB/athena/json_set.py" 2>/dev/null
        [ -f "$HEARTBEAT" ] && cat "$HEARTBEAT" || echo '{"overall":"no-data"}'
        ;;
    alert)
        export JSON_GET_PATH="$HEARTBEAT" JSON_GET_KEY="alerts"
        python3 "$PYTHON_LIB/athena/heartbeat_alerts.py" 2>/dev/null || echo "No heartbeat data yet."
        ;;
    *)
        echo "Usage: $0 {check|read|alert}" >&2
        exit 1
        ;;
esac
