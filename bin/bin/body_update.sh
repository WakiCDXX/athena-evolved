#!/usr/bin/bash
BASE_DIR="/root"
source "$BASE_DIR/.local/bin/athena_env.sh" 2>/dev/null
# body_update.sh — read device body/state into JSON.
# Usage:
#   body_update.sh read                    → prints JSON
#   body_update.sh poll                    → update all fields once
#   body_update.sh thermal                 → thermal only
#   body_update.sh storage                 → storage only
#   body_update.sh network                 → network only
#   body_update.sh processes               → processes only
#   body_update.sh kernel                  → kernel only

set -o pipefail

STATE="/opt/athena/state/body.json"

now() { date +%s; }

read_thermal() {
    local zones=() throttling=false
    for zone in /sys/class/thermal/thermal_zone*/temp; do
        [ -r "$zone" ] || continue
        local temp_raw=$(cat "$zone" 2>/dev/null)
        [ -n "$temp_raw" ] && zones+=("$((temp_raw / 1000))")
    done
    for zone in /sys/class/thermal/thermal_zone*/mode; do
        [ -r "$zone" ] || continue
        grep -q "enabled" "$zone" 2>/dev/null && throttling=true
    done
    local zones_str=$(IFS=,; echo "${zones[*]}")
    export BODY_STATE_PATH="$STATE" BODY_FIELD="thermal" BODY_FIELD_JSON='{"zones":['"$zones_str"'],"throttling":'"$throttling"',"last_check":'"$(now)"'}'
    python3 "$PYTHON_LIB/athena/body_write.py" 2>/dev/null
}

read_storage() {
    local out=$(df -k /data 2>/dev/null | tail -1)
    local total=0 avail=0 pct=0
    if [ -n "$out" ]; then
        total=$(echo "$out" | awk '{print $2}')
        avail=$(echo "$out" | awk '{print $4}')
        pct=$(( (total - avail) * 100 / total ))
    fi
    export BODY_STATE_PATH="$STATE" BODY_FIELD="storage" BODY_FIELD_JSON='{"total_mb":'"$((total / 1024))"',"avail_mb":'"$((avail / 1024))"',"pct_used":'"$pct"',"last_check":'"$(now)"'}'
    python3 "$PYTHON_LIB/athena/body_write.py" 2>/dev/null
}

read_network() {
    local type="unknown" ssid="null" signal=0 rx=0 tx=0
    local wifi=$(timeout 5 termux-wifi-connectioninfo 2>/dev/null || echo "")
    if [ -n "$wifi" ]; then
        type="wifi"
        local wifi_json
        wifi_json=$(echo "$wifi" | python3 "$PYTHON_LIB/athena/json_get.py" 2>/dev/null || echo "{}")
        ssid=$(echo "$wifi_json" | python3 "$PYTHON_LIB/athena/json_get.py" 2>/dev/null || echo "null")
        export BODY_WIFI_JSON="$wifi_json"
        python3 "$PYTHON_LIB/athena/body_extract_rssi.py" 2>/dev/null || signal=0
    fi
    for iface in wlan0 eth0 rmnet0; do
        if [ -r "/sys/class/net/$iface/statistics/rx_bytes" ]; then
            rx=$(cat "/sys/class/net/$iface/statistics/rx_bytes" 2>/dev/null || echo 0)
            tx=$(cat "/sys/class/net/$iface/statistics/tx_bytes" 2>/dev/null || echo 0)
            break
        fi
    done
    export BODY_STATE_PATH="$STATE" BODY_FIELD="network" BODY_FIELD_JSON='{"type":"'"$type"'","ssid":'"$ssid"',"signal_dbm":'"$signal"',"rx_bytes":'"$rx"',"tx_bytes":'"$tx"',"last_check":'"$(now)"'}'
    python3 "$PYTHON_LIB/athena/body_write.py" 2>/dev/null
}

read_processes() {
    local termux_pid=$$
    local top_cpu=() top_mem=()
    for line in $(ps -eo pid,pcpu,comm --sort=-pcpu 2>/dev/null | head -6 | tail -5); do
        top_cpu+=("$line")
    done
    for line in $(ps -eo pid,pmem,comm --sort=-pmem 2>/dev/null | head -6 | tail -5); do
        top_mem+=("$line")
    done
    local cpu_str=$(IFS=,; echo "${top_cpu[*]}")
    local mem_str=$(IFS=,; echo "${top_mem[*]}")
    export BODY_STATE_PATH="$STATE" BODY_FIELD="processes"
    export BODY_PROC_PID="$termux_pid" BODY_TOP_CPU="[$cpu_str]" BODY_TOP_MEM="[$mem_str]" BODY_PROC_TS="$(now)"
    python3 "$PYTHON_LIB/athena/auto_procs.py" 2>/dev/null | python3 "$PYTHON_LIB/athena/auto_procs_write.py" 2>/dev/null || true
}

read_kernel() {
    local version=$(uname -r 2>/dev/null)
    local uptime=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo 0)
    local load=$(cat /proc/loadavg 2>/dev/null | awk '{print $1","$2","$3}' || echo "0,0,0")
    export BODY_STATE_PATH="$STATE" BODY_FIELD="kernel" BODY_FIELD_JSON='{"version":"'"$version"'","uptime_s":'"$uptime"',"load_avg":['"$load"'],"last_check":'"$(now)"'}'
    python3 "$PYTHON_LIB/athena/body_write.py" 2>/dev/null
}

case "${1:-read}" in
    read)
        cat "$STATE"
        ;;
    poll)
        read_thermal
        read_storage
        read_network
        read_processes
        read_kernel
        export BODY_STATE_PATH="$STATE" BODY_FIELD="last_updated" BODY_FIELD_JSON="$(now)"
        python3 "$PYTHON_LIB/athena/body_write.py" 2>/dev/null
        ;;
    thermal) read_thermal ;;
    storage) read_storage ;;
    network) read_network ;;
    processes) read_processes ;;
    kernel) read_kernel ;;
    *)
        echo "usage: $0 {read|poll|thermal|storage|network|processes|kernel}" >&2
        exit 1
        ;;
esac
