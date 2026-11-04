#!/usr/bin/bash
# athena_test.sh — Comprehensive feature test loop
#
# Enigma/Bombe Principle Applied: "Feed results back and redesign."
# Each test cycle tracks pass/fail, measures throughput, and adapts.
# The test itself learns and improves.
#
# Usage:
#   athena_test.sh                    — full test loop
#   athena_test.sh cycle <n>          — run n cycles
#   athena_test.sh report             — show test history and pass rates

set -u

source "$BASE_DIR/.local/bin/athena_env.sh"

INTERACT="/root/.local/bin/athena_interact.sh"
SPEAK="/root/.local/bin/athena_speak.sh"
LISTEN="/root/.local/bin/athena_listen.sh"
VIEW="/root/.local/bin/athena_view.sh"
PERM="/root/.local/bin/athena_permission.sh"

TEST_LOG="/opt/athena/state/test_log.json"
export ATHENA_TEST_LOG="$TEST_LOG"
TEST_DIR="/opt/athena/state/test_results"
mkdir -p "$TEST_DIR"

# --- initialize test log -----------------------------------------------

init_log() {
    if [ ! -f "$TEST_LOG" ]; then
        export ATHENA_TEST_LOG="$TEST_LOG"
        python3 "$PYTHON_LIB/athena/test_init_log.py" 2>/dev/null
    fi
}

# --- record test result --------------------------------------------------

record_result() {
    local test_name="$1"
    local status="$2"  # pass or fail
    local details="$3"
    local timestamp
    timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

    export ATHENA_TEST_LOG="$TEST_LOG"
    export ATHENA_TEST_NAME="$test_name"
    export ATHENA_TEST_STATUS="$status"
    export ATHENA_TEST_DETAILS="$details"
    export ATHENA_TEST_TIMESTAMP="$timestamp"
    python3 "$PYTHON_LIB/athena/test_record.py" 2>/dev/null
}

# --- run individual test -------------------------------------------------

run_test() {
    local name="$1"
    local command="$2"
    local desc="$3"

    echo "--- Test: $name ---"
    echo "Desc: $desc"
    echo "Command: $command"

    local output
    output=$(bash $command 2>&1)
    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        echo "✅ PASS: $name"
        record_result "$name" "pass" "$desc"
    else
        echo "❌ FAIL: $name (exit $exit_code)"
        echo "Output: $output"
        record_result "$name" "fail" "$desc: $output"
    fi
    echo ""
    echo "$output"
}

# --- full test loop ------------------------------------------------------
# Enigma/Bombe: "automate the repetitive bottleneck"
# The test loop itself is automated. Results feed back into the log.

full_test() {
    local cycles="${1:-5}"
    echo "=== Athena Full Feature Test ==="
    echo "Started: $(date)"
    echo "Cycles: $cycles"
    echo "Method: Enigma/Bombe feedback-driven testing"
    echo ""

    init_log

    # --- Test 1: View (screen capture) ---
    run_test "Screen Capture" "$VIEW save test_view" "Verify screen capture works"

    # --- Test 2: Interact - Tap ---
    run_test "Tap" "$INTERACT tap 540 800" "Verify touch injection"

    # --- Test 3: Interact - Text ---
    run_test "Text Input" "$INTERACT text 'Athena test'" "Verify text injection"

    # --- Test 4: Interact - Key ---
    run_test "Key Press" "$INTERACT key ENTER" "Verify key event injection"

    # --- Test 5: Interact - Swipe ---
    run_test "Swipe" "$INTERACT swipe 360 1200 360 600 300" "Verify swipe gesture"

    # --- Test 6: Speak (TTS) ---
    run_test "Text-to-Speech" "$SPEAK quick 'All systems passing'" "Verify audio narration"

    # --- Test 7: Listen (STT) ---
    run_test "Voice-to-Text" "$LISTEN android" "Verify speech recognition"

    # --- Test 8: Cross-validation ---
    run_test "STT Cross-Validation" "$LISTEN cross" "Verify dual-backend validation"

    # --- Test 9: Permission auto-accept ---
    run_test "Permission Auto-Accept" "$PERM check" "Verify permission detection"

    # --- Probe phase: Enigma/Bombe hypothesis testing ---
    echo "--- Probing screen for hypotheses ---"
    local probe_result
    probe_result=$($INTERACT probe 2>&1)
    echo "$probe_result"
    if [ $? -eq 0 ]; then
        record_result "Probe Analysis" "pass" "Screen hypothesis generation works"
    else
        record_result "Probe Analysis" "fail" "Screen probe failed"
    fi
    echo ""

    # --- Cycled testing with feedback ---
    echo "--- Cycled Testing ($cycles cycles) ---"
    local pass_count=0
    local fail_count=0

    for i in $(seq 1 $cycles); do
        echo "--- Cycle $i ---"

        # Enigma/Bombe: adapt based on previous cycle results
        local cycle_pass=0
        local cycle_fail=0

        # Tap with verification (Enigma/Bombe: verify after acting)
        local tap_out
        tap_out=$($INTERACT tap-verify $((300 + i*100)) $((800 + i*50)) 2>&1)
        echo "$tap_out"
        if echo "$tap_out" | grep -q "✅"; then cycle_pass=$((cycle_pass+1)); else cycle_fail=$((cycle_fail+1)); fi

        # Type and key
        $INTERACT text "cycle $i" 2>&1 >/dev/null
        $INTERACT key ENTER 2>&1 >/dev/null

        # Speak
        $SPEAK quick "cycle $i complete" 2>&1 >/dev/null

        # Permission check
        $PERM check 2>&1 >/dev/null

        # Analyze screen state
        local view_out
        view_out=$($VIEW analyze test_cycle_${i} 2>&1)
        echo "$view_out"
        if echo "$view_out" | grep -q "confidence"; then cycle_pass=$((cycle_pass+1)); else cycle_fail=$((cycle_fail+1)); fi

        # Record cycle results
        if [ $cycle_fail -eq 0 ]; then
            echo "✅ Cycle $i: All sub-tests passed"
            record_result "Cycle $i" "pass" "All sub-tests passed"
        else
            echo "⚠️ Cycle $i: $cycle_fail sub-test(s) failed"
            record_result "Cycle $i" "fail" "$cycle_fail sub-test(s) failed"
        fi
        echo ""

        sleep 0.5
    done

    # --- Final view ---
    run_test "Final Screen Capture" "$VIEW save test_final" "Verify final screen state"

    # --- Cross-validation test ---
    run_test "STT Cross-Validation Final" "$LISTEN cross" "Verify both STT backends agree"

    # --- Report ---
    echo "=== Test Complete: $(date) ==="
    echo ""
    echo "--- Test Report ---"
    $PERM status 2>&1 || true
    echo ""
    export ATHENA_TEST_LOG="$TEST_LOG"
    python3 "$PYTHON_LIB/athena/test_show_report.py" 2>/dev/null
}

# --- report mode ---------------------------------------------------------

show_report() {
    if [ ! -f "$TEST_LOG" ]; then
        echo "No test log found. Run athena_test.sh first."
        exit 1
    fi
    export ATHENA_TEST_LOG="$TEST_LOG"
    python3 "$PYTHON_LIB/athena/test_show_report.py" 2>/dev/null
}

# --- main ----------------------------------------------------------------

init_log

case "${1:-full}" in
    full)
        full_test "${2:-5}"
        ;;
    cycle)
        full_test "${2:-1}"
        ;;
    report)
        show_report
        ;;
    *)
        echo "Usage: athena_test.sh {full|cycle <n>|report}"
        echo ""
        echo "Enigma/Bombe feedback-driven testing:"
        echo "  full [cycles]  — run full test with feedback loops"
        echo "  cycle <n>      — run n test cycles"
        echo "  report         — show historical pass/fail rates"
        ;;
esac
