#!/usr/bin/bash
# athena_grill_with_docs.sh - Documentation-driven grilling/questioning for Athena
# Implements Matt Pocock's grill-with-docs/grilling skill with Athena-specific enhancements
#
# Usage:
#   athena_grill_with_docs.sh start <topic> [docs_path]  → Start grilling session
#   athena_grill_with_docs.sh question <session_id> <q>  → Add question
#   athena_grill_with_docs.sh answer <session_id> <a>    → Add answer
#   athena_grill_with_docs.sh synthesize <session_id>    → Synthesize Q&A
#   athena_grill_with_docs.sh status <session_id>        → Show session status

set -o pipefail

BASE_DIR="/root"
BIN_DIR="$BASE_DIR/.local/bin"
source "$BIN_DIR/athena_env.sh" 2>/dev/null

DATA_DIR="/opt/athena/state"
GRILL_DIR="$DATA_DIR/grill_sessions"
LOG_DIR="$DATA_DIR/workflow_logs"

mkdir -p "$GRILL_DIR" "$LOG_DIR"

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

cmd_start() {
    local topic="$1"
    local docs_path="${2:-}"
    local session_id="grill_$(now)"
    local session_file="$GRILL_DIR/${session_id}.json"
    local log_file="$LOG_DIR/${session_id}.log"

    if [[ -z "$topic" ]]; then
        echo "Usage: $0 start <topic> [docs_path]" >&2
        exit 1
    fi

    echo "=== Athena Grill with Docs: Starting Session ===" | tee "$log_file"
    echo "Session ID: $session_id" | tee -a "$log_file"
    echo "Topic: $topic" | tee -a "$log_file"
    echo "Docs Path: $docs_path" | tee -a "$log_file"
    echo "Started: $(now_iso)" | tee -a "$log_file"
    echo "---" | tee -a "$log_file"

    local doc_content=""
    if [[ -n "$docs_path" && -f "$docs_path" ]]; then
        docs_path=$(validate_path "$docs_path") || exit 1
        doc_content=$(head -500 "$docs_path")
        echo "Loaded documentation from: $docs_path" | tee -a "$log_file"
    elif [[ -n "$docs_path" && -d "$docs_path" ]]; then
        docs_path=$(validate_path "$docs_path") || exit 1
        doc_content=$(find "$docs_path" -name "*.md" -exec head -100 {} \; 2>/dev/null | head -500)
        echo "Loaded documentation from directory: $docs_path" | tee -a "$log_file"
    fi

    cat > "$session_file" <<EOF
{
  "session_id": "$session_id",
  "topic": "$topic",
  "docs_path": "$docs_path",
  "doc_content": $(echo "$doc_content" | jq -R . | jq -s .),
  "created": $(now),
  "updated": $(now),
  "status": "active",
  "phase": "question",
  "qa_pairs": [],
  "synthesis": "",
  "log_file": "$log_file"
}
EOF

    echo "Grilling session created. Next: $0 question $session_id \"your question\"" | tee -a "$log_file"
}

cmd_question() {
    local session_id="$1"
    local question="$2"
    local session_file="$GRILL_DIR/${session_id}.json"

    if [[ ! -f "$session_file" ]]; then
        echo "Session not found: $session_id" >&2
        exit 1
    fi
    if [[ -z "$question" ]]; then
        echo "Usage: $0 question <session_id> <question>" >&2
        exit 1
    fi

    local log_file=$(jq -r '.log_file' "$session_file")
    local topic=$(jq -r '.topic' "$session_file")
    local doc_content=$(jq -r '.doc_content' "$session_file")

    echo "=== Adding Question ===" | tee -a "$log_file"
    echo "Q: $question" | tee -a "$log_file"

    local q_num=$(jq '.qa_pairs | length' "$session_file")
    q_num=$((q_num + 1))

    jq --arg q "$question" --argjson num "$q_num" --arg ts "$(now)" '
        .updated = ($ts | tonumber)
        | .phase = "question"
        | .qa_pairs += [{
            "number": $num,
            "question": $q,
            "answer": "",
            "timestamp": ($ts | tonumber)
          }]
    ' "$session_file" > "${session_file}.tmp" && mv "${session_file}.tmp" "$session_file"

    echo "Question #$q_num recorded. Next: $0 answer $session_id \"your answer\" OR $0 question $session_id \"another question\"" | tee -a "$log_file"
}

cmd_answer() {
    local session_id="$1"
    local answer="$2"
    local session_file="$GRILL_DIR/${session_id}.json"

    if [[ ! -f "$session_file" ]]; then
        echo "Session not found: $session_id" >&2
        exit 1
    fi
    if [[ -z "$answer" ]]; then
        echo "Usage: $0 answer <session_id> <answer>" >&2
        exit 1
    fi

    local log_file=$(jq -r '.log_file' "$session_file")

    echo "=== Adding Answer ===" | tee -a "$log_file"
    echo "A: $answer" | tee -a "$log_file"

    local last_idx=$(jq '.qa_pairs | length - 1' "$session_file")

    jq --arg ans "$answer" --argjson idx "$last_idx" --arg ts "$(now)" '
        .updated = ($ts | tonumber)
        | .phase = "answer"
        | .qa_pairs[$idx].answer = $ans
        | .qa_pairs[$idx].answered_at = ($ts | tonumber)
    ' "$session_file" > "${session_file}.tmp" && mv "${session_file}.tmp" "$session_file"

    echo "Answer recorded. Next: $0 question $session_id \"another question\" OR $0 synthesize $session_id" | tee -a "$log_file"
}

cmd_synthesize() {
    local session_id="$1"
    local session_file="$GRILL_DIR/${session_id}.json"

    if [[ ! -f "$session_file" ]]; then
        echo "Session not found: $session_id" >&2
        exit 1
    fi

    local log_file=$(jq -r '.log_file' "$session_file")
    local topic=$(jq -r '.topic' "$session_file")
    local doc_content=$(jq -r '.doc_content' "$session_file")

    echo "=== Synthesizing Grilling Session ===" | tee -a "$log_file"

    local synthesis="Grilling Synthesis for: $topic\n\n"
    synthesis+="Documentation consulted: $(jq -r '.docs_path' "$session_file")\n\n"
    synthesis+="Q&A Pairs:\n\n"

    local qa_pairs=$(jq -c '.qa_pairs[]' "$session_file" 2>/dev/null)
    while IFS= read -r pair; do
        [[ -z "$pair" ]] && continue
        local num=$(echo "$pair" | jq -r '.number')
        local q=$(echo "$pair" | jq -r '.question')
        local a=$(echo "$pair" | jq -r '.answer')
        synthesis+="Q$num: $q\n"
        synthesis+="A$num: $a\n\n"
    done <<< "$qa_pairs"

    synthesis+="Key Insights:\n"
    synthesis+="1. Questions reveal understanding gaps in: $topic\n"
    synthesis+="2. Answers should be validated against documentation\n"
    synthesis+="3. Follow-up questions recommended for unanswered areas\n"
    synthesis+="4. Consider creating teach lesson from this session\n"

    jq --arg synthesis "$synthesis" --arg ts "$(now)" '
        .updated = ($ts | tonumber)
        | .phase = "complete"
        | .status = "completed"
        | .synthesis = $synthesis
    ' "$session_file" > "${session_file}.tmp" && mv "${session_file}.tmp" "$session_file"

    echo -e "$synthesis" | tee -a "$log_file"
    echo "Session saved: $session_file" | tee -a "$log_file"
}

cmd_status() {
    local session_id="$1"
    local session_file="$GRILL_DIR/${session_id}.json"

    if [[ ! -f "$session_file" ]]; then
        echo "Session not found: $session_id" >&2
        exit 1
    fi

    cat "$session_file" | python3 -m json.tool
}

case "${1:-help}" in
    start)
        cmd_start "${2:-}" "${3:-}"
        ;;
    question)
        cmd_question "${2:-}" "${3:-}"
        ;;
    answer)
        cmd_answer "${2:-}" "${3:-}"
        ;;
    synthesize)
        cmd_synthesize "${2:-}"
        ;;
    status)
        cmd_status "${2:-}"
        ;;
    *)
        echo "Usage: $0 {start|question|answer|synthesize|status}"
        echo "  start <topic> [docs_path]     - Start grilling session with optional docs"
        echo "  question <session_id> <q>     - Add question to session"
        echo "  answer <session_id> <a>       - Add answer to last question"
        echo "  synthesize <session_id>       - Synthesize all Q&A"
        echo "  status <session_id>           - Show session details"
        exit 1
        ;;
esac