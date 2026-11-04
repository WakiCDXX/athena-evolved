#!/usr/bin/bash
BASE_DIR="/root"
source "$BASE_DIR/.local/bin/athena_env.sh" 2>/dev/null
# memory_consolidation.sh — consolidate memory markdown files into memory.json.
# Usage:
#   memory_consolidation.sh consolidate  → scan memory dir, write memory.json
#   memory_consolidation.sh read         → print memory.json
#   memory_consolidation.sh stats        → show file count and sizes

set -o pipefail

MEMORY_ROOT="/root/.openclaude/projects/-data-data-com-termux-files-home/memory"
STATE="/opt/athena/state/memory.json"

now() { date +%s; }

consolidate() {
    local count=0 total_size=0
    local files=""
    for f in "$MEMORY_ROOT"/*.md; do
        [ -f "$f" ] || continue
        count=$((count + 1))
        local sz=$(stat -c%s "$f" 2>/dev/null || echo 0)
        total_size=$((total_size + sz))
        files="$files$f"$'\n'
    done
    export MEMORY_CONSOLIDATE_COUNT="$count"
    export MEMORY_CONSOLIDATE_TOTAL_SIZE="$total_size"
    export MEMORY_CONSOLIDATE_FILES="$files"
    export MEMORY_CONSOLIDATE_PATH="$STATE"
    python3 "$PYTHON_LIB/athena/memory_consolidate.py" 2>/dev/null
}

case "${1:-read}" in
    consolidate)
        consolidate
        ;;
    read)
        export MEMORY_CONSOLIDATE_PATH="$STATE"
        python3 "$PYTHON_LIB/athena/memory_consolidate_full.py" 2>/dev/null
        ;;
    stats)
        if [ -f "$STATE" ]; then
            cat "$STATE" | python3 -m json.tool
        else
            echo '{"memory_files":0}'
        fi
        ;;
    *)
        echo "usage: $0 {consolidate|read|stats}" >&2
        exit 1
        ;;
esac
