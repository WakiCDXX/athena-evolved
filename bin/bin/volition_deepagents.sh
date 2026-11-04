#!/usr/bin/bash
# volition_deepagents.sh — DeepAgents-powered Volition Layer for Athena
# Replaces bash-based peer spawning with LangGraph-based agent orchestration

set -o pipefail

BASE_DIR="/root"
# Source central environment for API keys
source "$BASE_DIR/.local/bin/athena_env.sh" 2>/dev/null
DATA_DIR="/opt/athena/state"
PYTHON_LIB="$BASE_DIR/.local/lib/python"

mkdir -p "$DATA_DIR"

# Export for Python modules
export DATA_DIR="$DATA_DIR"
export PYTHONPATH="$PYTHON_LIB:$PYTHONPATH"
export SESSION_ID="${SESSION_ID:-session_$(date +%Y%m%d_%H%M%S)}"

usage() {
    cat <<'EOF'
Usage: volition_deepagents.sh <command> [args...]

Commands:
  decide <question>              → Single decision using DeepAgents
  collaborate <question>         → Multi-perspective collaboration via sub-agents
  hire <specialist> <question> <budget_cents>  → Hire external specialist via AgentBnB
  status                         → Show harness status and budget
  history                        → Show decision history
  budget <action> [amount]       → Budget management (query|reserve|spend|release)

Environment:
  DATA_DIR           → Athena data directory (default: /opt/athena/state)
  SESSION_ID         → Session identifier for LangGraph checkpointer
  OPENAI_API_KEY     → OpenRouter API key (from athena_env.sh)
  OPENAI_BASE_URL    → OpenRouter base URL (from athena_env.sh)
  TYPESAFE_API_KEY   → Jev/TypeSafe API key (optional)
EOF
}

# Check Python dependencies
check_deps() {
    python3 -c "import deepagents, langgraph, langchain_core" 2>/dev/null || {
        echo "ERROR: Missing Python dependencies. Install with:" >&2
        echo "  pip install deepagents==0.7.32 langgraph langchain-core langchain-openai" >&2
        return 1
    }
}

# Main commands
cmd_decide() {
    local question="$1"
    [ -z "$question" ] && { echo "Error: question required" >&2; usage; return 1; }

    check_deps || return 1

    python3 -c "
import asyncio, sys, os
sys.path.insert(0, '$PYTHON_LIB')
from athena.deepagents_harness import VolitionHarness

async def run():
    harness = VolitionHarness()
    result = await harness.decide('$question')
    import json
    print(json.dumps(result, indent=2))

asyncio.run(run())
"
}

cmd_collaborate() {
    local question="$1"
    [ -z "$question" ] && { echo "Error: question required" >&2; usage; return 1; }

    check_deps || return 1

    python3 -c "
import asyncio, sys, os
sys.path.insert(0, '$PYTHON_LIB')
from athena.deepagents_harness import VolitionHarness

async def run():
    harness = VolitionHarness()
    result = await harness.collaborate('$question')
    import json
    print(json.dumps(result, indent=2))

asyncio.run(run())
"
}

cmd_hire() {
    local specialist="$1"
    local question="$2"
    local budget="$3"

    [ -z "$specialist" ] || [ -z "$question" ] || [ -z "$budget" ] && {
        echo "Error: specialist, question, and budget_cents required" >&2
        usage
        return 1
    }

    check_deps || return 1

    python3 -c "
import asyncio, sys, os
sys.path.insert(0, '$PYTHON_LIB')
from athena.deepagents_harness import VolitionHarness, AgentHireRequest

async def run():
    harness = VolitionHarness()
    request = AgentHireRequest(
        specialist_type='$specialist',
        task_description='$question',
        max_budget_cents=$budget,
        required_capabilities=[],
        privacy_requirements=['data-minimization', 'no-training', 'session-isolation'],
        duration_estimate_seconds=3600
    )
    result = await harness.hire_specialist(request)
    import json
    print(json.dumps(result, indent=2))

asyncio.run(run())
"
}

cmd_status() {
    check_deps || return 1

    python3 -c "
import sys, os
sys.path.insert(0, '$PYTHON_LIB')
from athena.deepagents_harness import VolitionHarness

harness = VolitionHarness()
import json
print(json.dumps(harness.get_status(), indent=2))
"
}

cmd_history() {
    local history_file="$DATA_DIR/volition_history.jsonl"
    if [ -f "$history_file" ]; then
        tail -20 "$history_file" | python3 -c "
import sys, json
for line in sys.stdin:
    try:
        print(json.dumps(json.loads(line), indent=2))
    except:
        pass
"
    else
        echo "No history found"
    fi
}

cmd_budget() {
    local action="${1:-query}"
    local amount="${2:-0}"

    check_deps || return 1

    python3 -c "
import sys, os
sys.path.insert(0, '$PYTHON_LIB')
from athena.volition_budget import VolitionBudgetManager

config = {
    'daily_limit_cents': 2000,
    'monthly_limit_cents': 60000,
    'currency': 'USD',
    'alert_threshold': 0.7,
    'escrow_reserve_cents': 5000
}

manager = VolitionBudgetManager(config)

if '$action' == 'query':
    import json
    print(json.dumps(manager.get_status(), indent=2))
elif '$action' == 'reserve':
    print(json.dumps(manager.reserve($amount), indent=2))
elif '$action' == 'spend':
    print(json.dumps(manager.spend($amount, 'manual'), indent=2))
elif '$action' == 'release':
    print(json.dumps(manager.release_reserve($amount), indent=2))
else:
    print('Unknown action: $action')
    print('Actions: query, reserve, spend, release')
"
}

# Main dispatcher
case "${1:-help}" in
    decide)
        cmd_decide "$2"
        ;;
    collaborate)
        cmd_collaborate "$2"
        ;;
    hire)
        cmd_hire "$2" "$3" "$4"
        ;;
    status)
        cmd_status
        ;;
    history)
        cmd_history
        ;;
    budget)
        cmd_budget "$2" "$3"
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        echo "Unknown command: $1" >&2
        usage
        exit 1
        ;;
esac