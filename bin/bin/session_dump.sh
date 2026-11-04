#!/bin/bash
# Athena Session Dump Script
# Dumps all layer states to a unified JSON snapshot

source "$(dirname "$0")/athena_env.sh"

DATA="${ATHENA_DATA_DIR:-/opt/athena/state}"
SESSION_FILE="${ATHENA_SESSION_FILE:-$DATA/session_context.json}"

export DATA="$DATA"
export SESSION_FILE="$SESSION_FILE"
export OPENAI_MODEL="${OPENAI_MODEL:-unknown}"

echo "=== Athena Session Dump ==="
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Data dir: $DATA"
echo ""

# Dump all layer states to unified JSON snapshot
python3 "$PYTHON_LIB/athena/session_dump.py"

echo ""
echo "=== Session Context ==="
python3 "$PYTHON_LIB/athena/session_read.py"

echo ""
echo "=== Session Summary ==="
python3 "$PYTHON_LIB/athena/session_summary.py"
