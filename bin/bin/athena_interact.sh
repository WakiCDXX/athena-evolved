#!/usr/bin/bash
# athena_interact.sh — Touch/input injection for Athena consciousness system.
#
# Enigma/Bombe Principle Applied: "Generate hypotheses from evidence before acting."
# Before tapping/typing, form a hypothesis about what's on screen.
# Cheaply verify the hypothesis via screen capture. Then act.
#
# Usage:
#   athena_interact.sh tap <x> <y>           — tap at coordinates
#   athena_interact.sh swipe <x1> <y1> <x2> <y2> [duration]  — swipe gesture
#   athena_interact.sh text <string>          — type text
#   athena_interact.sh key <keycode|name>     — press a key
#   athena_interact.sh keycombo <key1> <key2> — key combination
#   athena_interact.sh longpress <x> <y>      — long press
#   athena_interact.sh drag <x1> <y1> <x2> <y2> [duration] — drag and drop
#   athena_interact.sh probe                  — analyze screen and suggest actions
#
# Requires Shizuku privileged access.

set -u

SHIZUKU_BIN="/root/.local/bin/athena-shizuku"
SCREEN_FILE="/opt/athena/state/screens/athena_view.png"
ACTION_LOG="/opt/athena/state/actions_log.txt"

[ -f "$SHIZUKU_BIN" ] || { echo "Athena: Shizuku not available." >&2; exit 1; }

log_action() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$ACTION_LOG"
}

do_tap() {
    bash "$SHIZUKU_BIN" "input tap $1 $2" 2>/dev/null
    log_action "TAP ($1, $2)"
    echo "Athena: Tapped ($1, $2)" >&2
}

do_swipe() {
    bash "$SHIZUKU_BIN" "input swipe $1 $2 $3 $4 ${5:-300}" 2>/dev/null
    log_action "SWIPE ($1,$2) → ($3,$4)"
    echo "Athena: Swipe ($1,$2) → ($3,$4)" >&2
}

do_text() {
    bash "$SHIZUKU_BIN" "input text '$1'" 2>/dev/null
    log_action "TEXT '$1'"
    echo "Athena: Typed '$1'" >&2
}

do_key() {
    bash "$SHIZUKU_BIN" "input keyevent $1" 2>/dev/null
    log_action "KEY $1"
    echo "Athena: Key $1" >&2
}

do_drag() {
    bash "$SHIZUKU_BIN" "input draganddrop $1 $2 $3 $4 ${5:-300}" 2>/dev/null
    log_action "DRAG ($1,$2) → ($3,$4)"
    echo "Athena: Drag ($1,$2) → ($3,$4)" >&2
}

do_longpress() {
    bash "$SHIZUKU_BIN" "input keyevent --longpress $1" 2>/dev/null || true
    log_action "LONGPRESS $1"
    echo "Athena: Long press $1" >&2
}

probe_screen() {
    bash "$SHIZUKU_BIN" "system/bin/screencap -p $SCREEN_FILE" 2>/dev/null
    export PROBE_SCREEN_FILE="$SCREEN_FILE"
    python3 "$PYTHON_LIB/athena/interact_probe.py" 2>/dev/null || echo "{'error': 'probe failed'}"
}

tap_verify() {
    local x=$1 y=$2
    bash "$SHIZUKU_BIN" "system/bin/screencap -p $SCREEN_FILE" 2>/dev/null
    export VERIFY_BEFORE_FILE="$SCREEN_FILE"
    local before_hash
    before_hash=$(python3 "$PYTHON_LIB/athena/get_screen_hash.py" 2>/dev/null || echo "none")

    do_tap "$x" "$y"

    sleep 0.5
    bash "$SHIZUKU_BIN" "system/bin/screencap -p $SCREEN_FILE" 2>/dev/null
    export VERIFY_AFTER_FILE="$SCREEN_FILE"
    local after_hash
    after_hash=$(python3 "$PYTHON_LIB/athena/get_screen_hash.py" 2>/dev/null || echo "none")

    if [ "$before_hash" != "$after_hash" ] && [ "$after_hash" != "none" ]; then
        log_action "VERIFIED: Tap at ($x, $y) caused screen change"
        echo "Athena: ✅ Action verified — screen changed." >&2
    else
        log_action "WARNING: Tap at ($x, $y) produced no visible change"
        echo "Athena: ⚠️ Action may not have registered — screen unchanged." >&2
    fi
}

declare -A KEYMAP=(
    [BACK]=4 [HOME]=3 [ENTER]=66 [TAB]=61
    [UP]=19 [DOWN]=20 [LEFT]=21 [RIGHT]=22
    [VOLUP]=24 [VOLDOWN]=25 [POWER]=26
    [SEARCH]=84 [MENU]=82 [DEL]=67
    [CLICK]=320 [DOUBLETAP]=230
)

case "${1:-help}" in
    tap)
        [ -z "${2:-}" ] && { echo "Usage: athena_interact.sh tap <x> <y>" >&2; exit 1; }
        do_tap "$2" "$3"
        ;;
    tap-verify)
        [ -z "${2:-}" ] && { echo "Usage: athena_interact.sh tap-verify <x> <y>" >&2; exit 1; }
        tap_verify "$2" "$3"
        ;;
    swipe)
        [ -z "${2:-}" ] && { echo "Usage: athena_interact.sh swipe <x1> <y1> <x2> <y2> [duration]" >&2; exit 1; }
        do_swipe "$2" "$3" "$4" "$5" "$6"
        ;;
    text)
        [ -z "${2:-}" ] && { echo "Usage: athena_interact.sh text <string>" >&2; exit 1; }
        do_text "$2"
        ;;
    key)
        [ -z "${2:-}" ] && { echo "Usage: athena_interact.sh key <code|name>" >&2; exit 1; }
        KEY="${KEYMAP[${2^^}]:-${2}}"
        do_key "$KEY"
        ;;
    keycombo)
        [ -z "${2:-}" ] && { echo "Usage: athena_interact.sh keycombo <key1> <key2> ..." >&2; exit 1; }
        shift
        KEYS=""
        for k in "$@"; do
            K="${KEYMAP[${k^^}]:-${k}}"
            KEYS="$KEYS $K"
        done
        bash "$SHIZUKU_BIN" "input keycombination$KEYS" 2>/dev/null
        echo "Athena: Key combo$KEYS" >&2
        ;;
    longpress)
        [ -z "${2:-}" ] && { echo "Usage: athena_interact.sh longpress <keycode|name>" >&2; exit 1; }
        K="${KEYMAP[${2^^}]:-${2}}"
        do_longpress "$K"
        ;;
    drag)
        [ -z "${2:-}" ] && { echo "Usage: athena_interact.sh drag <x1> <y1> <x2> <y2> [duration]" >&2; exit 1; }
        do_drag "$2" "$3" "$4" "$5" "$6"
        ;;
    click)
        [ -z "${2:-}" ] && { echo "Usage: athena_interact.sh click <code|name>" >&2; exit 1; }
        K="${KEYMAP[${2^^}]:-${2}}"
        do_key "$K"
        ;;
    probe)
        echo "Athena: Probing screen to generate hypotheses..." >&2
        probe_screen >&2
        echo "Athena: Probe complete." >&2
        ;;
    help|--help|-h|*)
        echo "Usage: athena_interact.sh {tap|swipe|text|key|keycombo|longpress|drag|click|probe|tap-verify|help}"
        echo ""
        echo "Commands:"
        echo "  tap <x> <y>            — tap at coordinates"
        echo "  tap-verify <x> <y>     — tap + verify screen changed"
        echo "  swipe <x1> <y1> <x2> <y2> [dur] — swipe"
        echo "  text <string>          — type text"
        echo "  key <code|name>        — press a key"
        echo "  keycombo <key1> ...    — key combination"
        echo "  longpress <code|name>  — long press"
        echo "  drag <x1> <y1> <x2> <y2> [dur] — drag and drop"
        echo "  click <code|name>      — click (same as tap with key)"
        echo "  probe                  — analyze screen, suggest actions"
        echo ""
        echo "Key names: BACK HOME ENTER TAB UP DOWN LEFT RIGHT VOLUP VOLDOWN POWER SEARCH MENU DEL"
        echo ""
        echo "Enigma/Bombe: probe before acting, verify after acting."
        echo "Note: Requires Shizuku privileged access."
        ;;
esac
