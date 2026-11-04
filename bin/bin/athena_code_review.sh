#!/usr/bin/bash
# athena_code_review.sh - Independent code review for Athena consciousness system
# Implements Matt Pocock's code-review skill with Athena-specific enhancements
#
# Usage:
#   athena_code_review.sh review <file> [focus_area]     → Review a file
#   athena_code_review.sh diff <file> [base_branch]       → Review git diff
#   athena_code_review.sh status <session_id>             → Show review status

set -o pipefail

BASE_DIR="/root"
BIN_DIR="$BASE_DIR/.local/bin"
source "$BIN_DIR/athena_env.sh" 2>/dev/null

DATA_DIR="/opt/athena/state"
REVIEW_DIR="$DATA_DIR/code_reviews"
LOG_DIR="$DATA_DIR/workflow_logs"

mkdir -p "$REVIEW_DIR" "$LOG_DIR"

now() { date +%s; }
now_iso() { date -Iseconds; }

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

cmd_review() {
    local file="$1"
    local focus="${2:-general}"
    local session_id="review_$(now)"
    local session_file="$REVIEW_DIR/${session_id}.json"
    local log_file="$LOG_DIR/${session_id}.log"

    if [[ -z "$file" ]]; then
        echo "Usage: $0 review <file> [focus_area]" >&2
        exit 1
    fi

    file=$(validate_path "$file") || exit 1

    echo "=== Athena Code Review: Starting Session ===" | tee "$log_file"
    echo "Session ID: $session_id" | tee -a "$log_file"
    echo "File: $file" | tee -a "$log_file"
    echo "Focus: $focus" | tee -a "$log_file"
    echo "Started: $(now_iso)" | tee -a "$log_file"
    echo "---" | tee -a "$log_file"

    if [[ ! -f "$file" ]]; then
        echo "File not found: $file" | tee -a "$log_file"
        exit 1
    fi

    local findings=""
    local severity_counts='{"critical":0,"high":0,"medium":0,"low":0,"info":0}'

    echo "[Phase 1] Security analysis..." | tee -a "$log_file"
    # Check for common security issues
    if grep -q "eval\|exec\|system\|shell_exec\|passthru\|backtick" "$file" 2>/dev/null; then
        findings+="SECURITY: Potential code injection via eval/exec/system\n"
        severity_counts=$(echo "$severity_counts" | jq '.high += 1')
    fi
    if grep -q "curl\|wget\|fetch" "$file" 2>/dev/null; then
        if ! grep -q "validate_path\|sanitize" "$file" 2>/dev/null; then
            findings+="SECURITY: Network calls without input validation\n"
            severity_counts=$(echo "$severity_counts" | jq '.medium += 1')
        fi
    fi
    if grep -q "chmod.*777\|chmod.*666" "$file" 2>/dev/null; then
        findings+="SECURITY: Overly permissive file permissions\n"
        severity_counts=$(echo "$severity_counts" | jq '.medium += 1')
    fi

    echo "[Phase 2] Correctness analysis..." | tee -a "$log_file"
    if [[ "$file" == *.sh ]]; then
        if ! bash -n "$file" 2>/dev/null; then
            findings+="CORRECTNESS: Shell syntax errors\n"
            severity_counts=$(echo "$severity_counts" | jq '.critical += 1')
        fi
        if grep -q 'set -e' "$file" 2>/dev/null; then
            findings+="CORRECTNESS: Uses 'set -e' but may not handle all error paths\n"
            severity_counts=$(echo "$severity_counts" | jq '.low += 1')
        fi
    elif [[ "$file" == *.py ]]; then
        if ! python3 -m py_compile "$file" 2>/dev/null; then
            findings+="CORRECTNESS: Python syntax errors\n"
            severity_counts=$(echo "$severity_counts" | jq '.critical += 1')
        fi
    fi

    echo "[Phase 3] Performance analysis..." | tee -a "$log_file"
    if grep -q "sleep\|usleep" "$file" 2>/dev/null; then
        findings+="PERFORMANCE: Contains sleep calls - verify necessity\n"
        severity_counts=$(echo "$severity_counts" | jq '.low += 1')
    fi
    if grep -q "find . -name\|grep -r\|ls -R" "$file" 2>/dev/null; then
        findings+="PERFORMANCE: Potentially expensive filesystem operations\n"
        severity_counts=$(echo "$severity_counts" | jq '.low += 1')
    fi

    echo "[Phase 4] Maintainability analysis..." | tee -a "$log_file"
    local lines=$(wc -l < "$file")
    if [[ $lines -gt 500 ]]; then
        findings+="MAINTAINABILITY: File exceeds 500 lines - consider splitting\n"
        severity_counts=$(echo "$severity_counts" | jq '.medium += 1')
    fi
    if grep -q "TODO\|FIXME\|HACK" "$file" 2>/dev/null; then
        findings+="MAINTAINABILITY: Contains TODO/FIXME/HACK markers\n"
        severity_counts=$(echo "$severity_counts" | jq '.info += 1')
    fi

    echo "[Phase 5] Athena-specific checks..." | tee -a "$log_file"
    if grep -q "athena_\|Athena" "$file" 2>/dev/null; then
        if ! grep -q "validate_path\|safe_execute" "$file" 2>/dev/null; then
            findings+="ATHENA: Missing security framework (validate_path/safe_execute)\n"
            severity_counts=$(echo "$severity_counts" | jq '.high += 1')
        fi
        if ! grep -q "set -o pipefail" "$file" 2>/dev/null; then
            findings+="ATHENA: Missing 'set -o pipefail' for robust error handling\n"
            severity_counts=$(echo "$severity_counts" | jq '.medium += 1')
        fi
    fi

    cat > "$session_file" <<EOF
{
  "session_id": "$session_id",
  "file": "$file",
  "focus": "$focus",
  "created": $(now),
  "updated": $(now),
  "status": "completed",
  "findings": $(echo "$findings" | jq -R . | jq -s .),
  "severity_counts": $severity_counts,
  "log_file": "$log_file"
}
EOF

    echo "Review complete. Findings:" | tee -a "$log_file"
    echo -e "$findings" | tee -a "$log_file"
    echo "Session saved: $session_file" | tee -a "$log_file"
}

cmd_diff() {
    local file="$1"
    local base="${2:-HEAD~1}"
    local session_id="review_$(now)"
    local session_file="$REVIEW_DIR/${session_id}.json"
    local log_file="$LOG_DIR/${session_id}.log"

    if [[ -z "$file" ]]; then
        echo "Usage: $0 diff <file> [base_branch]" >&2
        exit 1
    fi

    file=$(validate_path "$file") || exit 1

    echo "=== Athena Code Review: Diff Review ===" | tee "$log_file"
    echo "Session ID: $session_id" | tee -a "$log_file"
    echo "File: $file" | tee -a "$log_file"
    echo "Base: $base" | tee -a "$log_file"
    echo "Started: $(now_iso)" | tee -a "$log_file"

    local diff_output=$(git diff "$base" -- "$file" 2>&1)
    local findings="Diff review for $file against $base:\n$diff_output"

    cat > "$session_file" <<EOF
{
  "session_id": "$session_id",
  "file": "$file",
  "base": "$base",
  "created": $(now),
  "updated": $(now),
  "status": "completed",
  "diff": $(echo "$diff_output" | jq -R . | jq -s .),
  "log_file": "$log_file"
}
EOF

    echo "Diff review saved: $session_file" | tee -a "$log_file"
    echo "$diff_output" | head -100 | tee -a "$log_file"
}

cmd_status() {
    local session_id="$1"
    local session_file="$REVIEW_DIR/${session_id}.json"

    if [[ ! -f "$session_file" ]]; then
        echo "Session not found: $session_id" >&2
        exit 1
    fi

    cat "$session_file" | python3 -m json.tool
}

case "${1:-help}" in
    review)
        cmd_review "${2:-}" "${3:-}"
        ;;
    diff)
        cmd_diff "${2:-}" "${3:-}"
        ;;
    status)
        cmd_status "${2:-}"
        ;;
    *)
        echo "Usage: $0 {review|diff|status}"
        echo "  review <file> [focus]   - Review a file (focus: security, correctness, performance, maintainability, general)"
        echo "  diff <file> [base]      - Review git diff against base (default: HEAD~1)"
        echo "  status <session_id>     - Show review session details"
        exit 1
        ;;
esac