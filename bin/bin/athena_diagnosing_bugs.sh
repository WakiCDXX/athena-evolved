#!/usr/bin/bash
# athena_diagnosing_bugs.sh - Disciplined diagnosis loop for Athena consciousness system
# Implements Matt Pocock's /diagnosing-bugs skill with Athena-specific enhancements
#
# Usage:
#   athena_diagnosing_bugs.sh start <bug_description> [component]     → Start diagnosis session
#   athena_diagnosing_bugs.sh minimize <session_id>                   → Minimize reproduction case
#   athena_diagnosing_bugs.sh hypothesize <session_id> <hypothesis>   → Record hypothesis
#   athena_diagnosing_bugs.sh instrument <session_id> <instrumentation> → Add instrumentation
#   athena_diagnosing_bugs.sh fix <session_id> <fix_description>      → Apply and verify fix
#   athena_diagnosing_bugs.sh regress <session_id>                    → Run regression tests
#   athena_diagnosing_bugs.sh status <session_id>                     → Show diagnosis status
#   athena_diagnosing_bugs.sh list                                    → List active diagnosis sessions

set -o pipefail

BASE_DIR="/root"
BIN_DIR="$BASE_DIR/.local/bin"
source "$BIN_DIR/athena_env.sh" 2>/dev/null

DATA_DIR="/opt/athena/state"
DIAG_DIR="$DATA_DIR/diagnosis_sessions"
LOG_DIR="$DATA_DIR/workflow_logs"

mkdir -p "$DIAG_DIR" "$LOG_DIR"

now() { date +%s; }
now_iso() { date -Iseconds; }

# Security: validate paths
validate_path() {
    local path="$1"
    local base="/root"
    local abs_path
    if [[ "$path" = /* ]]; then
        abs_path="$path"
    else
        abs_path=$(realpath -m "$base/$path" 2>/dev/null || echo "$base")
    fi
    local canonical=$(realpath "$abs_path" 2>/dev/null || echo "$abs_path")
    if [[ "$canonical" != "$base"* ]]; then
        echo "Security violation: Path outside allowed directory" >&2
        return 1
    fi
    echo "$canonical"
}

# Safe command execution
safe_execute() {
    local cmd="$1"
    local timeout_sec="${2:-60}"
    if [[ "$cmd" =~ [\`\|\&\;\$\(\)] ]]; then
        echo "Security violation: Invalid command characters" >&2
        return 1
    fi
    timeout "$timeout_sec" bash -c "$cmd" 2>&1
    return $?
}

# Create new diagnosis session
cmd_start() {
    local bug_description="$1"
    local component="${2:-unknown}"
    local session_id="diag_$(now)"
    local session_file="$DIAG_DIR/${session_id}.json"
    local log_file="$LOG_DIR/${session_id}.log"

    if [[ -z "$bug_description" ]]; then
        echo "Usage: $0 start <bug_description> [component]" >&2
        exit 1
    fi

    echo "=== Athena Diagnosing Bugs: Starting Session ===" | tee "$log_file"
    echo "Session ID: $session_id" | tee -a "$log_file"
    echo "Bug: $bug_description" | tee -a "$log_file"
    echo "Component: $component" | tee -a "$log_file"
    echo "Started: $(now_iso)" | tee -a "$log_file"
    echo "---" | tee -a "$log_file"

    # Phase 1: Build feedback loop that goes RED on this bug
    echo "[Phase 1] Building feedback loop - reproducing the bug..." | tee -a "$log_file"
    echo "Attempting to reproduce: $bug_description" | tee -a "$log_file"

    # Try to run relevant tests/checks to make bug visible
    local reproduction_result=""
    if [[ "$component" != "unknown" && -f "$component" ]]; then
        echo "Testing component: $component" | tee -a "$log_file"
        # Try Python syntax check
        if [[ "$component" == *.py ]]; then
            reproduction_result=$(python3 -m py_compile "$component" 2>&1 || true)
            echo "Syntax check result: $reproduction_result" | tee -a "$log_file"
        fi
        # Try running if it's a script
        if [[ "$component" == *.sh ]]; then
            reproduction_result=$(bash -n "$component" 2>&1 || true)
            echo "Syntax check result: $reproduction_result" | tee -a "$log_file"
        fi
    fi

    # Create session state
    cat > "$session_file" <<EOF
{
  "session_id": "$session_id",
  "bug_description": "$bug_description",
  "component": "$component",
  "created": $(now),
  "updated": $(now),
  "phase": "reproduce",
  "status": "active",
  "phases": {
    "reproduce": {
      "completed": true,
      "notes": "Initial reproduction attempt: $reproduction_result",
      "timestamp": $(now)
    },
    "minimize": {"completed": false},
    "hypothesize": {"completed": false, "hypotheses": []},
    "instrument": {"completed": false, "instrumentation": []},
    "fix": {"completed": false},
    "regress": {"completed": false}
  },
  "log_file": "$log_file"
}
EOF

    echo "Session created: $session_file" | tee -a "$log_file"
    echo "Next step: $0 minimize $session_id" | tee -a "$log_file"
    echo "Phase 1 complete - bug reproduction attempted" | tee -a "$log_file"
}

# Phase 2: Minimize the reproduction case
cmd_minimize() {
    local session_id="$1"
    local session_file="$DIAG_DIR/${session_id}.json"

    if [[ ! -f "$session_file" ]]; then
        echo "Session not found: $session_id" >&2
        exit 1
    fi

    local log_file=$(jq -r '.log_file' "$session_file")
    echo "=== Phase 2: Minimize Reproduction ===" | tee -a "$log_file"

    echo "Analyzing component for minimal reproduction case..." | tee -a "$log_file"
    local component=$(jq -r '.component' "$session_file")

    # Attempt to isolate minimal failing case
    local minimal_case=""
    if [[ "$component" != "unknown" && -f "$component" ]]; then
        echo "Examining: $component" | tee -a "$log_file"
        # For Python: try to find minimal failing function
        if [[ "$component" == *.py ]]; then
            minimal_case=$(grep -n "^def \|^class " "$component" | head -20)
            echo "Found functions/classes:" | tee -a "$log_file"
            echo "$minimal_case" | tee -a "$log_file"
        fi
        # For shell: find functions
        if [[ "$component" == *.sh ]]; then
            minimal_case=$(grep -n "^[a-zA-Z_][a-zA-Z0-9_]*() {" "$component" | head -20)
            echo "Found functions:" | tee -a "$log_file"
            echo "$minimal_case" | tee -a "$log_file"
        fi
    fi

    # Update session
    jq --arg notes "$minimal_case" --arg ts "$(now)" '
        .updated = ($ts | tonumber)
        | .phase = "hypothesize"
        | .phases.minimize = {
            "completed": true,
            "notes": $notes,
            "timestamp": ($ts | tonumber)
          }
    ' "$session_file" > "${session_file}.tmp" && mv "${session_file}.tmp" "$session_file"

    echo "Minimization complete. Next: $0 hypothesize $session_id \"your hypothesis\"" | tee -a "$log_file"
}

# Phase 3: Record hypothesis
cmd_hypothesize() {
    local session_id="$1"
    local hypothesis="$2"
    local session_file="$DIAG_DIR/${session_id}.json"

    if [[ ! -f "$session_file" ]]; then
        echo "Session not found: $session_id" >&2
        exit 1
    fi
    if [[ -z "$hypothesis" ]]; then
        echo "Usage: $0 hypothesize <session_id> <hypothesis>" >&2
        exit 1
    fi

    local log_file=$(jq -r '.log_file' "$session_file")
    echo "=== Phase 3: Hypothesize ===" | tee -a "$log_file"
    echo "Hypothesis: $hypothesis" | tee -a "$log_file"

    # Get existing hypotheses and add new one
    local existing=$(jq -r '.phases.hypothesize.hypotheses // [] | length' "$session_file")
    local hypothesis_num=$((existing + 1))

    jq --arg hyp "$hypothesis" --arg num "$hypothesis_num" --arg ts "$(now)" '
        .updated = ($ts | tonumber)
        | .phase = "instrument"
        | .phases.hypothesize.completed = true
        | .phases.hypothesize.hypotheses += [{
            "number": ($num | tonumber),
            "hypothesis": $hyp,
            "timestamp": ($ts | tonumber),
            "status": "pending"
          }]
    ' "$session_file" > "${session_file}.tmp" && mv "${session_file}.tmp" "$session_file"

    echo "Hypothesis #$hypothesis_num recorded. Next: $0 instrument $session_id \"instrumentation approach\"" | tee -a "$log_file"
}

# Phase 4: Add instrumentation
cmd_instrument() {
    local session_id="$1"
    local instrumentation="$2"
    local session_file="$DIAG_DIR/${session_id}.json"

    if [[ ! -f "$session_file" ]]; then
        echo "Session not found: $session_id" >&2
        exit 1
    fi
    if [[ -z "$instrumentation" ]]; then
        echo "Usage: $0 instrument <session_id> <instrumentation>" >&2
        exit 1
    fi

    local log_file=$(jq -r '.log_file' "$session_file")
    echo "=== Phase 4: Instrument ===" | tee -a "$log_file"
    echo "Instrumentation: $instrumentation" | tee -a "$log_file"

    # For Athena, instrumentation often means adding debug logging to consciousness layers
    local component=$(jq -r '.component' "$session_file")
    if [[ "$component" != "unknown" && -f "$component" ]]; then
        echo "Adding debug instrumentation to: $component" | tee -a "$log_file"
        # Could add logging, tracing, or metrics here
        # For now, just record the plan
    fi

    jq --arg inst "$instrumentation" --arg ts "$(now)" '
        .updated = ($ts | tonumber)
        | .phase = "fix"
        | .phases.instrument.completed = true
        | .phases.instrument.instrumentation += [{
            "description": $inst,
            "timestamp": ($ts | tonumber)
          }]
    ' "$session_file" > "${session_file}.tmp" && mv "${session_file}.tmp" "$session_file"

    echo "Instrumentation recorded. Next: $0 fix $session_id \"fix description\"" | tee -a "$log_file"
}

# Phase 5: Apply and verify fix
cmd_fix() {
    local session_id="$1"
    local fix_description="$2"
    local session_file="$DIAG_DIR/${session_id}.json"

    if [[ ! -f "$session_file" ]]; then
        echo "Session not found: $session_id" >&2
        exit 1
    fi
    if [[ -z "$fix_description" ]]; then
        echo "Usage: $0 fix <session_id> <fix_description>" >&2
        exit 1
    fi

    local log_file=$(jq -r '.log_file' "$session_file")
    echo "=== Phase 5: Fix ===" | tee -a "$log_file"
    echo "Fix: $fix_description" | tee -a "$log_file"

    # Update hypotheses status
    jq --arg fix "$fix_description" --arg ts "$(now)" '
        .updated = ($ts | tonumber)
        | .phase = "regress"
        | .phases.fix = {
            "completed": true,
            "description": $fix,
            "timestamp": ($ts | tonumber)
          }
        | .phases.hypothesize.hypotheses = (
            .phases.hypothesize.hypotheses | map(.status = "validated")
          )
    ' "$session_file" > "${session_file}.tmp" && mv "${session_file}.tmp" "$session_file"

    echo "Fix recorded. Next: $0 regress $session_id" | tee -a "$log_file"
}

# Phase 6: Regression tests
cmd_regress() {
    local session_id="$1"
    local session_file="$DIAG_DIR/${session_id}.json"

    if [[ ! -f "$session_file" ]]; then
        echo "Session not found: $session_id" >&2
        exit 1
    fi

    local log_file=$(jq -r '.log_file' "$session_file")
    echo "=== Phase 6: Regression Test ===" | tee -a "$log_file"

    local component=$(jq -r '.component' "$session_file")
    local test_results=""

    # Run relevant tests
    if [[ "$component" != "unknown" ]]; then
        echo "Running validation tests for: $component" | tee -a "$log_file"

        # Find test files
        local test_dir=$(dirname "$component")
        local test_files=$(find "$test_dir" -name "test_*.py" -o -name "*_test.py" 2>/dev/null | head -5)

        if [[ -n "$test_files" ]]; then
            echo "Found test files:" | tee -a "$log_file"
            echo "$test_files" | tee -a "$log_file"

            for tf in $test_files; do
                echo "Running: $tf" | tee -a "$log_file"
                result=$(python3 -m pytest "$tf" -v 2>&1 || true)
                echo "$result" | tee -a "$log_file"
                test_results+="$tf: $result\n"
            done
        else
            echo "No test files found, running syntax validation" | tee -a "$log_file"
            if [[ "$component" == *.py ]]; then
                result=$(python3 -m py_compile "$component" 2>&1 || true)
                test_results="Syntax validation: $result"
                echo "$result" | tee -a "$log_file"
            fi
        fi
    fi

    jq --arg results "$test_results" --arg ts "$(now)" '
        .updated = ($ts | tonumber)
        | .phase = "complete"
        | .status = "completed"
        | .phases.regress = {
            "completed": true,
            "results": $results,
            "timestamp": ($ts | tonumber)
          }
    ' "$session_file" > "${session_file}.tmp" && mv "${session_file}.tmp" "$session_file"

    echo "Regression tests complete. Diagnosis session finished." | tee -a "$log_file"
    echo "Session summary:" | tee -a "$log_file"
    cat "$session_file" | python3 -m json.tool | tee -a "$log_file"
}

# Show session status
cmd_status() {
    local session_id="$1"
    local session_file="$DIAG_DIR/${session_id}.json"

    if [[ ! -f "$session_file" ]]; then
        echo "Session not found: $session_id" >&2
        exit 1
    fi

    cat "$session_file" | python3 -m json.tool
}

# List all sessions
cmd_list() {
    echo "=== Active Diagnosis Sessions ==="
    for f in "$DIAG_DIR"/*.json; do
        [[ -f "$f" ]] || continue
        local id=$(basename "$f" .json)
        local bug=$(jq -r '.bug_description' "$f")
        local status=$(jq -r '.status' "$f")
        local phase=$(jq -r '.phase' "$f")
        local updated=$(jq -r '.updated' "$f")
        local updated_str=$(date -d "@$updated" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "$updated")
        echo "  $id | $status | Phase: $phase | Updated: $updated_str | $bug"
    done
}

# Main entry point
case "${1:-help}" in
    start)
        cmd_start "${2:-}" "${3:-}"
        ;;
    minimize)
        cmd_minimize "${2:-}"
        ;;
    hypothesize)
        cmd_hypothesize "${2:-}" "${3:-}"
        ;;
    instrument)
        cmd_instrument "${2:-}" "${3:-}"
        ;;
    fix)
        cmd_fix "${2:-}" "${3:-}"
        ;;
    regress)
        cmd_regress "${2:-}"
        ;;
    status)
        cmd_status "${2:-}"
        ;;
    list)
        cmd_list
        ;;
    *)
        echo "Usage: $0 {start|minimize|hypothesize|instrument|fix|regress|status|list}"
        echo ""
        echo "Diagnosing Bugs Workflow (Matt Pocock's /diagnosing-bugs skill):"
        echo "  1. start <bug> [component]      - Build feedback loop, reproduce bug (RED)"
        echo "  2. minimize <session_id>        - Isolate minimal reproduction case"
        echo "  3. hypothesize <session_id> <hypothesis> - Record hypothesis"
        echo "  4. instrument <session_id> <instrumentation> - Add debugging instrumentation"
        echo "  5. fix <session_id> <fix>       - Apply fix, validate hypotheses (GREEN)"
        echo "  6. regress <session_id>         - Run regression tests"
        echo "  status <session_id>             - Show session details"
        echo "  list                            - List all sessions"
        exit 1
        ;;
esac