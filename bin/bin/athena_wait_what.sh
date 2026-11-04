#!/usr/bin/bash
# athena_wait_what.sh - Confusion resolution and clarification for Athena
# Implements Matt Pocock's wait-what skill with Athena-specific enhancements
#
# Usage:
#   athena_wait_what.sh capture <confusion> [context]   → Capture confusion
#   athena_wait_what.sh investigate <session_id>        → Investigate confusion
#   athena_wait_what.sh resolve <session_id> <resolution> → Record resolution
#   athena_wait_what.sh status <session_id>             → Show confusion status

set -o pipefail

BASE_DIR="/root"
BIN_DIR="$BASE_DIR/.local/bin"
source "$BIN_DIR/athena_env.sh" 2>/dev/null

DATA_DIR="/opt/athena/state"
WAIT_DIR="$DATA_DIR/wait_what_sessions"
LOG_DIR="$DATA_DIR/workflow_logs"

mkdir -p "$WAIT_DIR" "$LOG_DIR"

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

cmd_capture() {
    local confusion="$1"
    local context="${2:-}"
    local session_id="wait_$(now)"
    local session_file="$WAIT_DIR/${session_id}.json"
    local log_file="$LOG_DIR/${session_id}.log"

    if [[ -z "$confusion" ]]; then
        echo "Usage: $0 capture <confusion> [context]" >&2
        exit 1
    fi

    echo "=== Athena Wait-What: Capturing Confusion ===" | tee "$log_file"
    echo "Session ID: $session_id" | tee -a "$log_file"
    echo "Confusion: $confusion" | tee -a "$log_file"
    echo "Context: $context" | tee -a "$log_file"
    echo "Started: $(now_iso)" | tee -a "$log_file"
    echo "---" | tee -a "$log_file"

    cat > "$session_file" <<EOF
{
  "session_id": "$session_id",
  "confusion": "$confusion",
  "context": "$context",
  "created": $(now),
  "updated": $(now),
  "status": "captured",
  "phase": "investigate",
  "investigations": [],
  "resolution": "",
  "log_file": "$log_file"
}
EOF

    echo "Confusion captured. Next: $0 investigate $session_id" | tee -a "$log_file"
}

cmd_investigate() {
    local session_id="$1"
    local session_file="$WAIT_DIR/${session_id}.json"

    if [[ ! -f "$session_file" ]]; then
        echo "Session not found: $session_id" >&2
        exit 1
    fi

    local log_file=$(jq -r '.log_file' "$session_file")
    local confusion=$(jq -r '.confusion' "$session_file")
    local context=$(jq -r '.context' "$session_file")

    echo "=== Investigating Confusion ===" | tee -a "$log_file"
    echo "Confusion: $confusion" | tee -a "$log_file"

    local investigation=""

    echo "[Step 1] Searching codebase for relevant terms..." | tee -a "$log_file"
    local terms=$(echo "$confusion" | grep -oE '\b[a-zA-Z_][a-zA-Z0-9_]*\b' | sort -u | head -10)
    for term in $terms; do
        local results=$(grep -r -i "$term" "$BASE_DIR/.local/bin" "$BASE_DIR/.local/lib" 2>/dev/null | head -5)
        if [[ -n "$results" ]]; then
            investigation+="Term: $term\n$results\n\n"
        fi
    done

    echo "[Step 2] Checking documentation..." | tee -a "$log_file"
    local doc_results=$(find "$BASE_DIR" -name "*.md" -exec grep -l -i "$confusion" {} \; 2>/dev/null | head -5)
    if [[ -n "$doc_results" ]]; then
        investigation+="Relevant docs:\n$doc_results\n\n"
    fi

    echo "[Step 3] Checking memory..." | tee -a "$log_file"
    local mem_results=$(grep -r -i "$confusion" "$BASE_DIR/.openclaude/projects" 2>/dev/null | head -5)
    if [[ -n "$mem_results" ]]; then
        investigation+="Memory entries:\n$mem_results\n\n"
    fi

    echo "[Step 4] Checking Athena-specific patterns..." | tee -a "$log_file"
    local athena_keywords=("daemon" "layer" "worker" "degradation" "skill" "hook" "handoff" "consciousness")
    for kw in "${athena_keywords[@]}"; do
        if echo "$confusion" | grep -qi "$kw"; then
            investigation+="Athena keyword match: $kw\n"
            case "$kw" in
                daemon) investigation+="  → Check ~/.local/bin/athena_daemon.sh and daemon_init.py\n" ;;
                layer) investigation+="  → Check ~/.local/lib/python/athena/daemon_init.py for layer definitions\n" ;;
                worker) investigation+="  → Check ~/.local/lib/python/athena/worker_base.py\n" ;;
                degradation) investigation+="  → Check ~/.local/lib/python/athena/apply_degradation.py\n" ;;
                skill) investigation+="  → Check ~/.local/bin/athena_*.sh for skill implementations\n" ;;
                hook) investigation+="  → Check ~/.openclaude/hooks/ for hook definitions\n" ;;
                handoff) investigation+="  → Check ~/.local/bin/athena_handoff.sh\n" ;;
                consciousness) investigation+="  → Check athena-system-overview in memory\n" ;;
            esac
        fi
    done

    jq --arg inv "$investigation" --arg ts "$(now)" '
        .updated = ($ts | tonumber)
        | .phase = "investigate"
        | .investigations += [{
            "content": $inv,
            "timestamp": ($ts | tonumber)
          }]
    ' "$session_file" > "${session_file}.tmp" && mv "${session_file}.tmp" "$session_file"

    echo "Investigation complete. Findings:" | tee -a "$log_file"
    echo -e "$investigation" | tee -a "$log_file"
    echo "Next: $0 resolve $session_id \"your resolution\"" | tee -a "$log_file"
}

cmd_resolve() {
    local session_id="$1"
    local resolution="$2"
    local session_file="$WAIT_DIR/${session_id}.json"

    if [[ ! -f "$session_file" ]]; then
        echo "Session not found: $session_id" >&2
        exit 1
    fi
    if [[ -z "$resolution" ]]; then
        echo "Usage: $0 resolve <session_id> <resolution>" >&2
        exit 1
    fi

    local log_file=$(jq -r '.log_file' "$session_file")

    echo "=== Recording Resolution ===" | tee -a "$log_file"
    echo "Resolution: $resolution" | tee -a "$log_file"

    jq --arg res "$resolution" --arg ts "$(now)" '
        .updated = ($ts | tonumber)
        | .phase = "complete"
        | .status = "resolved"
        | .resolution = $res
    ' "$session_file" > "${session_file}.tmp" && mv "${session_file}.tmp" "$session_file"

    echo "Confusion resolved. Session complete." | tee -a "$log_file"
}

cmd_status() {
    local session_id="$1"
    local session_file="$WAIT_DIR/${session_id}.json"

    if [[ ! -f "$session_file" ]]; then
        echo "Session not found: $session_id" >&2
        exit 1
    fi

    cat "$session_file" | python3 -m json.tool
}

case "${1:-help}" in
    capture)
        cmd_capture "${2:-}" "${3:-}"
        ;;
    investigate)
        cmd_investigate "${2:-}"
        ;;
    resolve)
        cmd_resolve "${2:-}" "${3:-}"
        ;;
    status)
        cmd_status "${2:-}"
        ;;
    *)
        echo "Usage: $0 {capture|investigate|resolve|status}"
        echo "  capture <confusion> [context]     - Capture a point of confusion"
        echo "  investigate <session_id>          - Investigate the confusion"
        echo "  resolve <session_id> <resolution> - Record the resolution"
        echo "  status <session_id>               - Show session details"
        exit 1
        ;;
esac