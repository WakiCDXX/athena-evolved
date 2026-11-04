#!/bin/bash
# Athena Archive Maintenance Script
# Archives old sense entries and performs routine data maintenance

source "$(dirname "$0")/athena_env.sh"

DATA="${ATHENA_DATA_DIR:-/opt/athena/state}"
SENSES_LOG="${ATHENA_SENSES_LOG:-$DATA/senses.log}"
ARCHIVE_DIR="${ATHENA_ARCHIVE_DIR:-$DATA/corpus/senses_historical}"
CUTOFF="${ATHENA_CUTOFF_SECONDS:-0}"

export ATHENA_DATA_DIR="$DATA"
export ATHENA_SENSES_LOG="$SENSES_LOG"
export ATHENA_ARCHIVE_DIR="$ARCHIVE_DIR"
export ATHENA_CUTOFF_SECONDS="$CUTOFF"

echo "=== Athena Archive Maintenance ==="
echo "Data dir: $DATA"
echo "Cutoff: $CUTOFF seconds"
echo ""

# Archive old sense entries
python3 "$PYTHON_LIB/athena/archive_senses.py"
