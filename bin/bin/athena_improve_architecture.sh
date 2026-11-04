#!/usr/bin/bash
# athena_improve_architecture.sh - Codebase architecture improvement for Athena
# Implements Matt Pocock's improve-codebase-architecture skill with Athena-specific enhancements
#
# Usage:
#   athena_improve_architecture.sh analyze <component>          → Analyze architecture
#   athena_improve_architecture.sh suggest <session_id>         → Generate suggestions
#   athena_improve_architecture.sh apply <session_id> <suggestion_id> → Apply improvement
#   athena_improve_architecture.sh status <session_id>          → Show session status

set -o pipefail

BASE_DIR="/root"
BIN_DIR="$BASE_DIR/.local/bin"
source "$BIN_DIR/athena_env.sh" 2>/dev/null

DATA_DIR="/opt/athena/state"
ARCH_DIR="$DATA_DIR/architecture_reviews"
LOG_DIR="$DATA_DIR/workflow_logs"

mkdir -p "$ARCH_DIR" "$LOG_DIR"

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

cmd_analyze() {
    local component="$1"
    local session_id="arch_$(now)"
    local session_file="$ARCH_DIR/${session_id}.json"
    local log_file="$LOG_DIR/${session_id}.log"

    if [[ -z "$component" ]]; then
        echo "Usage: $0 analyze <component>" >&2
        exit 1
    fi

    component=$(validate_path "$component") || exit 1

    echo "=== Athena Architecture Improvement: Analysis ===" | tee "$log_file"
    echo "Session ID: $session_id" | tee -a "$log_file"
    echo "Component: $component" | tee -a "$log_file"
    echo "Started: $(now_iso)" | tee -a "$log_file"
    echo "---" | tee -a "$log_file"

    local analysis=""
    local suggestions=()

    echo "[Phase 1] Structural analysis..." | tee -a "$log_file"
    if [[ -d "$component" ]]; then
        local file_count=$(find "$component" -type f \( -name "*.sh" -o -name "*.py" \) | wc -l)
        local dir_count=$(find "$component" -type d | wc -l)
        analysis+="Directory structure: $file_count code files in $dir_count directories\n"

        if [[ $file_count -gt 20 ]]; then
            suggestions+=("Split large module: $component has $file_count files, consider submodules")
        fi
    elif [[ -f "$component" ]]; then
        local lines=$(wc -l < "$component")
        local functions=$(grep -c "^[a-zA-Z_][a-zA-Z0-9_]*() {" "$component" 2>/dev/null || echo 0)
        local classes=$(grep -c "^class " "$component" 2>/dev/null || echo 0)
        analysis+="File: $lines lines, $functions functions, $classes classes\n"

        if [[ $lines -gt 500 ]]; then
            suggestions+=("Extract modules: File exceeds 500 lines ($lines)")
        fi
        if [[ $functions -gt 20 ]]; then
            suggestions+=("Split functions: $functions functions in single file, consider separation")
        fi
    fi

    echo "[Phase 2] Coupling analysis..." | tee -a "$log_file"
    local imports=$(grep -h "source\|import \|require\|include" "$component" 2>/dev/null | sort -u)
    local import_count=$(echo "$imports" | grep -v "^$" | wc -l)
    analysis+="External dependencies: $import_count\n"
    echo "$imports" | while read -r imp; do
        [[ -n "$imp" ]] && analysis+="  - $imp\n"
    done
    if [[ $import_count -gt 15 ]]; then
        suggestions+=("Reduce coupling: $import_count external dependencies")
    fi

    echo "[Phase 3] Cohesion analysis..." | tee -a "$log_file"
    if [[ -f "$component" ]]; then
        local purpose_keywords=$(grep -E "^#|^\"\"\"" "$component" | head -5)
        if [[ -z "$purpose_keywords" ]]; then
            suggestions+=("Add documentation: Missing clear purpose statement")
        fi
    fi

    echo "[Phase 4] Athena-specific patterns..." | tee -a "$log_file"
    if [[ -d "$component" ]]; then
        local has_daemon=$(find "$component" -name "*daemon*" -type f | wc -l)
        local has_workers=$(find "$component" -name "*worker*" -type f | wc -l)
        local has_state=$(find "$component" -name "*state*" -type f | wc -l)
        if [[ $has_daemon -gt 0 && $has_workers -gt 0 ]]; then
            analysis+="Athena pattern: Daemon + Workers detected\n"
            if [[ $has_state -eq 0 ]]; then
                suggestions+=("Add state management: Daemon/worker pattern without state persistence")
            fi
        fi
    fi

    echo "[Phase 5] Degradation readiness..." | tee -a "$log_file"
    if [[ -f "$component" ]] || [[ -d "$component" ]]; then
        local has_degradation=$(grep -r "degradation\|conserve\|minimal\|suspended" "$component" 2>/dev/null | wc -l)
        if [[ $has_degradation -eq 0 ]]; then
            suggestions+=("Add degradation support: Component lacks progressive degradation hooks")
        fi
    fi

    cat > "$session_file" <<EOF
{
  "session_id": "$session_id",
  "component": "$component",
  "created": $(now),
  "updated": $(now),
  "status": "analyzed",
  "analysis": $(echo "$analysis" | jq -R . | jq -s .),
  "suggestions": $(printf '%s\n' "${suggestions[@]}" | jq -R . | jq -s .),
  "log_file": "$log_file"
}
EOF

    echo "Analysis complete. Suggestions:" | tee -a "$log_file"
    for i in "${!suggestions[@]}"; do
        echo "  $((i+1)). ${suggestions[$i]}" | tee -a "$log_file"
    done
    echo "Session saved: $session_file" | tee -a "$log_file"
    echo "Next: $0 suggest $session_id" | tee -a "$log_file"
}

cmd_suggest() {
    local session_id="$1"
    local session_file="$ARCH_DIR/${session_id}.json"

    if [[ ! -f "$session_file" ]]; then
        echo "Session not found: $session_id" >&2
        exit 1
    fi

    local log_file=$(jq -r '.log_file' "$session_file")
    echo "=== Architecture Suggestions ===" | tee -a "$log_file"

    local suggestions=$(jq -r '.suggestions[]' "$session_file" 2>/dev/null)
    local count=$(echo "$suggestions" | grep -v "^$" | wc -l)

    if [[ $count -eq 0 ]]; then
        echo "No suggestions generated." | tee -a "$log_file"
    else
        echo "Generated $count suggestions:" | tee -a "$log_file"
        local i=1
        echo "$suggestions" | while read -r s; do
            [[ -n "$s" ]] && echo "  $i. $s" | tee -a "$log_file"
            ((i++))
        done
    fi

    jq --arg ts "$(now)" '.updated = ($ts | tonumber) | .status = "suggested"' "$session_file" > "${session_file}.tmp" && mv "${session_file}.tmp" "$session_file"
    echo "Next: $0 apply $session_id <suggestion_number>" | tee -a "$log_file"
}

cmd_apply() {
    local session_id="$1"
    local suggestion_num="$2"
    local session_file="$ARCH_DIR/${session_id}.json"

    if [[ ! -f "$session_file" ]]; then
        echo "Session not found: $session_id" >&2
        exit 1
    fi
    if [[ -z "$suggestion_num" ]]; then
        echo "Usage: $0 apply <session_id> <suggestion_number>" >&2
        exit 1
    fi

    local log_file=$(jq -r '.log_file' "$session_file")
    local suggestion=$(jq -r ".suggestions[$((suggestion_num-1))]" "$session_file")

    echo "=== Applying Suggestion #$suggestion_num ===" | tee -a "$log_file"
    echo "Suggestion: $suggestion" | tee -a "$log_file"

    jq --arg ts "$(now)" --arg applied "$suggestion" '.updated = ($ts | tonumber) | .status = "applied" | .applied_suggestion = $applied' "$session_file" > "${session_file}.tmp" && mv "${session_file}.tmp" "$session_file"

    echo "Suggestion marked as applied. Manual implementation required." | tee -a "$log_file"
}

cmd_status() {
    local session_id="$1"
    local session_file="$ARCH_DIR/${session_id}.json"

    if [[ ! -f "$session_file" ]]; then
        echo "Session not found: $session_id" >&2
        exit 1
    fi

    cat "$session_file" | python3 -m json.tool
}

case "${1:-help}" in
    analyze)
        cmd_analyze "${2:-}"
        ;;
    suggest)
        cmd_suggest "${2:-}"
        ;;
    apply)
        cmd_apply "${2:-}" "${3:-}"
        ;;
    status)
        cmd_status "${2:-}"
        ;;
    *)
        echo "Usage: $0 {analyze|suggest|apply|status}"
        echo "  analyze <component>           - Analyze architecture of component/directory"
        echo "  suggest <session_id>          - Show improvement suggestions"
        echo "  apply <session_id> <num>      - Mark suggestion as applied"
        echo "  status <session_id>           - Show session details"
        exit 1
        ;;
esac