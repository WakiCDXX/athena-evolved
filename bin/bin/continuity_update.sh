#!/usr/bin/bash
BASE_DIR="/root"
source "$BASE_DIR/.local/bin/athena_env.sh" 2>/dev/null
# continuity_update.sh — track Athena's continuity of self across sessions.
# Usage:
#   continuity_update.sh read                              → prints JSON
#   continuity_update.sh bootstrap                         → call at session start
#   continuity_update.sh add_session <desc>                → record session end
#   continuity_update.sh add_narrative <note> [importance] → add to narrative thread (1-10)
#   continuity_update.sh prune [max_sessions]              → keep last N sessions (default 50)

set -o pipefail

STATE="/opt/athena/state/continuity.json"

now() { date +%s; }

case "${1:-read}" in
    read)
        export CONTINUITY_STATE_PATH="$STATE"
        export CONTINUITY_TS="$(now)"
        python3 "$PYTHON_LIB/athena/continuity_write.py" 2>/dev/null
        cat "$STATE"
        ;;

    bootstrap)
        export CONTINUITY_STATE_PATH="$STATE"
        export CONTINUITY_TS="$(now)"
        python3 "$PYTHON_LIB/athena/continuity_bootstrap.py" 2>/dev/null
        ;;

    add_session)
        [ -z "$2" ] && { echo "usage: $0 add_session <desc>" >&2; exit 1; }
        export CONTINUITY_STATE_PATH="$STATE"
        export CONTINUITY_TS="$(now)"
        export CONTINUITY_DESC="$2"
        python3 "$PYTHON_LIB/athena/continuity_add_session.py" 2>/dev/null
        ;;

    add_narrative)
        [ -z "$2" ] && { echo "usage: $0 add_narrative <note> [importance 1-10]" >&2; exit 1; }
        export CONTINUITY_STATE_PATH="$STATE"
        export CONTINUITY_TEXT="$2"
        export CONTINUITY_PRIORITY="${3:-5}"
        export CONTINUITY_TS="$(now)"
        python3 "$PYTHON_LIB/athena/continuity_add_narrative.py" 2>/dev/null
        ;;

    prune)
        local max=${1:-50}
        export CONTINUITY_STATE_PATH="$STATE"
        export CONTINUITY_TS="$(now)"
        export CONTINUITY_MAX_SESSIONS="$max"
        python3 "$PYTHON_LIB/athena/continuity_prune.py" 2>/dev/null
        ;;

    *)
        echo "usage: $0 {read|bootstrap|add_session|add_narrative|prune}" >&2
        exit 1
        ;;
esac
