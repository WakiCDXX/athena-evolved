#!/usr/bin/bash
# memory_padic.sh — p-adic ultrametric memory addressing for Athena.
# Replaces flat memory indexing with hierarchical p-adic tree (ℤₚ).
#
# Usage:
#   memory_padic.sh consolidate    → build p-adic index from memory.json
#   memory_padic.sh query <path>   → query memory by concept path (ultrametric nearest neighbors)
#   memory_padic.sh cluster        → show ultrametric clusters
#   memory_padic.sh refine <addr>  → Hensel refinement from approximate address
#   memory_padic.sh read           → print p-adic memory state

set -o pipefail

BASE_DIR="/root"
source "$BASE_DIR/.local/bin/athena_env.sh" 2>/dev/null

MEMORY_JSON="/opt/athena/state/memory.json"
PADIC_JSON="/opt/athena/state/memory_padic.json"
PYTHON_LIB="${PYTHON_LIB:-$BASE_DIR/.local/lib/python}"

case "${1:-read}" in
    consolidate)
        echo "Consolidating memory to p-adic format..."
        python3 "$PYTHON_LIB/athena/p_adic_memory.py" consolidate "$MEMORY_JSON" "$PADIC_JSON" 2
        ;;

    query)
        if [ $# -lt 2 ]; then
            echo "usage: $0 query <concept_path...>" >&2
            exit 1
        fi
        shift
        python3 "$PYTHON_LIB/athena/p_adic_memory.py" query "$PADIC_JSON" "$@"
        ;;

    cluster)
        python3 -c "
import json, sys
sys.path.insert(0, '$PYTHON_LIB/athena')
from p_adic_memory import PadicMemory

with open('$PADIC_JSON') as f:
    state = json.load(f)

pm = PadicMemory(p=state.get('p', 2), max_depth=state.get('max_depth', 64))
pm.import_state(state)

all_addrs = [a for a in pm._address_index.keys() if a != 0 and pm._address_index[a].data]
clusters = pm.cluster_radius(all_addrs, 0.1)

for center, members in clusters.items():
    print(f'Cluster {center}: {len(members)} items')
    for m in members[:3]:
        node = pm._address_index[m]
        path = node.metadata.get('concept_path', 'unknown')
        print(f'  {m}: {path}')
    if len(members) > 3:
        print(f'  ... and {len(members)-3} more')
"
        ;;

    refine)
        if [ $# -lt 2 ]; then
            echo "usage: $0 refine <approximate_address> [target_json]" >&2
            exit 1
        fi
        addr=$2
        target='{}'
        if [ $# -ge 3 ]; then
            target=$3
        fi
        python3 -c "
import json, sys
sys.path.insert(0, '$PYTHON_LIB/athena')
from p_adic_memory import PadicMemory

with open('$PADIC_JSON') as f:
    state = json.load(f)

pm = PadicMemory(p=state.get('p', 2), max_depth=state.get('max_depth', 64))
pm.import_state(state)

target_data = json.loads('$target')
refined_addr, data = pm.hensel_refine($addr, target_data)
print(json.dumps({
    'original_address': $addr,
    'refined_address': refined_addr,
    'data': data
}))
"
        ;;

    read)
        if [ -f "$PADIC_JSON" ]; then
            cat "$PADIC_JSON" | python3 -m json.tool
        else
            echo '{"error": "No p-adic memory index found. Run consolidate first."}'
        fi
        ;;

    stats)
        if [ -f "$PADIC_JSON" ]; then
            python3 -c "
import json
with open('$PADIC_JSON') as f:
    state = json.load(f)
nodes = state.get('nodes', {})
concepts = state.get('concept_map', {})
data_nodes = sum(1 for n in nodes.values() if n.get('data'))
print(json.dumps({
    'total_nodes': len(nodes),
    'data_nodes': data_nodes,
    'concepts_indexed': len(concepts),
    'p': state.get('p', 2),
    'max_depth': state.get('max_depth', 64),
    'consolidated_at': state.get('consolidated_at')
}))
"
        else
            echo '{"error": "No p-adic memory index found"}'
        fi
        ;;

    *)
        echo "usage: $0 {consolidate|query <path...>|cluster|refine <addr>|read|stats}" >&2
        exit 1
        ;;
esac