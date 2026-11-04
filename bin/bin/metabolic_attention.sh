#!/usr/bin/bash
# metabolic_attention.sh — Metabolic Mode Switching for Attention.
# Alien Chemistry analogue: Pluggable metabolic pathways (Calvin, reductive TCA,
# Wood-Ljungdahl, CETCH) for adaptive attention processing.
#
# Usage:
#   metabolic_attention.sh status           → show current metabolic state
#   metabolic_attention.sh process [substrates...] → process through current mode
#   metabolic_attention.sh switch <mode>    → force switch mode (calvin|reductive_tca|wood_ljungdahl|cetch|hybrid)
#   metabolic_attention.sh demo             → run demonstration
#   metabolic_attention.sh read             → print metabolic state

set -o pipefail

BASE_DIR="/root"
source "$BASE_DIR/.local/bin/athena_env.sh" 2>/dev/null

METABOLIC_STATE="/opt/athena/state/metabolic_attention.json"
PYTHON_LIB="${PYTHON_LIB:-$BASE_DIR/.local/lib/python}"

case "${1:-read}" in
    status)
        python3 -c "
import json, sys
sys.path.insert(0, '$PYTHON_LIB/athena')
from metabolic_attention import MetabolicAttention, metabolic_attention_query

result = metabolic_attention_query('$METABOLIC_STATE', {'type': 'status'})
print(json.dumps(result, indent=2))
"
        ;;

    process)
        shift
        substrates=("$@")
        if [ ${#substrates[@]} -eq 0 ]; then
            substrates=("raw_sensory")
        fi
        # Convert bash array to JSON
        substrates_json=$(printf '%s\n' "${substrates[@]}" | python3 -c "import sys, json; print(json.dumps([line.strip() for line in sys.stdin]))")

        # Build context from env or defaults
        task_type="${METABOLIC_TASK_TYPE:-routine}"
        urgency="${METABOLIC_URGENCY:-normal}"
        cpu_pressure="${METABOLIC_CPU_PRESSURE:-0.0}"

        python3 -c "
import json, sys
sys.path.insert(0, '$PYTHON_LIB/athena')
from metabolic_attention import metabolic_attention_query

substrates = json.loads('''$substrates_json''')
context = {
    'task_type': '$task_type',
    'urgency': '$urgency',
    'cpu_pressure': $cpu_pressure
}

result = metabolic_attention_query('$METABOLIC_STATE', {
    'type': 'process',
    'substrates': substrates,
    'context': context
})
print(json.dumps(result, indent=2))
"
        ;;

    switch)
        if [ -z "$2" ]; then
            echo "usage: \$0 switch <mode> [reason]" >&2
            echo "modes: calvin, reductive_tca, wood_ljungdahl, cetch, hybrid" >&2
            exit 1
        fi
        mode="$2"
        reason="${3:-manual}"

        python3 -c "
import json, sys
sys.path.insert(0, '$PYTHON_LIB/athena')
from metabolic_attention import metabolic_attention_query

result = metabolic_attention_query('$METABOLIC_STATE', {
    'type': 'switch',
    'mode': '$mode',
    'reason': '$reason'
})
print(json.dumps(result, indent=2))
"
        ;;

    demo)
        echo "Running Metabolic Attention demo..."
        python3 "$PYTHON_LIB/athena/metabolic_attention.py" demo
        ;;

    read)
        if [ -f "$METABOLIC_STATE" ]; then
            cat "$METABOLIC_STATE" | python3 -m json.tool
        else
            echo '{"error": "No metabolic state found. Run demo or process first."}'
        fi
        ;;

    *)
        echo "usage: \$0 {status|process [substrates...]|switch <mode> [reason]|demo|read}" >&2
        exit 1
        ;;
esac