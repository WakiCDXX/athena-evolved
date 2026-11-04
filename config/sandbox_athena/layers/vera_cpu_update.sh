#!/usr/bin/bash
BASE_DIR="/root"
source "/opt/athena/bin/athena_env.sh" 2>/dev/null
# vera_cpu_update.sh — Vera CPU scheduler layer state
# Usage:
#   vera_cpu_update.sh read                    → prints JSON
#   vera_cpu_update.sh poll                    → update all fields once
#   vera_cpu_update.sh scheduler               → scheduler metrics
#   vera_cpu_update.sh power                   → power domains

set -o pipefail

STATE="/opt/athena/state/vera_cpu.json"

now() { date +%s; }

check_scheduler() {
    local active_cores=0
    local idle_cores=0
    local runqueue_length=0
    local migrations=0
    local preemption_count=0

    # Get core info
    active_cores=$(nproc)
    idle_cores=0

    # Simulate scheduler metrics
    runqueue_length=$(cat /proc/loadavg 2>/dev/null | awk '{print int($1)}' || echo 0)
    migrations=3
    preemption_count=47

    export VERA_CPU_STATE_PATH="$STATE" VERA_CPU_FIELD="scheduler"
    export VERA_CPU_FIELD_JSON="{\"active_cores\":$active_cores,\"idle_cores\":$idle_cores,\"runqueue_length\":$runqueue_length,\"migrations_last_minute\":$migrations,\"preemption_count\":$preemption_count,\"last_check\":$(now)}"
    python3 "$PYTHON_LIB/athena/vera_cpu_write.py" 2>/dev/null
}

check_power() {
    local power_domains_active=0
    local temperature=0
    local frequency=0

    # Get thermal info
    for zone in /sys/class/thermal/thermal_zone*/temp; do
        [ -r "$zone" ] || continue
        local temp_raw=$(cat "$zone" 2>/dev/null)
        if [ -n "$temp_raw" ]; then
            temperature=$((temp_raw / 1000))
            break
        fi
    done

    # Get frequency
    if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ]; then
        frequency=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null | awk '{print $1/1000}' || echo 0)
    fi

    # Simulate power domains
    power_domains_active=6

    export VERA_CPU_STATE_PATH="$STATE" VERA_CPU_FIELD="power"
    export VERA_CPU_FIELD_JSON="{\"power_domains_active\":$power_domains_active,\"temperature_celsius\":$temperature,\"frequency_mhz\":$frequency,\"last_check\":$(now)}"
    python3 "$PYTHON_LIB/athena/vera_cpu_write.py" 2>/dev/null
}

case "${1:-read}" in
    read)
        cat "$STATE"
        ;;
    poll)
        check_scheduler
        check_power
        export VERA_CPU_STATE_PATH="$STATE" VERA_CPU_FIELD="last_updated" VERA_CPU_FIELD_JSON="$(now)"
        python3 "$PYTHON_LIB/athena/vera_cpu_write.py" 2>/dev/null
        ;;
    scheduler) check_scheduler ;;
    power) check_power ;;
    *)
        echo "usage: $0 {read|poll|scheduler|power}" >&2
        exit 1
        ;;
esac