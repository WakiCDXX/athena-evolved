#!/usr/bin/bash
# attention_tropical.sh — Tropical (min-plus) attention allocation for Athena.
# Replaces softmax with exact optimal allocation via tropical algebra.
#
# Usage:
#   attention_tropical.sh allocate    → compute tropical allocation
#   attention_tropical.sh steady      → compute steady-state pattern
#   attention_tropical.sh adapt       → adapt costs from feedback
#   attention_tropical.sh read        → print allocation result

set -o pipefail

BASE_DIR="/root"
source "$BASE_DIR/.local/bin/athena_env.sh" 2>/dev/null

STATE="/opt/athena/state/attention.json"
TROPICAL_STATE="/opt/athena/state/attention_tropical.json"

case "${1:-read}" in
    allocate)
        python3 "$PYTHON_LIB/athena/tropical_attention.py" "$STATE" "$TROPICAL_STATE"
        ;;

    steady)
        python3 -c "
import json, sys
sys.path.insert(0, '$PYTHON_LIB/athena')
from tropical_attention import TropicalAttention, TROPICAL_INF
import numpy as np

with open('$STATE') as f:
    state = json.load(f)

active = state.get('active_task')
bg = state.get('background', [])
concerns = state.get('concerns', [])

n_sources = 5
n_targets = 1 + len(bg) + len(concerns)
demands = np.full(n_targets, TROPICAL_INF)
if active:
    demands[0] = 1.0
for i in range(len(bg)):
    demands[1 + i] = 3.0
for i, c in enumerate(concerns):
    if ':' in c:
        name, lvl = c.split(':')
        demands[1 + len(bg) + i] = 10.0 - int(lvl.rstrip('\"'))
    else:
        demands[1 + len(bg) + i] = 5.0

W = np.full((n_sources, n_targets), 2.0)
for i in range(min(n_sources, n_targets)):
    W[i, i] = 1.0

alloc = TropicalAttention(n_sources, n_targets)
alloc.set_cost_matrix(W)
eigenval, eigenvec = alloc.steady_state_pattern()

print(json.dumps({
    'eigenvalue': float(eigenval) if eigenval != TROPICAL_INF else None,
    'eigenvector': eigenvec.tolist(),
    'n_sources': n_sources,
    'n_targets': n_targets
}))
"
        ;;

    adapt)
        # Read feedback from attention_feedback.json and adapt costs
        FEEDBACK_FILE="/opt/athena/state/attention_feedback.json"
        if [ -f "$FEEDBACK_FILE" ]; then
            python3 -c "
import json, sys
sys.path.insert(0, '$PYTHON_LIB/athena')
from tropical_attention import TropicalAttention, TROPICAL_INF
import numpy as np

with open('$FEEDBACK_FILE') as f:
    feedback = json.load(f)

# Reconstruct cost matrix from current state
with open('$STATE') as f:
    state = json.load(f)

active = state.get('active_task')
bg = state.get('background', [])
concerns = state.get('concerns', [])

n_sources = 5
n_targets = 1 + len(bg) + len(concerns)

W = np.full((n_sources, n_targets), 2.0)
for i in range(min(n_sources, n_targets)):
    W[i, i] = 1.0

alloc = TropicalAttention(n_sources, n_targets)
alloc.set_cost_matrix(W)
alloc.adaptive_reweight(feedback, learning_rate=0.1)

# Save updated cost matrix
with open('$TROPICAL_STATE', 'r') as f:
    data = json.load(f)
data['cost_matrix'] = alloc.W.tolist()
with open('$TROPICAL_STATE', 'w') as f:
    json.dump(data, f, separators=(',', ':'))

print('Adapted cost matrix from feedback')
"
        else
            echo "No feedback file found"
        fi
        ;;

    read)
        if [ -f "$TROPICAL_STATE" ]; then
            cat "$TROPICAL_STATE" | python3 -m json.tool
        else
            echo '{"error": "No tropical allocation computed yet. Run allocate first."}'
        fi
        ;;

    *)
        echo "usage: $0 {allocate|steady|adapt|read}" >&2
        exit 1
        ;;
esac