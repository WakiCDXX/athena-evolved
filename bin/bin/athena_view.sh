#!/usr/bin/bash
# athena_view.sh — Screen capture for Athena consciousness system.
#
# Enigma/Bombe Principle Applied: Model unknowns, collect observations
# from independent channels, reject impossible candidates cheaply, test survivors.
#
# Accessibility-first design: Uses accessibility snapshots as primary source,
# with raw pixel/OCR as fallback for games, canvas, custom interfaces,
# and secure windows.
#
# Usage:
#   athena_view.sh                      — capture current screen, output path
#   athena_view.sh view                 — capture and display
#   athena_view.sh save <label>         — capture and save to athena_data/screens/
#   athena_view.sh diff <label>         — capture and compare with previous
#   athena_view.sh analyze <label>      — structural analysis + confidence scoring
#   athena_view.sh probe                — hypothesis test: what's on screen?
#   athena_view.sh state                — output full structured screen state as JSON
#   athena_view.sh click <node_id>      — propose structured ACTION_CLICK
#   athena_view.sh scroll <node_id> <dir> <dist>  — propose ACTION_SCROLL
#   athena_view.sh type <text>          — propose ACTION_TYPE
#   athena_view.sh back                 — propose ACTION_BACK
#   athena_view.sh launch <package>     — propose ACTION_LAUNCH_APP
#
# Requires Shizuku privileged access to run /system/bin/screencap.

set -u

DATA_DIR="/opt/athena/state"
SCREEN_DIR="$DATA_DIR/screens"
HISTORY_FILE="/root/.openclaude/history.jsonl"
SHIZUKU_BIN="/root/.local/bin/athena-shizuku"
OUTPUT="$SCREEN_DIR/athena_view.png"
STRUCTURED_STATE_FILE="$DATA_DIR/screen_state.json"
ACTION_LOG="$DATA_DIR/action_log.jsonl"
DEGRADATION_FILE="$DATA_DIR/degradation_state.json"

mkdir -p "$SCREEN_DIR"
mkdir -p "$DATA_DIR"

# --- accessibility-first structured state -----------------------------------

get_accessibility_snapshot() {
    # Attempt to get structured accessibility data via Shizuku
    # Returns JSON with window info, focused node, dialogs, navigation
    local result=$(bash "$SHIZUKU_BIN" "android.accessibility.GetWindows" 2>/dev/null)
    if [ -n "$result" ] && echo "$result" | python3 "$PYTHON_LIB/athena/view_validate_json.py" 2>/dev/null; then
        echo "$result"
        return 0
    fi
    return 1
}

get_accessibility_tree() {
    # Get accessibility tree for the current window
    local result=$(bash "$SHIZUKU_BIN" "android.accessibility.GetNodeTree" 2>/dev/null)
    if [ -n "$result" ]; then
        echo "$result"
        return 0
    fi
    return 1
}

is_accessibility_available() {
    # Check if accessibility services are enabled and functional
    bash "$SHIZUKU_BIN" "android.accessibility.IsEnabled" 2>/dev/null | grep -q "true" 2>/dev/null
    return $?
}

is_shizuku_authorized() {
    [ -f "/root/storage/rish/rish_shizuku.dex" ] 2>/dev/null
}

# --- screen capture (fallback) ----------------------------------------------

capture() {
    bash "$SHIZUKU_BIN" "system/bin/screencap -p $OUTPUT" 2>/dev/null
    if [ -f "$OUTPUT" ] && [ $(stat -c%s "$OUTPUT" 2>/dev/null) -gt 1000 ]; then
        echo "$OUTPUT"
    else
        echo ""
    fi
}

analyze_pixel_stats() {
    # Pixel-based fallback analysis when accessibility is unavailable
    # Pure Python implementation — no numpy dependency
    # Vintage console principle: if you can't afford the math coprocessor,
    # use simpler algorithms and iterate manually
    local img="${1:-$OUTPUT}"
    [ -f "$img" ] || return 1
    VIEW_IMG="$img" python3 "$PYTHON_LIB/athena/view_pixel_stats.py" 2>/dev/null
}

# --- structured screen state -----------------------------------------------

build_structured_state() {
    local accessibility_available=false
    local pixel_available=false
    local screen_type="unknown"
    local confidence=0.0
    local active_window="{}"
    local focused_node="{}"
    local dialogs="[]"
    local navigation_present=false
    local content_type="unknown"
    local timestamp=$(date +%s)

    # Primary: try accessibility snapshot
    if is_shizuku_authorized && is_accessibility_available; then
        accessibility_available=true
        local acc_snapshot=$(get_accessibility_snapshot 2>/dev/null)
        if [ -n "$acc_snapshot" ]; then
            # Parse accessibility snapshot into structured state
            VIEW_ACC_SNAPSHOT="$acc_snapshot" VIEW_TIMESTAMP="$timestamp" python3 "$PYTHON_LIB/athena/view_build_state.py" 2>/dev/null
            return
        fi
    fi

    # Fallback: pixel analysis
    pixel_available=true
    local pixel_result=$(analyze_pixel_stats "$OUTPUT" 2>/dev/null)
    screen_type=$(echo "$pixel_result" | python3 "$PYTHON_LIB/athena/view_extract_screen_type.py" 2>/dev/null || echo "unknown")
    confidence=$(echo "$pixel_result" | python3 "$PYTHON_LIB/athena/view_extract_confidence.py" 2>/dev/null || echo "0.3")

    # Build state with pixel-only data
    VIEW_SCREEN_TYPE="$screen_type" VIEW_CONFIDENCE="$confidence" VIEW_TIMESTAMP="$timestamp" python3 "$PYTHON_LIB/athena/view_build_pixel_state.py" 2>/dev/null
}

get_screen_state() {
    # Get the most recent structured screen state
    if [ -f "$STRUCTURED_STATE_FILE" ]; then
        local age=$(( $(date +%s) - $(VIEW_STRUCTURED_STATE_FILE="$STRUCTURED_STATE_FILE" python3 "$PYTHON_LIB/athena/view_get_timestamp.py" 2>/dev/null || echo 0) ))
        if [ $age -lt 30 ]; then
            cat "$STRUCTURED_STATE_FILE"
            return
        fi
    fi
    build_structured_state > "$STRUCTURED_STATE_FILE" 2>/dev/null
    cat "$STRUCTURED_STATE_FILE" 2>/dev/null
}

# --- typed action broker ----------------------------------------------------
# Each action validates operation, target freshness, parameter range, permission state

validate_action() {
    local action="$1"
    VALIDATION=$(STRUCTURED_STATE_FILE="$STRUCTURED_STATE_FILE" DEGRADATION_FILE="$DEGRADATION_FILE" ACTION="$action" python3 "$PYTHON_LIB/athena/view_validate_action.py" 2>/dev/null || echo '{"valid": false, "reason": "validation_error"}')
}

propose_action() {
    local action="$1"
    local target="${2:-}"
    local detail="${3:-}"
    local validation=$(validate_action "$action")
    local is_valid=$(echo "$validation" | python3 "$PYTHON_LIB/athena/view_extract_valid.py" 2>/dev/null || echo "False")
    if [ "$is_valid" = "True" ]; then
        # Log the action proposal
        VIEW_EVENT="$action" VIEW_TARGET="$target" VIEW_DETAIL="$detail" VIEW_VALIDATION="$validation" VIEW_TIMESTAMP="$(date +%s)" ACTION_LOG="$ACTION_LOG" python3 "$PYTHON_LIB/athena/view_log_action.py" 2>/dev/null
    else
        echo "$validation"
    fi
}

# --- core commands ----------------------------------------------------------

handle_view() {
    # Capture current screen, output path
    local img=$(capture)
    if [ -n "$img" ]; then
        echo "$img"
        # Also update structured state
        build_structured_state > "$STRUCTURED_STATE_FILE" 2>/dev/null
    else
        echo "Athena: Failed to capture screen." >&2
        exit 1
    fi
}

handle_save() {
    local label="$1"
    local img=$(capture)
    if [ -n "$img" ]; then
        cp "$img" "$SCREEN_DIR/${label}.png"
        echo "$SCREEN_DIR/${label}.png"
        build_structured_state > "$STRUCTURED_STATE_FILE" 2>/dev/null
    else
        echo "Athena: Failed to capture screen." >&2
        exit 1
    fi
}

handle_diff() {
    local label="$1"
    local img=$(capture)
    if [ -z "$img" ]; then
        echo "Athena: Failed to capture screen." >&2
        exit 1
    fi
    local current_hash=$(VIEW_IMG="$img" python3 "$PYTHON_LIB/athena/view_compute_hash.py" 2>/dev/null || echo "none")
    # Check against last saved
    local last_hash=$(cat "$SCREEN_DIR/.last_hash" 2>/dev/null || echo "")
    if [ "$current_hash" = "$last_hash" ]; then
        echo "UNCHANGED (hash: $current_hash)"
        echo "screen_state: stable"
        record_screen_event "screen_unchanged" "$current_hash"
    else
        echo "CHANGED (new hash: $current_hash)"
        echo "screen_state: changed"
        record_screen_event "screen_changed" "$current_hash"
        cp "$img" "$SCREEN_DIR/.last.png"
        echo "$current_hash" > "$SCREEN_DIR/.last_hash"
    fi
    # Output structured state too
    build_structured_state > "$STRUCTURED_STATE_FILE" 2>/dev/null
    echo "--- Structured State ---"
    cat "$STRUCTURED_STATE_FILE" 2>/dev/null
}

handle_analyze() {
    local label="$1"
    local img="$SCREEN_DIR/${label}.png"
    [ -f "$img" ] || img=$(capture)
    if [ -z "$img" ]; then
        echo "Athena: No screen to analyze." >&2
        exit 1
    fi
    echo "--- Pixel Analysis ---"
    analyze_pixel_stats "$img"
    echo ""
    echo "--- Structured State ---"
    build_structured_state
    echo ""
    echo "--- Confidence Scoring ---"
    VIEW_STRUCTURED_STATE_FILE="$STRUCTURED_STATE_FILE" python3 "$PYTHON_LIB/athena/view_confidence_scoring.py" 2>/dev/null
}

handle_probe() {
    # Hypothesis test: what's on screen?
    local img=$(capture)
    if [ -z "$img" ]; then
        echo "Athena: Failed to capture screen." >&2
        exit 1
    fi
    build_structured_state > "$STRUCTURED_STATE_FILE" 2>/dev/null
    echo "--- Screen Probe ---"
    VIEW_STRUCTURED_STATE_FILE="$STRUCTURED_STATE_FILE" python3 "$PYTHON_LIB/athena/view_probe_screen.py" 2>/dev/null
}

handle_state() {
    # Output full structured screen state as JSON
    build_structured_state
}

# --- screen event logging -------------------------------------------------

record_screen_event() {
    local event="$1"
    local hash="$2"
    local log_file="$DATA_DIR/screen_events.jsonl"
    VIEW_EVENT="$event" VIEW_HASH="$hash" VIEW_LOG_FILE="$log_file" python3 "$PYTHON_LIB/athena/view_record_event.py" 2>/dev/null
}

# --- action commands --------------------------------------------------------

handle_click() {
    local node_id="${1:-}"
    if [ -z "$node_id" ]; then
        echo "Usage: athena_view.sh click <node_id>" >&2
        exit 1
    fi
    echo "Proposing ACTION_CLICK for node: $node_id"
    propose_action "ACTION_CLICK" "$node_id" ""
}

handle_scroll() {
    local node_id="${1:-}"
    local direction="${2:-down}"
    local distance="${3:-100}"
    if [ -z "$node_id" ]; then
        echo "Usage: athena_view.sh scroll <node_id> <direction> <distance>" >&2
        exit 1
    fi
    echo "Proposing ACTION_SCROLL for node: $node_id, direction: $direction, distance: $distance"
    propose_action "ACTION_SCROLL" "$node_id" "$direction $distance"
}

handle_type() {
    local text="${1:-}"
    if [ -z "$text" ]; then
        echo "Usage: athena_view.sh type <text>" >&2
        exit 1
    fi
    # Get focused node
    local focused_node=$(VIEW_STRUCTURED_STATE_FILE="$STRUCTURED_STATE_FILE" python3 "$PYTHON_LIB/athena/view_get_focused_text.py" 2>/dev/null || echo "")
    echo "Proposing ACTION_TYPE: '$text' into focused node: $focused_node"
    propose_action "ACTION_TYPE" "$focused_node" "$text"
}

handle_back() {
    echo "Proposing ACTION_BACK"
    propose_action "ACTION_BACK" "" ""
}

handle_launch() {
    local package="${1:-}"
    if [ -z "$package" ]; then
        echo "Usage: athena_view.sh launch <package>" >&2
        exit 1
    fi
    echo "Proposing ACTION_LAUNCH_APP for: $package"
    propose_action "ACTION_LAUNCH_APP" "$package" ""
}

# --- main -------------------------------------------------------------------

case "${1:-help}" in
    view)
        handle_view
        ;;
    save)
        [ -z "${2:-}" ] && { echo "Usage: athena_view.sh save <label>" >&2; exit 1; }
        handle_save "$2"
        ;;
    diff)
        [ -z "${2:-}" ] && { echo "Usage: athena_view.sh diff <label>" >&2; exit 1; }
        handle_diff "$2"
        ;;
    analyze)
        [ -z "${2:-}" ] && { echo "Usage: athena_view.sh analyze <label>" >&2; exit 1; }
        handle_analyze "$2"
        ;;
    probe)
        handle_probe
        ;;
    state)
        handle_state
        ;;
    click)
        handle_click "$2"
        ;;
    scroll)
        handle_scroll "$2" "$3" "$4"
        ;;
    type)
        handle_type "$2"
        ;;
    back)
        handle_back
        ;;
    launch)
        handle_launch "$2"
        ;;
    "")
        handle_view
        ;;
    help|--help|-h|*)
        echo "Usage: athena_view.sh {view|save|diff|analyze|probe|state|click|scroll|type|back|launch}"
        echo ""
        echo "Commands:"
        echo "  view                   Capture current screen, output path"
        echo "  save <label>           Capture and save to athena_data/screens/"
        echo "  diff <label>           Capture and compare with previous"
        echo "  analyze <label>        Structural analysis + confidence scoring"
        echo "  probe                  Hypothesis test: what's on screen?"
        echo "  state                  Output full structured screen state as JSON"
        echo "  click <node_id>        Propose ACTION_CLICK"
        echo "  scroll <node_id> <dir> <dist>  Propose ACTION_SCROLL"
        echo "  type <text>            Propose ACTION_TYPE"
        echo "  back                   Propose ACTION_BACK"
        echo "  launch <package>       Propose ACTION_LAUNCH_APP"
        echo ""
        echo "Accessibility-first: primary source is accessibility tree,"
        echo "  with raw pixel/OCR as fallback for games, canvas, secure windows"
        echo ""
        echo "Requires Shizuku privileged access."
        ;;
esac
