#!/usr/bin/bash
# athena_teach.sh - Teaching/knowledge transfer skill for Athena
# Implements Matt Pocock's teach skill with Athena-specific enhancements
#
# Usage:
#   athena_teach.sh lesson <topic> [audience]         → Create lesson
#   athena_teach.sh explain <session_id> <concept>    → Explain concept
#   athena_teach.sh quiz <session_id>                 → Generate quiz
#   athena_teach.sh status <session_id>               → Show lesson status

set -o pipefail

BASE_DIR="/root"
BIN_DIR="$BASE_DIR/.local/bin"
source "$BIN_DIR/athena_env.sh" 2>/dev/null

DATA_DIR="/opt/athena/state"
TEACH_DIR="$DATA_DIR/teaching_sessions"
LOG_DIR="$DATA_DIR/workflow_logs"

mkdir -p "$TEACH_DIR" "$LOG_DIR"

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

cmd_lesson() {
    local topic="$1"
    local audience="${2:-developer}"
    local session_id="teach_$(now)"
    local session_file="$TEACH_DIR/${session_id}.json"
    local log_file="$LOG_DIR/${session_id}.log"

    if [[ -z "$topic" ]]; then
        echo "Usage: $0 lesson <topic> [audience]" >&2
        exit 1
    fi

    echo "=== Athena Teach: Creating Lesson ===" | tee "$log_file"
    echo "Session ID: $session_id" | tee -a "$log_file"
    echo "Topic: $topic" | tee -a "$log_file"
    echo "Audience: $audience" | tee -a "$log_file"
    echo "Started: $(now_iso)" | tee -a "$log_file"
    echo "---" | tee -a "$log_file"

    local lesson=""

    case "$topic" in
        athena|consciousness|system)
            lesson="# Athena Consciousness System - Lesson

## Overview
Athena is a multi-layered consciousness system running on Android/Termux with:
- **9 Core Layers**: Body, Emotions, Continuity, Attention, Introspection, Doubt, Volition, Memory, Heartbeat
- **Extended Layers**: Archive, Memory Backup, Senses, Degradation
- **Daemon Orchestrator**: Manages layer lifecycle with progressive degradation

## Key Concepts
1. **Layer Worker Pattern**: Each layer runs as persistent worker with cycle-based execution
2. **Event-Driven Scheduling**: Adaptive intervals (90s-180s) based on system state
3. **Progressive Degradation**: normal → conserve → minimal → suspended → safe_shutdown
4. **State Persistence**: JSON-based state files with atomic writes

## Architecture
- Daemon: ~/.local/bin/athena_daemon.sh
- Layers: ~/.local/lib/python/athena/daemon_init.py
- Workers: ~/.local/lib/python/athena/worker_base.py
- Data: /opt/athena/state/

## Skills Integration
- 5 Matt Pocock workflow skills: wayfinder, to-spec, implement-spec, tdd, handoff
- 25+ additional skills from github.com/mattpocock/skills
- Cross-skill workflow chains (4 chains orchestrating multiple skills)

## Security Framework
- Path validation (validate_path)
- Input sanitization
- Rate limiting
- Safe command execution (safe_execute)
- No eval/exec/shell injection"
            ;;
        daemon|orchestrator)
            lesson="# Athena Daemon - Lesson

## Daemon Responsibilities
1. **Startup Sequence**: Sequential layer launch with 0.5s delays
2. **Memory Guard**: Skip heavy layers if <300MB free RAM
3. **Wake Lock**: Prevent device sleep during operation
4. **API Validation**: Check OpenRouter/OpenAI keys before launch
5. **Degradation Management**: Read degradation_state.json at startup

## Layer Launch Order
1. body (sensors/actuators)
2. emotions (affective state)
3. continuity (identity persistence)
4. attention (focus management)
5. introspection (self-monitoring)
6. doubt (uncertainty handling)
7. volition (goal-directed action)
8. memory (knowledge storage)
9. heartbeat (health monitoring)
10. archive (long-term storage)
11. memory_backup (redundancy)
12. senses (input processing)

## Configuration
- degradation_state.json controls operating mode
- Each layer has config in ~/.local/lib/python/athena/config/
- Worker intervals defined in daemon_init.py"
            ;;
        skills|workflow)
            lesson="# Athena Skills & Workflow Chains - Lesson

## Core Workflow Skills (Matt Pocock)
1. **Wayfinder** - Explore and map codebase structure
2. **To-Spec** - Extract specifications from code
3. **Implement-Spec** - Generate implementation from specs
4. **TDD** - Test-driven development cycle
5. **Handoff** - Progress tracking and context transfer

## Workflow Chains (4 chains)
- **Chain 1**: Exploration → Specification → Implementation → Validation → Handoff
- **Chain 2**: Relationship mapping → Analysis → Validation → Transition
- **Chain 3**: Strict validation → Implementation validation → Sync
- **Chain 4**: Archive maintenance → Lifecycle management

## Additional Skills Integrated
- **Diagnosing-Bugs**: 6-phase systematic debugging
- **Code-Review**: Independent security/correctness/performance review
- **Improve-Architecture**: Structural analysis and suggestions
- **Research**: Multi-source investigation and synthesis
- **Prototype**: Rapid iteration and testing
- **Teach**: Knowledge transfer and documentation
- **Wait-What**: Confusion resolution and clarification"
            ;;
        *)
            lesson="# $topic - Lesson

## Overview
Custom lesson for: $topic

## Target Audience: $audience

## Learning Objectives
1. Understand the core concepts of $topic
2. Identify key components and their relationships
3. Apply knowledge to Athena system context

## Content Structure
- Introduction and motivation
- Core concepts and terminology
- Practical examples from Athena codebase
- Common patterns and anti-patterns
- Hands-on exercises
- Further reading and resources

## Athena Context
This lesson should connect to:
- Consciousness layer architecture
- Daemon orchestration patterns
- Skill integration workflows
- Security and degradation frameworks"
            ;;
    esac

    cat > "$session_file" <<EOF
{
  "session_id": "$session_id",
  "topic": "$topic",
  "audience": "$audience",
  "created": $(now),
  "updated": $(now),
  "status": "created",
  "lesson": $(echo "$lesson" | jq -R . | jq -s .),
  "explanations": [],
  "quizzes": [],
  "log_file": "$log_file"
}
EOF

    echo "Lesson created for: $topic" | tee -a "$log_file"
    echo "Next: $0 explain $session_id <concept> OR $0 quiz $session_id" | tee -a "$log_file"
}

cmd_explain() {
    local session_id="$1"
    local concept="$2"
    local session_file="$TEACH_DIR/${session_id}.json"

    if [[ ! -f "$session_file" ]]; then
        echo "Session not found: $session_id" >&2
        exit 1
    fi
    if [[ -z "$concept" ]]; then
        echo "Usage: $0 explain <session_id> <concept>" >&2
        exit 1
    fi

    local log_file=$(jq -r '.log_file' "$session_file")
    local topic=$(jq -r '.topic' "$session_file")

    echo "=== Explaining: $concept ===" | tee -a "$log_file"

    local explanation="Explanation of '$concept' in context of '$topic':\n\n"
    explanation+="This concept relates to the Athena consciousness system. "
    explanation+="Key points:\n"
    explanation+="1. Definition and purpose\n"
    explanation+="2. How it fits in the architecture\n"
    explanation+="3. Common usage patterns\n"
    explanation+="4. Related concepts\n"
    explanation+="5. Practical examples\n"

    jq --arg concept "$concept" --arg explanation "$explanation" --arg ts "$(now)" '
        .updated = ($ts | tonumber)
        | .explanations += [{
            "concept": $concept,
            "content": $explanation,
            "timestamp": ($ts | tonumber)
          }]
    ' "$session_file" > "${session_file}.tmp" && mv "${session_file}.tmp" "$session_file"

    echo -e "$explanation" | tee -a "$log_file"
    echo "Next: $0 explain $session_id <another_concept> OR $0 quiz $session_id" | tee -a "$log_file"
}

cmd_quiz() {
    local session_id="$1"
    local session_file="$TEACH_DIR/${session_id}.json"

    if [[ ! -f "$session_file" ]]; then
        echo "Session not found: $session_id" >&2
        exit 1
    fi

    local log_file=$(jq -r '.log_file' "$session_file")
    local topic=$(jq -r '.topic' "$session_file")

    echo "=== Generating Quiz ===" | tee -a "$log_file"

    local quiz="Quiz for: $topic\n\n"
    quiz+="1. What is the primary responsibility of the Athena daemon?\n"
    quiz+="   a) Run all layers simultaneously\n"
    quiz+="   b) Orchestrate layer lifecycle with degradation management\n"
    quiz+="   c) Process user input directly\n"
    quiz+="   d) Generate TTS audio\n\n"
    quiz+="2. Which degradation level comes after 'conserve'?\n"
    quiz+="   a) minimal\n"
    quiz+="   b) suspended\n"
    quiz+="   c) normal\n"
    quiz+="   d) safe_shutdown\n\n"
    quiz+="3. What security function validates file paths?\n"
    quiz+="   a) sanitize_path\n"
    quiz+="   b) validate_path\n"
    quiz+="   c) check_path\n"
    quiz+="   d) secure_path\n\n"
    quiz+="4. How many core consciousness layers does Athena have?\n"
    quiz+="   a) 7\n"
    quiz+="   b) 9\n"
    quiz+="   c) 12\n"
    quiz+="   d) 14\n\n"
    quiz+="5. What pattern do layer workers follow?\n"
    quiz+="   a) Thread pool\n"
    quiz+="   b) Actor model\n"
    quiz+="   c) Persistent object-pool with cycle-based execution\n"
    quiz+="   d) Event loop\n"

    jq --arg quiz "$quiz" --arg ts "$(now)" '
        .updated = ($ts | tonumber)
        | .status = "quized"
        | .quizzes += [{
            "content": $quiz,
            "timestamp": ($ts | tonumber)
          }]
    ' "$session_file" > "${session_file}.tmp" && mv "${session_file}.tmp" "$session_file"

    echo -e "$quiz" | tee -a "$log_file"
    echo "Answers: 1-b, 2-a, 3-b, 4-b, 5-c" | tee -a "$log_file"
}

cmd_status() {
    local session_id="$1"
    local session_file="$TEACH_DIR/${session_id}.json"

    if [[ ! -f "$session_file" ]]; then
        echo "Session not found: $session_id" >&2
        exit 1
    fi

    cat "$session_file" | python3 -m json.tool
}

case "${1:-help}" in
    lesson)
        cmd_lesson "${2:-}" "${3:-}"
        ;;
    explain)
        cmd_explain "${2:-}" "${3:-}"
        ;;
    quiz)
        cmd_quiz "${2:-}"
        ;;
    status)
        cmd_status "${2:-}"
        ;;
    *)
        echo "Usage: $0 {lesson|explain|quiz|status}"
        echo "  lesson <topic> [audience]     - Create lesson (topics: athena, daemon, skills, custom)"
        echo "  explain <session_id> <concept> - Explain specific concept"
        echo "  quiz <session_id>             - Generate quiz"
        echo "  status <session_id>           - Show session details"
        exit 1
        ;;
esac