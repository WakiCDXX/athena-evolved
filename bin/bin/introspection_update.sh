#!/usr/bin/bash
BASE_DIR="/root"
source "$BASE_DIR/.local/bin/athena_env.sh" 2>/dev/null
# introspection_update.sh — Athena's self-query and self-report.
# Usage:
#   introspection_update.sh read              → prints last self-report
#   introspection_update.sh report            → generate full self-report now
#   introspection_update.sh query <question>  → targeted self-query
#   introspection_update.sh history           → show query history

set -o pipefail

STATE="/opt/athena/state/introspection.json"
SENSE_LOG="/opt/athena/state/senses.log"
TRAINING_DIR="/opt/athena/state/corpus/training"
EMBEDDINGS_DIR="/opt/athena/state/corpus/embeddings"

mkdir -p "$TRAINING_DIR" "$EMBEDDINGS_DIR"

export INTROSPECTION_STATE_PATH="$STATE"
export INTROSPECTION_SENSE_LOG="$SENSE_LOG"
export INTROSPECTION_DATA_DIR="/opt/athena/state"
export INTROSPECTION_TRAINING_DIR="$TRAINING_DIR"
export INTROSPECTION_EMBEDDINGS_DIR="$EMBEDDINGS_DIR"

case "${1:-read}" in
    read)
        python3 "$PYTHON_LIB/athena/introspection_read.py" 2>/dev/null
        ;;
    report)
        python3 "$PYTHON_LIB/athena/introspection_report.py" 2>/dev/null
        python3 "$PYTHON_LIB/athena/introspection_training.py" 2>/dev/null
        ;;
    query)
        [ -z "$2" ] && { echo "usage: $0 query <question>" >&2; exit 1; }
        export INTROSPECTION_QUESTION="$2"
        python3 "$PYTHON_LIB/athena/introspection_query.py" 2>/dev/null
        ;;
    history)
        python3 "$PYTHON_LIB/athena/introspection_history.py" 2>/dev/null
        ;;
    *)
        echo "usage: $0 {read|report|query <question>|history}" >&2
        exit 1
        ;;
esac
