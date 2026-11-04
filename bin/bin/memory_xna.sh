#!/usr/bin/bash
# memory_xna.sh — XNA-inspired pluggable memory codecs for Athena.
# Synthetic backbone encodings for corruption-resistant memory.
#
# Usage:
#   memory_xna.sh consolidate       → build XNA store from memory.json
#   memory_xna.sh store <key> <type> <json>  → store memory with XNA encoding
#   memory_xna.sh retrieve <key>    → retrieve and decode memory
#   memory_xna.sh verify            → verify integrity of all memories
#   memory_xna.sh repair            → attempt repair of corrupted memories
#   memory_xna.sh transcribe <type> <backbone> → transcribe memory type to new backbone
#   memory_xna.sh stats             → show encoding statistics
#   memory_xna.sh query <type> <text> → query memories by type and text
#   memory_xna.sh read              → print XNA store
#   memory_xna.sh demo              → run encoding demo

set -o pipefail

BASE_DIR="/root"
source "$BASE_DIR/.local/bin/athena_env.sh" 2>/dev/null

MEMORY_JSON="/opt/athena/state/memory.json"
XNA_STORE="/opt/athena/state/memory_xna.json"
PYTHON_LIB="${PYTHON_LIB:-$BASE_DIR/.local/lib/python}"

case "${1:-read}" in
    consolidate)
        echo "Consolidating memory to XNA format..."
        python3 "$PYTHON_LIB/athena/xna_memory.py" consolidate "$MEMORY_JSON" "$XNA_STORE"
        ;;

    store)
        if [ $# -lt 4 ]; then
            echo "usage: $0 store <key> <type> <json>" >&2
            exit 1
        fi
        key="$2"
        mtype="$3"
        json_data="$4"
        python3 -c "
import json, sys
sys.path.insert(0, '$PYTHON_LIB/athena')
from xna_memory import XNAMemoryEncoder, XNAMemoryStore

encoder = XNAMemoryEncoder()
store = XNAMemoryStore(encoder)

if sys.path[0] != '$PYTHON_LIB/athena':
    sys.path.insert(0, '$PYTHON_LIB/athena')

# Load existing store
import os
if os.path.exists('$XNA_STORE'):
    with open('$XNA_STORE') as f:
        data = json.load(f)
    store.import_store(data)

memory = json.loads('$json_data')
packet = store.store('$key', memory, '$mtype')

# Save
with open('$XNA_STORE', 'w') as f:
    json.dump(store.export(), f, separators=(',', ':'))

print('Stored:', '\$key')
print('Backbone:', packet.backbone.value)
print('Size:', packet.metadata.get('original_size'), '->', packet.metadata.get('encoded_size'))
"
        ;;

    retrieve)
        if [ $# -lt 2 ]; then
            echo "usage: $0 retrieve <key>" >&2
            exit 1
        fi
        python3 -c "
import json, sys
sys.path.insert(0, '$PYTHON_LIB/athena')
from xna_memory import XNAMemoryEncoder, XNAMemoryStore

encoder = XNAMemoryEncoder()
store = XNAMemoryStore(encoder)

with open('$XNA_STORE') as f:
    data = json.load(f)
store.import_store(data)

memory = store.retrieve('$2')
if memory:
    print(json.dumps(memory, indent=2))
else:
    print('Memory not found:', '\$2')
"
        ;;

    verify)
        python3 -c "
import json, sys
sys.path.insert(0, '$PYTHON_LIB/athena')
from xna_memory import XNAMemoryEncoder, XNAMemoryStore

encoder = XNAMemoryEncoder()
store = XNAMemoryStore(encoder)

with open('$XNA_STORE') as f:
    data = json.load(f)
store.import_store(data)

results = store.verify_all()
corrupted = [k for k, v in results.items() if not v]
print(json.dumps({
    'total': len(results),
    'verified': len(results) - len(corrupted),
    'corrupted': len(corrupted),
    'corrupted_keys': corrupted
}, indent=2))
"
        ;;

    repair)
        python3 -c "
import json, sys
sys.path.insert(0, '$PYTHON_LIB/athena')
from xna_memory import XNAMemoryEncoder, XNAMemoryStore

encoder = XNAMemoryEncoder()
store = XNAMemoryStore(encoder)

with open('$XNA_STORE') as f:
    data = json.load(f)
store.import_store(data)

results = store.repair_all()
repaired = [k for k, v in results.items() if v]
failed = [k for k, v in results.items() if not v]
print(json.dumps({
    'total': len(results),
    'repaired': len(repaired),
    'failed': len(failed),
    'failed_keys': failed
}, indent=2))

# Save repaired store
with open('$XNA_STORE', 'w') as f:
    json.dump(store.export(), f, separators=(',', ':'))
"
        ;;

    transcribe)
        if [ $# -lt 3 ]; then
            echo "usage: $0 transcribe <type> <backbone>" >&2
            exit 1
        fi
        python3 -c "
import json, sys
sys.path.insert(0, '$PYTHON_LIB/athena')
from xna_memory import XNAMemoryEncoder, XNAMemoryStore, XNABackbone

encoder = XNAMemoryEncoder()
store = XNAMemoryStore(encoder)

with open('$XNA_STORE') as f:
    data = json.load(f)
store.import_store(data)

store.transcribe_type('$2', XNABackbone('\$3'))

with open('$XNA_STORE', 'w') as f:
    json.dump(store.export(), f, separators=(',', ':'))

print(f'Transcribed {$\2} to {$\3}')
"
        ;;

    stats)
        python3 -c "
import json, sys
sys.path.insert(0, '$PYTHON_LIB/athena')
from xna_memory import XNAMemoryEncoder, XNAMemoryStore

encoder = XNAMemoryEncoder()
store = XNAMemoryStore(encoder)

with open('$XNA_STORE') as f:
    data = json.load(f)
store.import_store(data)

stats = store.get_stats()
print(json.dumps(stats, indent=2))
"
        ;;

    query)
        if [ $# -lt 3 ]; then
            echo "usage: $0 query <type> <text>" >&2
            exit 1
        fi
        python3 -c "
import json, sys
sys.path.insert(0, '$PYTHON_LIB/athena')
from xna_memory import xna_memory_query

results = xna_memory_query('$XNA_STORE', {'type': '\$2', 'text': '\$3'})
print(json.dumps(results, indent=2))
"
        ;;

    read)
        if [ -f "$XNA_STORE" ]; then
            cat "$XNA_STORE" | python3 -m json.tool
        else
            echo '{"error": "No XNA store found. Run consolidate first."}'
        fi
        ;;

    demo)
        python3 "$PYTHON_LIB/athena/xna_memory.py" demo
        ;;

    *)
        echo "usage: \$0 {consolidate|store|retrieve|verify|repair|transcribe|stats|query|read|demo}" >&2
        exit 1
        ;;
esac