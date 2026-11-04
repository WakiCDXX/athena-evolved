#!/usr/bin/bash
BASE_DIR="/root"
source "/opt/athena/bin/athena_env.sh" 2>/dev/null
# archestra_update.sh — Archestra tonl policy layer state
# Usage:
#   archestra_update.sh read                    → prints JSON
#   archestra_update.sh poll                    → update all fields once
#   archestra_update.sh tonl                    → scan TONL tags
#   archestra_update.sh alarms                  → check alarms

set -o pipefail

STATE="/opt/athena/state/archestra.json"

now() { date +%s; }

scan_tonl() {
    local tags_defined=1247
    local tags_active=1198
    local scan_cycle_ms=5000
    local alarms_active=0
    local compression_ratio=2.3

    # Simulate TONL tag scanning
    local scan_start=$(now)
    sleep 0.001  # Simulate scan time
    local scan_end=$(now)
    scan_cycle_ms=$((scan_end - scan_start))

    export ARCHESTRA_STATE_PATH="$STATE" ARCHESTRA_FIELD="tonl"
    export ARCHESTRA_FIELD_JSON="{\"tags_defined\":$tags_defined,\"tags_active\":$tags_active,\"scan_cycle_ms\":$scan_cycle_ms,\"alarms_active\":$alarms_active,\"compression_ratio\":$compression_ratio,\"last_check\":$(now)}"
    python3 "$PYTHON_LIB/athena/archestra_write.py" 2>/dev/null
}

check_alarms() {
    local alarms_active=2
    local alarms_acknowledged=1
    local alarm_priority=3

    export ARCHESTRA_STATE_PATH="$STATE" ARCHESTRA_FIELD="alarms"
    export ARCHESTRA_FIELD_JSON="{\"alarms_active\":$alarms_active,\"alarms_acknowledged\":$alarms_acknowledged,\"alarm_priority\":$alarm_priority,\"last_check\":$(now)}"
    python3 "$PYTHON_LIB/athena/archestra_write.py" 2>/dev/null
}

case "${1:-read}" in
    read)
        cat "$STATE"
        ;;
    poll)
        scan_tonl
        check_alarms
        export ARCHESTRA_STATE_PATH="$STATE" ARCHESTRA_FIELD="last_updated" ARCHESTRA_FIELD_JSON="$(now)"
        python3 "$PYTHON_LIB/athena/archestra_write.py" 2>/dev/null
        ;;
    tonl) scan_tonl ;;
    alarms) check_alarms ;;
    *)
        echo "usage: $0 {read|poll|tonl|alarms}" >&2
        exit 1
        ;;
esac