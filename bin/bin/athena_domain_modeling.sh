#!/usr/bin/bash
# athena_domain_modeling.sh - Domain modeling for Athena consciousness system
# Implements Matt Pocock's domain-modeling skill with Athena-specific enhancements
#
# Usage:
#   athena_domain_modeling.sh discover <domain>         → Discover domain model
#   athena_domain_modeling.sh entity <session_id> <name> → Define entity
#   athena_domain_modeling.sh relation <session_id> <from> <to> <type> → Define relationship
#   athena_domain_modeling.sh visualize <session_id>    → Generate visualization
#   athena_domain_modeling.sh status <session_id>       → Show model status

set -o pipefail

BASE_DIR="/root"
BIN_DIR="$BASE_DIR/.local/bin"
source "$BIN_DIR/athena_env.sh" 2>/dev/null

DATA_DIR="/opt/athena/state"
DOMAIN_DIR="$DATA_DIR/domain_models"
LOG_DIR="$DATA_DIR/workflow_logs"

mkdir -p "$DOMAIN_DIR" "$LOG_DIR"

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

cmd_discover() {
    local domain="$1"
    local session_id="domain_$(now)"
    local session_file="$DOMAIN_DIR/${session_id}.json"
    local log_file="$LOG_DIR/${session_id}.log"

    if [[ -z "$domain" ]]; then
        echo "Usage: $0 discover <domain>" >&2
        exit 1
    fi

    echo "=== Athena Domain Modeling: Discovery ===" | tee "$log_file"
    echo "Session ID: $session_id" | tee -a "$log_file"
    echo "Domain: $domain" | tee -a "$log_file"
    echo "Started: $(now_iso)" | tee -a "$log_file"
    echo "---" | tee -a "$log_file"

    local entities=()
    local relationships=()

    case "$domain" in
        athena|consciousness)
            entities=("Layer" "Worker" "Daemon" "State" "Config" "DegradationLevel" "Skill" "Hook" "Memory" "Archive")
            relationships=("Layer HAS Worker" "Daemon ORCHESTRATES Layer" "Layer HAS State" "Daemon READS Config" "State TRACKS DegradationLevel" "Skill EXTENDS Daemon" "Hook TRIGGERS Daemon" "Layer WRITES Memory" "Archive STORES Memory")
            ;;
        daemon|orchestration)
            entities=("Daemon" "LayerConfig" "WorkerProcess" "HealthCheck" "WakeLock" "APIKey" "DegradationState" "StartupSequence")
            relationships=("Daemon MANAGES LayerConfig" "Daemon SPAWNS WorkerProcess" "Daemon MONITORS HealthCheck" "Daemon HOLDS WakeLock" "Daemon VALIDATES APIKey" "Daemon READS DegradationState" "Daemon EXECUTES StartupSequence")
            ;;
        memory|storage)
            entities=("MemoryStore" "Archive" "Backup" "Index" "Query" "RetentionPolicy" "Compression" "Encryption")
            relationships=("MemoryStore WRITES Archive" "Archive CREATES Backup" "MemoryStore MAINTAINS Index" "Query SEARCHES Index" "RetentionPolicy GOVERNS Archive" "Compression APPLIES_TO Archive" "Encryption PROTECTS MemoryStore")
            ;;
        skills|workflows)
            entities=("Skill" "WorkflowChain" "Phase" "Handoff" "Artifact" "Validation" "Session" "Progress")
            relationships=("WorkflowChain CONTAINS Phase" "Phase PRODUCES Artifact" "Phase VALIDATES Validation" "Handoff TRANSFERS Session" "Skill PARTICIPATES_IN WorkflowChain" "Progress TRACKS Phase")
            ;;
        *)
            entities=("Entity" "Attribute" "Relationship")
            relationships=()
            ;;
    esac

    cat > "$session_file" <<EOF
{
  "session_id": "$session_id",
  "domain": "$domain",
  "created": $(now),
  "updated": $(now),
  "status": "discovered",
  "entities": $(printf '%s\n' "${entities[@]}" | jq -R . | jq -s .),
  "relationships": $(printf '%s\n' "${relationships[@]}" | jq -R . | jq -s .),
  "log_file": "$log_file"
}
EOF

    echo "Domain model discovered for: $domain" | tee -a "$log_file"
    echo "Entities found: ${#entities[@]}" | tee -a "$log_file"
    echo "Relationships found: ${#relationships[@]}" | tee -a "$log_file"
    for e in "${entities[@]}"; do echo "  - $e" | tee -a "$log_file"; done
    for r in "${relationships[@]}"; do echo "  - $r" | tee -a "$log_file"; done
    echo "Next: $0 entity $session_id <name> OR $0 relation $session_id <from> <to> <type>" | tee -a "$log_file"
}

cmd_entity() {
    local session_id="$1"
    local name="$2"
    local session_file="$DOMAIN_DIR/${session_id}.json"

    if [[ ! -f "$session_file" ]]; then
        echo "Session not found: $session_id" >&2
        exit 1
    fi
    if [[ -z "$name" ]]; then
        echo "Usage: $0 entity <session_id> <name>" >&2
        exit 1
    fi

    local log_file=$(jq -r '.log_file' "$session_file")

    echo "=== Adding Entity: $name ===" | tee -a "$log_file"

    jq --arg name "$name" --arg ts "$(now)" '
        .updated = ($ts | tonumber)
        | .entities += [$name]
    ' "$session_file" > "${session_file}.tmp" && mv "${session_file}.tmp" "$session_file"

    echo "Entity added. Next: $0 entity $session_id <another> OR $0 relation $session_id <from> <to> <type>" | tee -a "$log_file"
}

cmd_relation() {
    local session_id="$1"
    local from="$2"
    local to="$3"
    local type="$4"
    local session_file="$DOMAIN_DIR/${session_id}.json"

    if [[ ! -f "$session_file" ]]; then
        echo "Session not found: $session_id" >&2
        exit 1
    fi
    if [[ -z "$from" || -z "$to" || -z "$type" ]]; then
        echo "Usage: $0 relation <session_id> <from> <to> <type>" >&2
        exit 1
    fi

    local log_file=$(jq -r '.log_file' "$session_file")
    local relation="$from $type $to"

    echo "=== Adding Relationship: $relation ===" | tee -a "$log_file"

    jq --arg rel "$relation" --arg ts "$(now)" '
        .updated = ($ts | tonumber)
        | .relationships += [$rel]
    ' "$session_file" > "${session_file}.tmp" && mv "${session_file}.tmp" "$session_file"

    echo "Relationship added. Next: $0 relation $session_id <from> <to> <type> OR $0 visualize $session_id" | tee -a "$log_file"
}

cmd_visualize() {
    local session_id="$1"
    local session_file="$DOMAIN_DIR/${session_id}.json"

    if [[ ! -f "$session_file" ]]; then
        echo "Session not found: $session_id" >&2
        exit 1
    fi

    local log_file=$(jq -r '.log_file' "$session_file")
    local domain=$(jq -r '.domain' "$session_file")
    local entities=$(jq -r '.entities[]' "$session_file" 2>/dev/null)
    local relationships=$(jq -r '.relationships[]' "$session_file" 2>/dev/null)

    echo "=== Domain Model Visualization ===" | tee -a "$log_file"
    echo "Domain: $domain" | tee -a "$log_file"
    echo "" | tee -a "$log_file"
    echo "Entities:" | tee -a "$log_file"
    echo "$entities" | while read -r e; do [[ -n "$e" ]] && echo "  [$e]" | tee -a "$log_file"; done
    echo "" | tee -a "$log_file"
    echo "Relationships:" | tee -a "$log_file"
    echo "$relationships" | while read -r r; do [[ -n "$r" ]] && echo "  $r" | tee -a "$log_file"; done
    echo "" | tee -a "$log_file"
    echo "Mermaid Diagram:" | tee -a "$log_file"
    echo "```mermaid" | tee -a "$log_file"
    echo "graph TD" | tee -a "$log_file"
    echo "$entities" | while read -r e; do [[ -n "$e" ]] && echo "    $e" | tee -a "$log_file"; done
    echo "$relationships" | while read -r r; do
        [[ -z "$r" ]] && continue
        local from=$(echo "$r" | awk '{print $1}')
        local type=$(echo "$r" | awk '{print $2}')
        local to=$(echo "$r" | awk '{print $3}')
        echo "    $from -->|$type| $to" | tee -a "$log_file"
    done
    echo "```" | tee -a "$log_file"

    jq --arg ts "$(now)" '.updated = ($ts | tonumber) | .status = "visualized"' "$session_file" > "${session_file}.tmp" && mv "${session_file}.tmp" "$session_file"
}

cmd_status() {
    local session_id="$1"
    local session_file="$DOMAIN_DIR/${session_id}.json"

    if [[ ! -f "$session_file" ]]; then
        echo "Session not found: $session_id" >&2
        exit 1
    fi

    cat "$session_file" | python3 -m json.tool
}

case "${1:-help}" in
    discover)
        cmd_discover "${2:-}"
        ;;
    entity)
        cmd_entity "${2:-}" "${3:-}"
        ;;
    relation)
        cmd_relation "${2:-}" "${3:-}" "${4:-}" "${5:-}"
        ;;
    visualize)
        cmd_visualize "${2:-}"
        ;;
    status)
        cmd_status "${2:-}"
        ;;
    *)
        echo "Usage: $0 {discover|entity|relation|visualize|status}"
        echo "  discover <domain>              - Discover domain model (athena, daemon, memory, skills)"
        echo "  entity <session_id> <name>     - Add entity to model"
        echo "  relation <session_id> <from> <to> <type> - Add relationship"
        echo "  visualize <session_id>         - Show domain model visualization"
        echo "  status <session_id>            - Show session details"
        exit 1
        ;;
esac