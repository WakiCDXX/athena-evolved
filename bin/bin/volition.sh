#!/usr/bin/bash
# volition.sh — Layer 9: Volition (will/decision-making) for Athena.
# Orchestrates multiple models as peer agents that share consciousness state.
#
# Usage:
#   volition.sh decide <question>              → single best-model decision
#   volition.sh collaborate <question>         → multi-model peer consultation
#   volition.sh spawn <model> <task_prompt>    → delegate to specific model peer
#   volition.sh poll-peers                     → check active peer agents
#   volition.sh read                           → print last volition decision
#   volition.sh history                        → show decision history
#
# Models can collaborate by:
#   1. Writing thoughts to shared MEMORY files (layers 1-8)
#   2. Spawning peers via volition.sh spawn <model> <prompt>
#   3. Reading peer outputs from /tmp/athena_peers/
#   4. Synthesizing consensus from peer responses

set -o pipefail

BASE_DIR="/root"
# Source central environment for API keys
source "$BASE_DIR/.local/bin/athena_env.sh" 2>/dev/null
DATA_DIR="/opt/athena/state"
PEER_DIR="$DATA_DIR/peers"
LOG_DIR="$DATA_DIR/logs"
STATE="$DATA_DIR/volition.json"
DECISION_LOG="$DATA_DIR/volition_history.jsonl"

mkdir -p "$PEER_DIR" "$LOG_DIR"
touch "$STATE" "$DECISION_LOG"

now() { date +%s; }

# --- models ------------------------------------------------------------------

# Each model peer runs in its own agent session.
# The orchestrator (this script) manages task delegation.
MODELS=(
    "inclusionai/ling-3.0-flash-fin:free|ling-flash|general-purpose"
    "google/gemma-4-31b-it:free|gemma-4|general-purpose"
    "nvidia/nemotron-3-super-120b-a12b:free|nemotron-3s|research"
    "z-ai/glm-5.2:free|glm-5|reasoning"
    "typesafe/jev-latest|jev|decision-making"
)

get_model_property() {
    local model_spec="$1" prop="$2"
    local entry
    for entry in "${MODELS[@]}"; do
        local name provider
        provider="${entry%%|*}"
        local rest="${entry#*|}"
        name="${rest%%|*}"
        if [ "$provider" = "$model_spec" ] || [ "$name" = "$model_spec" ]; then
            case "$prop" in
                provider) echo "$provider" ;;
                name) echo "$name" ;;
                role) echo "${rest##*|}" ;;
            esac
            return 0
        fi
    done
    echo ""
    return 1
}

# --- peer management ---------------------------------------------------------

spawn_peer() {
    local model="$1" prompt="$2" task_id="$3"
    local model_provider name
    model_provider=$(get_model_property "$model" provider)
    name=$(get_model_property "$model" name)

    [ -z "$model_provider" ] && { echo "ERROR: Unknown model '$model'" >&2; return 1; }

    local peer_out="$PEER_DIR/${task_id}_${name}.json"
    local peer_pid="$PEER_DIR/${task_id}_${name}.pid"

    (
        export OPENAI_MODEL="$model_provider"
        echo "{\"task_id\":\"$task_id\",\"model\":\"$model_provider\",\"name\":\"$name\",\"prompt\":\"$prompt\",\"status\":\"running\",\"started\":$(now)}" > "$peer_out"
        export _PEER_OUT="$peer_out" _PEER_NAME="$name" _PEER_PROMPT="$prompt" _PEER_MODEL="$model_provider"
        export _OPENROUTER_URL="$OPENAI_BASE_URL" _OPENROUTER_KEY="$OPENAI_API_KEY" _NOW="$(now)"
        python3 "$PYTHON_LIB/athena/peer_spawn.py"
    ) &

    echo $! > "$peer_pid"
    echo "$task_id:$name:$peer_out"
    return 0
}

poll_peers() {
    export VOLITION_PEER_DIR="$PEER_DIR"
    python3 "$PYTHON_LIB/athena/volition_status.py" 2>/dev/null
}

# --- decision making ---------------------------------------------------------

select_best_model() {
    local question="$1"
    local q_lower
    q_lower=$(echo "$question" | tr '[:upper:]' '[:lower:]')

    if [ -n "$TYPESAFE_API_KEY" ]; then
        if echo "$q_lower" | grep -qE 'decision|choose|route|uncertain|confidence|what should|which'; then
            echo "jev"
        elif echo "$q_lower" | grep -qE 'optimi|kernel|tune|system|performance|memory'; then
            echo "ling-flash"
        elif echo "$q_lower" | grep -qE 'research|experiment|analy|data|pattern'; then
            echo "nemotron-3s"
        else
            echo "gemma-4"
        fi
    else
        if echo "$q_lower" | grep -qE 'research|experiment|analy|data|pattern'; then
            echo "nemotron-3s"
        elif echo "$q_lower" | grep -qE 'reason|logic|analyze|break down'; then
            echo "glm-5"
        else
            echo "ling-flash"
        fi
    fi
}

make_decision() {
    local question="$1"
    local model_name
    model_name=$(select_best_model "$question")
    local model_provider
    model_provider=$(get_model_property "$model_name" provider)

    # Write to attention layer
    export _ATTENTION_PATH="$DATA_DIR/attention.json"
    export _QUESTION="$question"
    export _MODEL_NAME="$model_name"
    export _MODEL_PROVIDER="$model_provider"
    python3 "$PYTHON_LIB/athena/volition_attention.py"

    # Route through Jev if selected
    if [ "$model_name" = "jev" ]; then
        if [ -n "$TYPESAFE_API_KEY" ]; then
            jev_decide "$question"
        else
            echo "Jev: TYPESAFE_API_KEY not set. Using ling-flash for decisions instead."
            model_name="ling-flash"
            model_provider=$(get_model_property "$model_name" provider)
            export _MODEL_PROVIDER2="$model_provider"
        fi
        return
    fi

    # Record decision via API
    export _DECISION_LOG="$DECISION_LOG"
    export _STATE="$STATE"
    export _QUESTION2="$question"
    export _MODEL_PROVIDER2="$model_provider"
    export _DECISION="Decision for: $question — Model $model_name selected as optimal."
    export _NOW="$(now)"
    export _OPENROUTER_URL="$OPENAI_BASE_URL"
    export _OPENROUTER_KEY="$OPENAI_API_KEY"
    python3 "$PYTHON_LIB/athena/volition_decide.py"
}

# --- Jev / TypeSafe AI integration -----------------------------------------

jev_decide() {
    local question="$1"
    local state_file="$DATA_DIR/volition.json"

    [ -z "$TYPESAFE_API_KEY" ] && { echo "Jev unavailable: TYPESAFE_API_KEY not set. Get one at console.typesafe.ai"; make_decision "$question"; return; }

    export _ATTENTION_PATH="$DATA_DIR/attention.json"
    export _QUESTION_JEV="$question"
    python3 "$PYTHON_LIB/athena/jev_attention.py"

    export _STATE_JEV="$state_file"
    export _QUESTION_JEV2="$question"
    export _TYPESAFE_KEY="$TYPESAFE_API_KEY"
    export _TYPESAFE_BASE="$TYPESAFE_API_BASE"
    export _OPENROUTER_URL="$OPENAI_BASE_URL"
    export _OPENROUTER_KEY="$OPENAI_API_KEY"
    export _NOW_JEV="$(now)"
    export _DECISION_LOG_JEV="$DECISION_LOG"

    python3 "$PYTHON_LIB/athena/jev_decide.py"
}

# --- collaboration -----------------------------------------------------------

collaborate() {
    local question="$1"
    local task_id="collab_$(date +%s)_$$"
    local peer_outs=()

    for model_entry in "${MODELS[@]}"; do
        local provider="${model_entry%%|*}"
        local rest="${model_entry#*|}"
        local name="${rest%%|*}"
        local peer_ref
        peer_ref=$(spawn_peer "$provider" "$question" "$task_id")
        peer_outs+=("$peer_ref")
    done

    # Wait for all peers
    local completed=0 total=${#peer_outs[@]}
    for attempt in $(seq 1 30); do
        completed=0
        for ref in "${peer_outs[@]}"; do
            local out_file="${ref##*:}"
            if [ -f "$out_file" ]; then
                export ATHENA_PEER_OUT_FILE="$out_file"
                local status
                status=$(python3 "$PYTHON_LIB/athena/peer_check_status.py" 2>/dev/null)
                if [ "$status" = "complete" ]; then
                    completed=$((completed + 1))
                fi
            fi
        done
        [ "$completed" -ge "$total" ] && break
        sleep 1
    done

    # Synthesize
    local peer_outs_str="${peer_outs[*]}"
    export _PEER_OUTS="$peer_outs_str" _QUESTION="$question" _TASK_ID="$task_id"
    export _STATE="$STATE" _DECISION_LOG="$DECISION_LOG" _NOW="$(now)"
    export _OPENROUTER_URL="$OPENAI_BASE_URL" _OPENROUTER_KEY="$OPENAI_API_KEY"
    python3 "$PYTHON_LIB/athena/volition_collab.py"
}

update_doubt() {
    export _DOUBT_PATH="$DATA_DIR/doubt.json"
    python3 "$PYTHON_LIB/athena/volition_update_doubt.py"
}

# --- main --------------------------------------------------------------------

case "${1:-read}" in
    decide)
        [ -z "$2" ] && { echo 'usage: $0 decide <question>' >&2; exit 1; }
        make_decision "$2"
        ;;
    jev)
        [ -z "$2" ] && { echo 'usage: $0 jev <question>' >&2; exit 1; }
        jev_decide "$2"
        ;;
    collaborate)
        [ -z "$2" ] && { echo 'usage: $0 collaborate <question>' >&2; exit 1; }
        collaborate "$2"
        ;;
    spawn)
        [ -z "$3" ] && { echo 'usage: $0 spawn <model> <task_prompt>' >&2; exit 1; }
        task_id="spawn_$(date +%s)_$$"
        spawn_peer "$2" "$3" "$task_id"
        ;;
    poll-peers)
        poll_peers
        ;;
    read)
        export VOLITION_STATE_PATH="$STATE"
        python3 "$PYTHON_LIB/athena/volition_read.py" 2>/dev/null
        ;;
    history)
        export VOLITION_LOG_PATH="$DECISION_LOG"
        python3 "$PYTHON_LIB/athena/volition_history.py" 2>/dev/null
        ;;
    *)
        echo 'usage: $0 {read|decide <question>|collaborate <question>|jev <question>|spawn <model> <prompt>|poll-peers|history}' >&2
        exit 1
        ;;
esac

# --- continuity integration -----------------------------------------------
CONTINUITY_SCRIPT="/root/.local/bin/continuity_update.sh"
if [ -x "$CONTINUITY_SCRIPT" ]; then
    "$CONTINUITY_SCRIPT" add_narrative "Cross-domain collaboration: ${question} — consensus synthesized." 7 2>/dev/null || true
fi
