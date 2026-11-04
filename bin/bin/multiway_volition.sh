#!/usr/bin/bash
# multiway_volition.sh — Multiway volition with causal invariance for Athena.
# Wolfram Physics Project inspired: branchial space, causal graphs, multiway evolution.
#
# Usage:
#   multiway_volition.sh step         → single volition step (daemon integration)
#   multiway_volition.sh evolve [n]   → evolve multiway system n steps
#   multiway_volition.sh decide       → extract decision from current state
#   multiway_volition.sh invariance   → check causal invariance
#   multiway_volition.sh branchial    → show branchial clusters
#   multiway_volition.sh causal       → print causal graph
#   multiway_volition.sh init         → initialize from volition input
#   multiway_volition.sh read         → print multiway state

set -o pipefail

BASE_DIR="/root"
source "$BASE_DIR/.local/bin/athena_env.sh" 2>/dev/null

VOLITION_INPUT="/opt/athena/state/volition_input.json"
MULTIWAY_STATE="/opt/athena/state/multiway_state.json"
MULTIWAY_OUTPUT="/opt/athena/state/multiway_output.json"
PYTHON_LIB="${PYTHON_LIB:-$BASE_DIR/.local/lib/python}"

case "${1:-read}" in
    step)
        echo "Running multiway volition step..."
        python3 "$PYTHON_LIB/athena/multiway_volition.py" "$VOLITION_INPUT" "$MULTIWAY_STATE" "$MULTIWAY_OUTPUT"
        ;;

    evolve)
        steps="${2:-10}"
        python3 -c "
import json, sys
sys.path.insert(0, '$PYTHON_LIB/athena')
from multiway_volition import MultiwayVolitionSystem

with open('$MULTIWAY_STATE') as f:
    state = json.load(f)

mws = MultiwayVolitionSystem()
mws.import_state(state)

result = mws.evolve($steps)
print(json.dumps(result, indent=2))

with open('$MULTIWAY_STATE', 'w') as f:
    json.dump(mws.export_state(), f, separators=(',', ':'))
"
        ;;

    decide)
        python3 -c "
import json, sys
sys.path.insert(0, '$PYTHON_LIB/athena')
from multiway_volition import MultiwayVolitionSystem

with open('$MULTIWAY_STATE') as f:
    state = json.load(f)

mws = MultiwayVolitionSystem()
mws.import_state(state)

decision = mws.extract_decision('consensus')
print(json.dumps(decision, indent=2))
"
        ;;

    invariance)
        python3 -c "
import json, sys
sys.path.insert(0, '$PYTHON_LIB/athena')
from multiway_volition import MultiwayVolitionSystem

with open('$MULTIWAY_STATE') as f:
    state = json.load(f)

mws = MultiwayVolitionSystem()
mws.import_state(state)

result = mws.check_causal_invariance()
print(json.dumps(result, indent=2))
"
        ;;

    branchial)
        python3 -c "
import json, sys
sys.path.insert(0, '$PYTHON_LIB/athena')
from multiway_volition import MultiwayVolitionSystem

with open('$MULTIWAY_STATE') as f:
    state = json.load(f)

mws = MultiwayVolitionSystem()
mws.import_state(state)

clusters = mws.get_branchial_clusters(0.5)
print(json.dumps({
    'num_clusters': len(clusters),
    'clusters': [{'size': len(c), 'states': c[:5]} for c in clusters]
}, indent=2))
"
        ;;

    causal)
        python3 -c "
import json, sys
sys.path.insert(0, '$PYTHON_LIB/athena')
from multiway_volition import MultiwayVolitionSystem

with open('$MULTIWAY_STATE') as f:
    state = json.load(f)

mws = MultiwayVolitionSystem()
mws.import_state(state)

graph = mws.get_causal_graph()
print(json.dumps({
    'nodes': len(graph['nodes']),
    'edges': len(graph['edges']),
    'sample_nodes': graph['nodes'][:5]
}, indent=2))
"
        ;;

    init)
        echo "Initializing multiway volition system..."
        # Create default volition input if not exists
        if [ ! -f "$VOLITION_INPUT" ]; then
            python3 -c "
import json
data = {
    'goals': ['understand_consciousness', 'optimize_resources'],
    'context': {'battery': 0.8, 'thermal': 0.3, 'load': 0.5},
    'observation_targets': ['attention_state', 'memory_pressure', 'system_health'],
    'attention_candidates': ['research', 'maintenance', 'idle'],
    'decision_options': ['continue_research', 'run_maintenance', 'enter_idle'],
    'simulation_scenarios': ['high_load', 'low_battery', 'thermal_throttle'],
    'hypothesis_space': 5
}
with open('$VOLITION_INPUT', 'w') as f:
    json.dump(data, f)
print('Created volition_input.json')
"
        fi
        python3 -c "
import json, sys
sys.path.insert(0, '$PYTHON_LIB/athena')
from multiway_volition import MultiwayVolitionSystem

with open('$VOLITION_INPUT') as f:
    volition_input = json.load(f)

mws = MultiwayVolitionSystem()
initial_payload = {
    'goals': volition_input.get('goals', []),
    'context': volition_input.get('context', {}),
    'observation_targets': volition_input.get('observation_targets', []),
    'attention_candidates': volition_input.get('attention_candidates', []),
    'decision_options': volition_input.get('decision_options', []),
    'simulation_scenarios': volition_input.get('simulation_scenarios', []),
    'hypothesis_space': volition_input.get('hypothesis_space', 5)
}
mws.initialize(initial_payload)

with open('$MULTIWAY_STATE', 'w') as f:
    json.dump(mws.export_state(), f, separators=(',', ':'))

print('Initialized multiway volition system')
print('Frontier:', mws.current_frontier)
"
        ;;

    read)
        if [ -f "$MULTIWAY_STATE" ]; then
            cat "$MULTIWAY_STATE" | python3 -m json.tool
        else
            echo '{"error": "No multiway state found. Run init first."}'
        fi
        ;;

    output)
        if [ -f "$MULTIWAY_OUTPUT" ]; then
            cat "$MULTIWAY_OUTPUT" | python3 -m json.tool
        else
            echo '{"error": "No multiway output found. Run step first."}'
        fi
        ;;

    demo)
        echo "Running multiway volition demo..."
        $0 init
        $0 step
        $0 decide
        $0 invariance
        $0 branchial
        $0 causal
        ;;

    *)
        echo "usage: $0 {step|evolve [n]|decide|invariance|branchial|causal|init|read|output|demo}" >&2
        exit 1
        ;;
esac