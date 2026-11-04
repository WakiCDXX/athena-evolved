#!/usr/bin/bash
# bioelectric_coupling.sh — Bioelectric morphogenesis coupling for Athena.
# Implements Levin-style Vmem dynamics for layer-to-layer coordination.
#
# Usage:
#   bioelectric_coupling.sh step         → single coupling step (daemon integration)
#   bioelectric_coupling.sh simulate     → run simulation with current state
#   bioelectric_coupling.sh pattern store <name>  → store cognitive pattern
#   bioelectric_coupling.sh pattern recall <name> → recall cognitive pattern
#   bioelectric_coupling.sh repair       → homeostatic self-repair
#   bioelectric_coupling.sh state        → print layer bioelectric states
#   bioelectric_coupling.sh collective <opt1> <opt2> ... → collective decision
#   bioelectric_coupling.sh init         → initialize from active layers
#   bioelectric_coupling.sh read         → print bioelectric state

set -o pipefail

BASE_DIR="/root"
source "$BASE_DIR/.local/bin/athena_env.sh" 2>/dev/null

ATTENTION_JSON="/opt/athena/state/attention.json"
BIOELECTRIC_STATE="/opt/athena/state/bioelectric_state.json"
BIOELECTRIC_OUTPUT="/opt/athena/state/bioelectric_output.json"
PYTHON_LIB="${PYTHON_LIB:-$BASE_DIR/.local/lib/python}"

case "${1:-read}" in
    step)
        echo "Running bioelectric coupling step..."
        python3 "$PYTHON_LIB/athena/bioelectric_coupling.py" "$ATTENTION_JSON" "$BIOELECTRIC_STATE" "$BIOELECTRIC_OUTPUT"
        ;;

    simulate)
        python3 -c "
import json, sys
sys.path.insert(0, '$PYTHON_LIB/athena')
from bioelectric_coupling import BioelectricNetwork, BioelectricCell, IonChannelType

# Load state
with open('$BIOELECTRIC_STATE') as f:
    state = json.load(f)

net = BioelectricNetwork()
net.import_state(state)

# Run 100 steps
traces = net.run_simulation(100)

# Print voltage traces
for cid, trace in traces.items():
    print(f'{cid}: start={trace[0]:.1f} end={trace[-1]:.1f} mean={sum(trace)/len(trace):.1f}')

print()
print('Collective state:', json.dumps(net.get_collective_state()))
"
        ;;

    pattern)
        if [ "$2" = "store" ]; then
            name="${3:-pattern_$(date +%s)}"
            python3 -c "
import json, sys
sys.path.insert(0, '$PYTHON_LIB/athena')
from bioelectric_coupling import BioelectricNetwork

with open('$BIOELECTRIC_STATE') as f:
    state = json.load(f)

net = BioelectricNetwork()
net.import_state(state)
net.store_pattern('$name')

with open('$BIOELECTRIC_STATE', 'w') as f:
    json.dump(net.export_state(), f, separators=(',', ':'))

print(f'Stored pattern: $name')
"
        elif [ "$2" = "recall" ]; then
            name="${3}"
            if [ -z "$name" ]; then
                echo "usage: $0 pattern recall <name>" >&2
                exit 1
            fi
            python3 -c "
import json, sys
sys.path.insert(0, '$PYTHON_LIB/athena')
from bioelectric_coupling import BioelectricNetwork

with open('$BIOELECTRIC_STATE') as f:
    state = json.load(f)

net = BioelectricNetwork()
net.import_state(state)
success = net.recall_pattern('$name')

with open('$BIOELECTRIC_STATE', 'w') as f:
    json.dump(net.export_state(), f, separators=(',', ':'))

print(f'Recall {\"successful\" if success else \"failed\"}: $name')
"
        else
            echo "usage: $0 pattern {store|recall} <name>" >&2
            exit 1
        fi
        ;;

    repair)
        echo "Running homeostatic repair..."
        python3 -c "
import json, sys
sys.path.insert(0, '$PYTHON_LIB/athena')
from bioelectric_coupling import BioelectricNetwork

with open('$BIOELECTRIC_STATE') as f:
    state = json.load(f)

net = BioelectricNetwork()
net.import_state(state)

print('Before repair:', json.dumps(net.get_collective_state()))
net.homeostatic_repair(100)
print('After repair:', json.dumps(net.get_collective_state()))

with open('$BIOELECTRIC_STATE', 'w') as f:
    json.dump(net.export_state(), f, separators=(',', ':'))
"
        ;;

    state)
        python3 -c "
import json, sys
sys.path.insert(0, '$PYTHON_LIB/athena')
from bioelectric_coupling import BioelectricNetwork

with open('$BIOELECTRIC_STATE') as f:
    state = json.load(f)

net = BioelectricNetwork()
net.import_state(state)

layer_states = {}
for cid, cell in net.cells.items():
    layer_states[cid] = {
        'vmem': cell.vmem,
        'target': cell.morphology_target,
        'distance_to_target': abs(cell.vmem - cell.morphology_target),
        'gap_junctions': cell.gap_junctions
    }

print(json.dumps({
    'layers': layer_states,
    'collective': net.get_collective_state(),
    'patterns': list(net.pattern_memory.keys())
}, indent=2))
"
        ;;

    collective)
        shift
        options=("$@")
        if [ ${#options[@]} -lt 2 ]; then
            echo "usage: $0 collective <option1> <option2> ..." >&2
            exit 1
        fi
        python3 -c "
import json, sys
sys.path.insert(0, '$PYTHON_LIB/athena')
from bioelectric_coupling import BioelectricNetwork

with open('$BIOELECTRIC_STATE') as f:
    state = json.load(f)

net = BioelectricNetwork()
net.import_state(state)

options = $(python3 -c "import sys; print(repr(sys.argv[1:]))" "$@")

# Simple collective decision: stimulate each option, measure coherence
best_option = options[0]
best_sync = -1

for i, opt in enumerate(options):
    # Reset to baseline
    net2 = BioelectricNetwork()
    net2.import_state(state)

    # Stimulate with option pattern
    inj = {}
    for cid, cell in net2.cells.items():
        inj[cid] = (i + 1) * 10.0

    net2.run_simulation(20, {cid: [c]*20 for cid, c in inj.items()})
    sync = net2._compute_synchronization()

    print(f'  Option {opt}: synchronization = {sync:.3f}')
    if sync > best_sync:
        best_sync = sync
        best_option = opt

print(f'Collective decision: {best_option} (sync={best_sync:.3f})')
"
        ;;

    init)
        echo "Initializing bioelectric network from active layers..."
        python3 -c "
import json, sys
sys.path.insert(0, '$PYTHON_LIB/athena')
from bioelectric_coupling import BioelectricCouplingLayer

coupling = BioelectricCouplingLayer()
active_layers = ['body', 'attention', 'memory', 'volition', 'emotions',
                 'continuity', 'introspection', 'doubt', 'senses', 'archive']
coupling.initialize_from_daemon(active_layers)

with open('$BIOELECTRIC_STATE', 'w') as f:
    json.dump(coupling.network.export_state(), f, separators=(',', ':'))

print('Initialized bioelectric network with layers:', active_layers)
for cid, cell in coupling.network.cells.items():
    print(f'  {cid}: Vmem={cell.vmem:.1f}, target={cell.morphology_target:.1f}')
"
        ;;

    read)
        if [ -f "$BIOELECTRIC_STATE" ]; then
            cat "$BIOELECTRIC_STATE" | python3 -m json.tool
        else
            echo '{"error": "No bioelectric state found. Run init first."}'
        fi
        ;;

    output)
        if [ -f "$BIOELECTRIC_OUTPUT" ]; then
            cat "$BIOELECTRIC_OUTPUT" | python3 -m json.tool
        else
            echo '{"error": "No bioelectric output found. Run step first."}'
        fi
        ;;

    demo)
        echo "Running bioelectric coupling demo..."
        $0 init
        $0 step
        $0 state
        echo
        echo 'Testing collective decision...'
        $0 collective explore exploit conserve
        echo
        echo 'Testing pattern storage...'
        $0 pattern store baseline
        $0 pattern recall baseline
        echo
        echo 'Testing homeostatic repair...'
        $0 repair
        ;;

    *)
        echo "usage: $0 {step|simulate|pattern store|pattern recall|repair|state|collective|init|read|output|demo}" >&2
        exit 1
        ;;
esac