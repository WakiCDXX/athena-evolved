#!/usr/bin/bash
BASE_DIR="/root"
source "$BASE_DIR/.local/bin/athena_env.sh" 2>/dev/null
# doubt_update.sh — Layer 8: Doubt (self-doubt calibration) for Athena.
# Usage:
#   doubt_update.sh read                           → prints JSON
#   doubt_update.sh decay                          → drift confidence toward neutral
#   doubt_update.sh decay                          → drift confidence toward neutral
#   doubt_update.sh add <category> <detail> [level]→ add a doubt entry
#   doubt_update.sh check <answer>                 → validate against calibration
#   doubt_update.sh query <question>               → targeted doubt query
#   doubt_update.sh history                        → show doubt history
#   doubt_update.sh calibrate                      → run calibration update

set -o pipefail

DATA_DIR="/opt/athena/state"
STATE="$DATA_DIR/doubt.json"
LOG_FILE="$DATA_DIR/doubt_log.jsonl"

mkdir -p "$DATA_DIR"
touch "$STATE" "$LOG_FILE"

# Initialize doubt.json if empty
if [ ! -s "$STATE" ]; then
    export JSON_INIT_PATH="$STATE" JSON_INIT_TS="$(now)"
    python3 "$PYTHON_LIB/athena/json_init.py" 2>/dev/null
fi

now() { date +%s; }

# --- helpers for confidence drift (0-1 scale) -------------------------------

json_get() {
    local key=$1
    export JSON_GET_PATH="$STATE" JSON_GET_KEY="$key"
    python3 "$PYTHON_LIB/athena/json_get.py" 2>/dev/null
}

json_set() {
    local key=$1 val=$2
    export JSON_SET_PATH="$STATE" JSON_SET_KEY="$key" JSON_SET_VAL="$val"
    python3 "$PYTHON_LIB/athena/json_set.py" 2>/dev/null
}

clamp() {
    local v=$1
    export JSON_CLAMP_VAL="$v" JSON_CLAMP_LO="0" JSON_CLAMP_HI="1"
    python3 "$PYTHON_LIB/athena/json_clamp.py" 2>/dev/null
}

drift_toward() {
    local cur=$1 target=$2 step=0.1
    python3 -c "print(max(0,min(1,$1+($2-$1)*$3)))" 2>/dev/null
}

case "${1:-read}" in
    read)
        export JSON_SET_PATH="$STATE" JSON_SET_KEY="last_updated" JSON_SET_VAL="$(now)"
        python3 "$PYTHON_LIB/athena/json_set.py" 2>/dev/null
        cat "$STATE"
        ;;

    add)
        [ -z "$2" ] && { echo "usage: $0 add <category> <detail> [level 1-10]" >&2; exit 1; }
        export DOUBT_PATH="$STATE"
        export DOUBT_TS="$(now)"
        export DOUBT_CATEGORY="$2"
        export DOUBT_DETAIL="$3"
        export DOUBT_LEVEL="${4:-5}"
        python3 "$PYTHON_LIB/athena/doubt_add.py" 2>/dev/null
        echo "Doubt added: $2 (${4:-5}/10)"
        ;;

    check)
        [ -z "$2" ] && { echo "usage: $0 check <answer>" >&2; exit 1; }
        export DOUBT_PATH="$STATE"
        export DOUBT_ANSWER="$2"
        export DOUBT_TS="$(now)"
        export DOUBT_LOG_FILE="$LOG_FILE"
        python3 "$PYTHON_LIB/athena/doubt_check.py" 2>/dev/null
        ;;

    query)
        [ -z "$2" ] && { echo "usage: $0 query <question>" >&2; exit 1; }
        export DOUBT_PATH="$STATE"
        export DOUBT_QUESTION="$2"
        python3 "$PYTHON_LIB/athena/doubt_query.py" 2>/dev/null
        ;;

    history)
        export JSON_GET_PATH="$LOG_FILE" JSON_GET_KEY="entries"
        python3 "$PYTHON_LIB/athena/jsonl_read.py" 2>/dev/null
        ;;

    decay)
        # Drift confidence toward neutral (0.5). Small step per cycle.
        cur=$(json_get "confidence")
        [ -z "$cur" ] && cur=0.8
        new=$(drift_toward "$cur" 0.5 0.05)
        [ -n "$new" ] && json_set "confidence" "$new"
        json_set "last_updated" "$(now)"
        ;;

    calibrate)
        export DOUBT_PATH="$STATE"
        export DOUBT_TS="$(now)"
        export DOUBT_VOLITION_PATH="$DATA_DIR/volition.json"
        python3 "$PYTHON_LIB/athena/doubt_consolidate.py" 2>/dev/null
        echo "Calibration complete."
        ;;

    *)
        echo "usage: $0 {read|add|check|query|history|calibrate|decay}" >&2
        exit 1
        ;;
esac
