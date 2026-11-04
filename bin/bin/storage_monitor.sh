#!/bin/bash
# Athena Storage Monitor Script
# Monitors data storage, calculates growth projections, and checks archival status

source "$(dirname "$0")/athena_env.sh"

DATA="${ATHENA_DATA_DIR:-/opt/athena/state}"
SENSES_LOG="${ATHENA_SENSES_LOG:-$DATA/senses.log}"
ARCHIVE_DIR="${ATHENA_ARCHIVE_DIR:-$DATA/corpus/senses_historical}"

export ATHENA_DATA_DIR="$DATA"
export ATHENA_SENSES_LOG="$SENSES_LOG"
export ATHENA_ARCHIVE_DIR="$ARCHIVE_DIR"

echo "=== Athena Storage Monitor ==="
echo "Data dir: $DATA"
echo ""

# Calculate storage growth projections
python3 "$PYTHON_LIB/athena/storage_growth.py"

echo ""
# Calculate storage utilization statistics
python3 "$PYTHON_LIB/athena/storage_stats.py"
