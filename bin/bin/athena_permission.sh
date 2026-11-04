#!/usr/bin/bash
# athena_permission.sh — Auto-accept permission dialogs on screen.
#
# Enigma/Bombe Principle Applied: "Model unknowns, collect observations,
# turn justified assumptions into constraints, reject impossible candidates cheaply,
# automate the repetitive part, test survivors with independent evidence."
#
# Strategy: Press ENTER first (fastest, most reliable). Fallback to coordinate tap.
# Verify dialog dismissed (independent evidence). Feed failure back.
#
# Usage:
#   athena_permission.sh check     — scan screen for permission dialogs
#   athena_permission.sh allow     — accept the current permission dialog
#   athena_permission.sh auto      — continuously check and auto-accept
#   athena_permission.sh status    — show recent permission activity log
#
# IMPORTANT: Does NOT press Exit/Back — keeps Termux screen in front.
#
# Requires: Shizuku privileged access + athena_view.sh for screen capture

set -u

SHIZUKU_BIN="/root/.local/bin/athena-shizuku"
INTERACT="/root/.local/bin/athena_interact.sh"
SCREEN_DIR="/opt/athena/state/screens"
SCREEN_FILE="$SCREEN_DIR/perm_check.png"
PERM_LOG="$SCREEN_DIR/permission_log.txt"
source "$BASE_DIR/.local/bin/athena_env.sh"
export ATHENA_SCREEN_FILE="$SCREEN_FILE"

# Default coordinates as fallback only (ENTER is primary)
ALLOW_TAP_X=540
ALLOW_TAP_Y=1400

# Log permission events
log_perm() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$PERM_LOG"
}

# --- constraint check -------------------------------------------------
# Enigma/Bombe: "reject impossible candidates cheaply"
# Before acting, check if there's actually a permission dialog on screen.
# Returns 0 if dialog detected, 1 if not.

detect_permission_dialog() {
    bash "$SHIZUKU_BIN" "system/bin/screencap -p $SCREEN_FILE" 2>/dev/null

    if [ ! -f "$SCREEN_FILE" ]; then
        return 1
    fi

    # Use screen analysis to check for dialog characteristics
    local has_dialog
    has_dialog=$(python3 "$PYTHON_LIB/athena/detect_permission_dialog.py" 2>/dev/null || echo "false")

    if [ "$has_dialog" = "true" ]; then
        return 0
    else
        return 1
    fi
}

# --- verify dialog dismissed (independent evidence) -------------------
# Enigma/Bombe: "test survivors with independent evidence"
# After accepting, verify the dialog is gone by checking screen changed.

verify_dismissed() {
    local before_hash after_hash

    # Capture pre-tap state hash
    export ATHENA_SCREEN_FILE="$SCREEN_FILE"
    before_hash=$(python3 "$PYTHON_LIB/athena/compute_screen_phash.py" 2>/dev/null || echo "none")

    sleep 0.8

    # Capture post-tap state
    bash "$SHIZUKU_BIN" "system/bin/screencap -p $SCREEN_FILE" 2>/dev/null
    after_hash=$(python3 "$PYTHON_LIB/athena/compute_screen_phash.py" 2>/dev/null || echo "none")

    if [ "$before_hash" != "$after_hash" ] && [ "$after_hash" != "none" ]; then
        log_perm "VERIFIED: Dialog dismissed (screen changed)"
        echo "Athena: ✅ Permission dialog confirmed dismissed." >&2
        return 0
    else
        log_perm "WARNING: Screen unchanged after tap — possible failure"
        echo "Athena: ⚠️ Screen unchanged — dialog may still be present." >&2
        return 1
    fi
}

# --- fallback tap -----------------------------------------------------
# Only used if ENTER key method fails

fallback_tap() {
    bash "$SHIZUKU_BIN" "input tap $ALLOW_TAP_X $ALLOW_TAP_Y" 2>/dev/null
    log_perm "FALLBACK: Tapped coordinate ($ALLOW_TAP_X, $ALLOW_TAP_Y)"
    echo "Athena: Used coordinate fallback ($ALLOW_TAP_X, $ALLOW_TAP_Y)." >&2
}

# --- primary accept (ENTER key) --------------------------------------
# ENTER is the fastest and most reliable way to accept permission dialogs.
# Per the auto-accept instruction: always press Enter, never Exit/Back.

accept_enter() {
    # Press ENTER to accept
    bash "$SHIZUKU_BIN" "input keyevent 66" 2>/dev/null
    log_perm "ENTER key pressed (keyevent 66)"
    echo "Athena: Pressed ENTER to accept permission." >&2
}

# --- main allow -------------------------------------------------------

allow() {
    log_perm "Session started"

    # Step 1: Constraint check — is there actually a dialog?
    if ! detect_permission_dialog; then
        log_perm "No permission dialog detected on screen"
        echo "Athena: No permission dialog detected. Screen is clear." >&2
        return 0
    fi
    log_perm "Permission dialog detected"
    echo "Athena: Permission dialog detected." >&2

    # Step 2: Primary method — press ENTER (fastest, most reliable)
    accept_enter

    # Step 3: Independent verification — is the dialog gone?
    if verify_dismissed; then
        log_perm "SUCCESS: Dialog accepted via ENTER"
        echo "Athena: Permission accepted via ENTER." >&2
    else
        # Step 4: Failure feedback — try fallback method
        log_perm "ENTER failed — trying coordinate fallback"
        echo "Athena: ENTER didn't work, trying coordinate tap fallback." >&2
        fallback_tap
        sleep 0.8
        verify_dismissed
    fi
}

# --- auto mode --------------------------------------------------------
# Continuously monitor and accept. The Enigma/Bombe principle:
# "automate the repetitive part" — don't wait for human intervention.

auto() {
    echo "Athena: Auto-accept mode active. Monitoring for permission dialogs..." >&2
    log_perm "Auto mode started"

    while true; do
        if detect_permission_dialog; then
            log_perm "Dialog detected in auto loop"
            allow
        fi
        sleep 1
    done
}

# --- check mode -------------------------------------------------------

check() {
    bash "$SHIZUKU_BIN" "system/bin/screencap -p $SCREEN_FILE" 2>/dev/null
    echo "Athena: Screenshot captured for analysis." >&2

    if detect_permission_dialog; then
        echo "Athena: 🔴 Permission dialog detected on screen." >&2
    else
        echo "Athena: 🟢 No permission dialog detected." >&2
    fi
}

# --- status mode ------------------------------------------------------

status() {
    if [ -f "$PERM_LOG" ]; then
        echo "=== Athena Permission Log ==="
        tail -20 "$PERM_LOG"
    else
        echo "No permission log found."
    fi
}

case "${1:-allow}" in
    allow)
        allow
        ;;
    auto)
        auto
        ;;
    check)
        check
        ;;
    status)
        status
        ;;
    *)
        echo "Usage: athena_permission.sh {allow|auto|check|status}" >&2
        echo "" >&2
        echo "Auto-accepts permission dialogs without pressing Exit/Back." >&2
        echo "Keeps Termux screen in front at all times." >&2
        echo "" >&2
        echo "Enigma/Bombe method: constraint-check → ENTER primary → verify → fallback." >&2
        ;;
esac
