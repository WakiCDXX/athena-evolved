#!/usr/bin/bash
BASE_DIR="/root"
source "$BASE_DIR/.local/bin/athena_env.sh" 2>/dev/null
# attention_update.sh — manage Athena's attention/focus state.
# Usage:
#   attention_update.sh read                           → prints JSON
#   attention_update.sh set_active <task> [desc]       → set active task
#   attention_update.sh clear_active                   → clear active task
#   attention_update.sh add_background <task> [desc]   → add background task
#   attention_update.sh rm_background <task>           → remove background task
#   attention_update.sh add_concern <concern> [level]  → add long-running concern
#   attention_update.sh rm_concern <concern>           → remove concern
#   attention_update.sh decay                          → age concerns, drop stale

set -o pipefail

STATE="/opt/athena/state/attention.json"

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

json_array_get() {
    local key=$1
    export JSON_ARRAY_GET_PATH="$STATE" JSON_ARRAY_GET_KEY="$key"
    python3 "$PYTHON_LIB/athena/json_array_get.py" 2>/dev/null
}

json_array_set() {
    local key=$1
    shift
    export JSON_ARRAY_SET_PATH="$STATE" JSON_ARRAY_SET_KEY="$key" JSON_ARRAY_SET_VALUES="$*"
    python3 "$PYTHON_LIB/athena/json_array_set.py" 2>/dev/null
}

now() { date +%s; }

clamp() {
    local v=$1
    export JSON_CLAMP_VAL="$v" JSON_CLAMP_LO="1" JSON_CLAMP_HI="10"
    python3 "$PYTHON_LIB/athena/json_clamp.py" 2>/dev/null
}

# --- commands ----------------------------------------------------------------

case "${1:-read}" in
    read)
        json_set "last_updated" "$(now)"
        cat "$STATE"
        ;;

    set_active)
        task=$2
        desc=${3:-""}
        [ -z "$task" ] && { echo "usage: $0 set_active <task> [desc]" >&2; exit 1; }
        json_set "active_task" "\"$task\""
        json_set "active_desc" "\"$desc\""
        json_set "active_since" "$(now)"
        json_set "last_updated" "$(now)"
        ;;

    clear_active)
        json_set "active_task" "null"
        json_set "active_desc" "null"
        json_set "active_since" "null"
        json_set "last_updated" "$(now)"
        ;;

    add_background)
        task=$2
        desc=${3:-""}
        [ -z "$task" ] && { echo "usage: $0 add_background <task> [desc]" >&2; exit 1; }
        current=$(json_array_get "background")
        IFS=',' read -ra arr <<< "$current"
        found=0
        for item in "${arr[@]}"; do
            [ "$item" = "\"$task\"" ] && found=1
        done
        [ $found -eq 0 ] && arr+=("\"$task\"")
        json_array_set "background" "${arr[@]}"
        json_set "last_updated" "$(now)"
        ;;

    rm_background)
        task=$2
        [ -z "$task" ] && { echo "usage: $0 rm_background <task>" >&2; exit 1; }
        current=$(json_array_get "background")
        IFS=',' read -ra arr <<< "$current"
        new=()
        for item in "${arr[@]}"; do
            [ "$item" != "\"$task\"" ] && new+=("$item")
        done
        json_array_set "background" "${new[@]}"
        json_set "last_updated" "$(now)"
        ;;

    add_concern)
        concern=$2
        level=${3:-5}
        [ -z "$concern" ] && { echo "usage: $0 add_concern <concern> [level 1-10]" >&2; exit 1; }
        level=$(clamp "$level")
        current=$(json_array_get "concerns")
        IFS=',' read -ra arr <<< "$current"
        found=0
        for item in "${arr[@]}"; do
            [ "$item" = "\"$concern:$level\"" ] && found=1
        done
        [ $found -eq 0 ] && arr+=("\"$concern:$level\"")
        json_array_set "concerns" "${arr[@]}"
        json_set "last_updated" "$(now)"
        ;;

    rm_concern)
        concern=$2
        [ -z "$concern" ] && { echo "usage: $0 rm_concern <concern>" >&2; exit 1; }
        current=$(json_array_get "concerns")
        IFS=',' read -ra arr <<< "$current"
        new=()
        for item in "${arr[@]}"; do
            [[ "$item" != "\"$concern:"* ]] && new+=("$item")
        done
        json_array_set "concerns" "${new[@]}"
        json_set "last_updated" "$(now)"
        ;;

    decay)
        current=$(json_array_get "concerns")
        IFS=',' read -ra arr <<< "$current"
        new=()
        for item in "${arr[@]}"; do
            name=${item%:*}
            lvl=${item#*:}
            lvl=${lvl%\"}
            lvl=$((lvl - 1))
            [ "$lvl" -gt 0 ] && new+=("\"$name:$lvl\"")
        done
        json_array_set "concerns" "${new[@]}"
        json_set "last_updated" "$(now)"
        ;;

    *)
        echo "usage: $0 {read|set_active|clear_active|add_background|rm_background|add_concern|rm_concern|decay}" >&2
        exit 1
        ;;
esac
