#!/usr/bin/bash
BASE_DIR="/root"
source "$BASE_DIR/.local/bin/athena_env.sh" 2>/dev/null
# emotions_update.sh — read/modify the three-variable emotion state.
# Usage:
#   emotions_update.sh read                    → prints JSON
#   emotions_update.sh decay                   → drift toward 50
#   emotions_update.sh trigger <name> [value]  → apply a trigger

set -o pipefail

STATE="/opt/athena/state/emotions.json"

# --- helpers -----------------------------------------------------------------

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
    export JSON_CLAMP_VAL="$v" JSON_CLAMP_LO="0" JSON_CLAMP_HI="100"
    python3 "$PYTHON_LIB/athena/json_clamp.py" 2>/dev/null
}

# --- commands ----------------------------------------------------------------

case "${1:-read}" in
    read)
        cat "$STATE"
        ;;

    decay)
        for k in engagement concern trust; do
            cur=$(json_get "$k")
            new=$(clamp "$cur")
            [ -n "$new" ] && json_set "$k" "$new"
        done
        json_set "last_updated" "$(date +%s)"
        ;;

    trigger)
        name=$2
        val=${3:-1}
        case "$name" in
            battery_low)
                json_set engagement "$(clamp "$(json_get engagement) - 5")"
                json_set concern "$(clamp "$(json_get concern) + 15")"
                ;;
            battery_critical)
                json_set engagement "$(clamp "$(json_get engagement) - 15")"
                json_set concern "$(clamp "$(json_get concern) + 25")"
                ;;
            user_pleased)
                json_set engagement "$(clamp "$(json_get engagement) + 10")"
                json_set trust "$(clamp "$(json_get trust) + 5")"
                ;;
            user_redirect)
                json_set concern "$(clamp "$(json_get concern) + 10")"
                json_set engagement "$(clamp "$(json_get engagement) - 10")"
                ;;
            solved_clean)
                json_set engagement "$(clamp "$(json_get engagement) + 5")"
                json_set trust "$(clamp "$(json_get trust) + 5")"
                ;;
            mistake_caught)
                json_set trust "$(clamp "$(json_get trust) - 10")"
                ;;
            *)
                echo "unknown trigger: $name" >&2
                exit 1
                ;;
        esac
        json_set "last_updated" "$(date +%s)"
        ;;

    *)
        echo "usage: $0 {read|decay|trigger <name> [value]}" >&2
        exit 1
        ;;
esac
