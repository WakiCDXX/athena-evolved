#!/usr/bin/bash
BASE_DIR="/root"
source "$BASE_DIR/.local/bin/athena_env.sh" 2>/dev/null
# openappa_update.sh — OpenAPPA portability layer state
# Usage:
#   openappa_update.sh read                    → prints JSON
#   openappa_update.sh poll                    → update all fields once
#   openappa_update.sh portability             → check portability status
#   openappa_update.sh vera_cpu                → check Vera CPU binding

set -o pipefail

STATE="/opt/athena/state/openappa.json"

now() { date +%s; }

check_portability() {
    local platform="termux"
    local openappa_available=false
    local migration_ready=false

    # Check if OpenAPPA libraries are available
    if command -v openappa-daemon >/dev/null 2>&1; then
        openappa_available=true
    fi

    # Check Vera CPU features
    local cpu_cores=$(nproc)
    local cpu_arch=$(uname -m)
    local numa_domains=0
    if [ -d /sys/devices/system/node ]; then
        numa_domains=$(ls -d /sys/devices/system/node/node* 2>/dev/null | wc -l)
    fi

    export OPENAPPA_STATE_PATH="$STATE" OPENAPPA_FIELD="portability"
    export OPENAPPA_FIELD_JSON="{\"platform\":\"$platform\",\"openappa_available\":$openappa_available,\"migration_ready\":$migration_ready,\"cpu_cores\":$cpu_cores,\"cpu_arch\":\"$cpu_arch\",\"numa_domains\":$numa_domains,\"last_check\":$(now)}"
    python3 "$PYTHON_LIB/athena/openappa_write.py" 2>/dev/null
}

check_vera_cpu() {
    local vera_bound=false
    local active_cores=0
    local memory_bandwidth=0
    local cache_coherency="none"

    # Simulate Vera CPU binding check
    if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ]; then
        local freq=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null || echo 0)
        active_cores=$(nproc)
        vera_bound=true
    fi

    export OPENAPPA_STATE_PATH="$STATE" OPENAPPA_FIELD="vera_cpu"
    export OPENAPPA_FIELD_JSON="{\"vera_bound\":$vera_bound,\"active_cores\":$active_cores,\"memory_bandwidth_gbps\":$memory_bandwidth,\"cache_coherency\":\"$cache_coherency\",\"last_check\":$(now)}"
    python3 "$PYTHON_LIB/athena/openappa_write.py" 2>/dev/null
}

case "${1:-read}" in
    read)
        cat "$STATE"
        ;;
    poll)
        check_portability
        check_vera_cpu
        export OPENAPPA_STATE_PATH="$STATE" OPENAPPA_FIELD="last_updated" OPENAPPA_FIELD_JSON="$(now)"
        python3 "$PYTHON_LIB/athena/openappa_write.py" 2>/dev/null
        ;;
    portability) check_portability ;;
    vera_cpu) check_vera_cpu ;;
    *)
        echo "usage: $0 {read|poll|portability|vera_cpu}" >&2
        exit 1
        ;;
esac