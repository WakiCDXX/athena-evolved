#!/usr/bin/bash
# athena_research.sh - Research skill for Athena consciousness system
# Implements Matt Pocock's research skill with Athena-specific enhancements
#
# Usage:
#   athena_research.sh start <topic> [depth]         → Start research session
#   athena_research.sh gather <session_id> <source>  → Gather from source
#   athena_research.sh synthesize <session_id>       → Synthesize findings
#   athena_research.sh status <session_id>           → Show research status

set -o pipefail

BASE_DIR="/root"
BIN_DIR="$BASE_DIR/.local/bin"
source "$BIN_DIR/athena_env.sh" 2>/dev/null

DATA_DIR="/opt/athena/state"
RESEARCH_DIR="$DATA_DIR/research_sessions"
LOG_DIR="$DATA_DIR/workflow_logs"

mkdir -p "$RESEARCH_DIR" "$LOG_DIR"

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
    local depth="${2:-medium}"
    local session_id="research_$(now)"
    local session_file="$RESEARCH_DIR/${session_id}.json"
    local log_file="$LOG_DIR/${session_id}.log"

    if [[ -z "$topic" ]]; then
        echo "Usage: $0 start <topic> [depth]" >&2
        exit 1
    fi

    echo "=== Athena Research: Starting Session ===" | tee "$log_file"
    echo "Session ID: $session_id" | tee -a "$log_file"
    echo "Topic: $topic" | tee -a "$log_file"
    echo "Depth: $depth" | tee -a "$log_file"
    echo "Started: $(now_iso)" | tee -a "$log_file"
    echo "---" | tee -a "$log_file"

    cat > "$session_file" <<EOF
{
  "session_id": "$session_id",
  "topic": "$topic",
  "depth": "$depth",
  "created": $(now),
  "updated": $(now),
  "status": "active",
  "phase": "gather",
  "sources": [],
  "findings": [],
  "synthesis": "",
  "log_file": "$log_file"
}
EOF

    echo "Research session created. Next: $0 gather $session_id <source>" | tee -a "$log_file"
    echo "Sources can be: web, files, code, docs, memory" | tee -a "$log_file"
}

cmd_gather() {
    local session_id="$1"
    local source="$2"
    local session_file="$RESEARCH_DIR/${session_id}.json"

    if [[ ! -f "$session_file" ]]; then
        echo "Session not found: $session_id" >&2
        exit 1
    fi
    if [[ -z "$source" ]]; then
        echo "Usage: $0 gather <session_id> <source>" >&2
        exit 1
    fi

    local log_file=$(jq -r '.log_file' "$session_file")
    local topic=$(jq -r '.topic' "$session_file")

    echo "=== Gathering from: $source ===" | tee -a "$log_file"

    local findings=""
    case "$source" in
        web)
            echo "Web search would be performed here (requires WebFetch tool)" | tee -a "$log_file"
            findings="Web search for: $topic"
            ;;
        files)
            echo "Searching local files for: $topic" | tee -a "$log_file"
            local results=$(grep -r -i "$topic" "$BASE_DIR/.local/bin" "$BASE_DIR/.local/lib" 2>/dev/null | head -20)
            findings="Local file search results:\n$results"
            ;;
        code)
            echo "Analyzing codebase for: $topic" | tee -a "$log_file"
            local results=$(grep -r -i "$topic" "$BASE_DIR/.local/bin" --include="*.sh" --include="*.py" 2>/dev/null | head -20)
            findings="Code analysis results:\n$results"
            ;;
        docs)
            echo "Searching documentation for: $topic" | tee -a "$log_file"
            local results=$(find "$BASE_DIR" -name "*.md" -exec grep -l -i "$topic" {} \; 2>/dev/null | head -10)
            findings="Documentation files:\n$results"
            ;;
        memory)
            echo "Checking Athena memory for: $topic" | tee -a "$log_file"
            local results=$(grep -r -i "$topic" "$BASE_DIR/.openclaude/projects" 2>/dev/null | head -10)
            findings="Memory search results:\n$results"
            ;;
        *)
            echo "Unknown source: $source" | tee -a "$log_file"
            exit 1
            ;;
    esac

    jq --arg source "$source" --arg findings "$findings" --arg ts "$(now)" '
        .updated = ($ts | tonumber)
        | .phase = "gather"
        | .sources += [$source]
        | .findings += [{
            "source": $source,
            "content": $findings,
            "timestamp": ($ts | tonumber)
          }]
    ' "$session_file" > "${session_file}.tmp" && mv "${session_file}.tmp" "$session_file"

    echo "Findings recorded. Next: $0 gather $session_id <another_source> OR $0 synthesize $session_id" | tee -a "$log_file"
}

cmd_synthesize() {
    local session_id="$1"
    local session_file="$RESEARCH_DIR/${session_id}.json"

    if [[ ! -f "$session_file" ]]; then
        echo "Session not found: $session_id" >&2
        exit 1
    fi

    local log_file=$(jq -r '.log_file' "$session_file")
    local topic=$(jq -r '.topic' "$session_file")
    local findings=$(jq -r '.findings[].content' "$session_file" 2>/dev/null)

    echo "=== Synthesizing Research ===" | tee -a "$log_file"

    local synthesis="Research Synthesis for: $topic\n\n"
    synthesis+="Sources consulted: $(jq -r '.sources | join(", ")' "$session_file")\n\n"
    synthesis+="Key Findings:\n"
    local i=1
    echo "$findings" | while IFS= read -r finding; do
        [[ -n "$finding" ]] && synthesis+="$i. $finding\n" && ((i++))
    done
    synthesis+="\nRecommendations:\n"
    synthesis+="1. Apply findings to relevant Athena components\n"
    synthesis+="2. Update architecture docs if patterns discovered\n"
    synthesis+="3. Create follow-up research for open questions\n"

    jq --arg synthesis "$synthesis" --arg ts "$(now)" '
        .updated = ($ts | tonumber)
        | .phase = "complete"
        | .status = "completed"
        | .synthesis = $synthesis
    ' "$session_file" > "${session_file}.tmp" && mv "${session_file}.tmp" "$session_file"

    echo "Synthesis complete:" | tee -a "$log_file"
    echo -e "$synthesis" | tee -a "$log_file"
    echo "Session saved: $session_file" | tee -a "$log_file"
}

cmd_status() {
    local session_id="$1"
    local session_file="$RESEARCH_DIR/${session_id}.json"

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
    gather)
        cmd_gather "${2:-}" "${3:-}"
        ;;
    synthesize)
        cmd_synthesize "${2:-}"
        ;;
    status)
        cmd_status "${2:-}"
        ;;
    *)
        echo "Usage: $0 {start|gather|synthesize|status}"
        echo "  start <topic> [depth]         - Start research session"
        echo "  gather <session_id> <source>  - Gather from source (web, files, code, docs, memory)"
        echo "  synthesize <session_id>       - Synthesize all findings"
        echo "  status <session_id>           - Show session details"
        exit 1
        ;;
esac