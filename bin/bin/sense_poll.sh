#!/usr/bin/bash
# sense_poll.sh — background poller for Athena's senses.
# Emits one JSON line per tick to senses.log. 60s default, 1MB log cap.
#
# Idempotent: writes atomically, rotates on size, exits cleanly on SIGTERM.
# Now uses sensor_cache.py (cached polling via sensor sidecar) for privileged sensors.

set -u

source "/opt/athena/bin/athena_env.sh" 2>/dev/null
DATA_DIR="/opt/athena/state"
LOG="$DATA_DIR/senses.log"
PIDFILE="$DATA_DIR/sense_poll.pid"
ARCHIVE_DIR="$DATA_DIR/corpus/senses_historical"
INTERVAL="${SENSE_INTERVAL:-60}"
MAX_BYTES=$((1024 * 1024))
MAX_ARCHIVE_AGE=86400
SENSES_LOG="$LOG"
SENSES_JSON="$DATA_DIR/senses.json"

mkdir -p "$(dirname "$LOG")"
touch "$LOG"

cleanup() {
    rm -f "$PIDFILE"
    exit 0
}
trap cleanup TERM INT

# --- helpers -----------------------------------------------------------------

# Use sensor_cache.py for privileged sensors (battery, network, location, screen, etc.)
# Fallback to direct termux-api for system sensors (CPU, memory, uptime)

SENSOR_CACHE_CMD="python3 -m athena.sensor_cache"

get_sensor_cached() {
    local sensor="$1"
    local ttl="${2:-10}"
    python3 -c "
import sys
sys.path.insert(0, '$PYTHON_LIB')
from athena.sensor_cache import SensorCache
cache = SensorCache()
data = cache.get('$sensor', ttl=$ttl)
import json
print(json.dumps(data) if data else '{}')
" 2>/dev/null || echo "{}"
}

sense_battery_json() {
    get_sensor_cached "battery" 30
}

sense_wifi_json() {
    get_sensor_cached "network" 30
}

sense_location_json() {
    get_sensor_cached "location" 60
}

sense_screen_json() {
    get_sensor_cached "screen" 10
}

sense_device_json() {
    local sdk=$(getprop ro.build.version.sdk 2>/dev/null || echo "")
    local release=$(getprop ro.build.version.release 2>/dev/null || echo "")
    local model=$(getprop ro.product.model 2>/dev/null || echo "")
    local hardware=$(getprop ro.hardware 2>/dev/null || echo "")
    local density=$(getprop ro.sf.lcd_density 2>/dev/null || echo "")
    local tz=$(getprop persist.sys.timezone 2>/dev/null || echo "")
    local zygote=$(getprop init.svc.zygote 2>/dev/null || echo "")

    echo "$model" "$sdk" "$release" "$hardware" "$density" "$tz" "$zygote" | tr ' ' '\n' | python3 "$PYTHON_LIB/athena/sense_devices.py" 2>/dev/null || echo ""
}

read_cpu_cur() {
    cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null | head -1 || echo 0
}

read_uptime() {
    local up idle
    if [ -r /proc/uptime ]; then
        read up idle < /proc/uptime
        printf '%d' "${up%.*}"
    else
        printf '0'
    fi
}

rotate_if_needed() {
    if [ -f "$LOG" ]; then
        local size=$(stat -c%s "$LOG" 2>/dev/null || echo 0)
        if [ "$size" -gt "$MAX_BYTES" ]; then
            local ts=$(date +%Y%m%d_%H%M%S)
            cp "$LOG" "$ARCHIVE_DIR/senses_${ts}.log" 2>/dev/null
            : > "$LOG"
        fi
    fi
}

write_senses_json() {
    export SENSE_BAT_JSON="$ATHENA_BAT_STR"
    export SENSE_WIFI_JSON="$ATHENA_WIFI_STR"
    export SENSE_DEV_JSON="$ATHENA_DEV_STR"
    export SENSE_TS="$ATHENA_TS"
    export SENSE_CPU_CUR="$ATHENA_CPU_CUR"
    export SENSE_UPTIME="$ATHENA_UPTIME"
    export SENSE_MEM_TOTAL="$ATHENA_MEM_TOTAL"
    export SENSE_MEM_AVAIL="$ATHENA_MEM_AVAIL"
    export SENSE_MEM_FREE="$ATHENA_MEM_FREE"
    export SENSE_CPU_GOV="$ATHENA_CPU_GOV"
    export SENSE_CPU_MIN="$ATHENA_CPU_MIN"
    export SENSE_CPU_MAX="$ATHENA_CPU_MAX"
    python3 "$PYTHON_LIB/athena/sense_poll_write_json.py" 2>/dev/null
}

# --- tick --------------------------------------------------------------------

tick() {
    local ts cpu_cur_khz uptime
    ts=$(date +%s)
    cpu_cur_khz=$(read_cpu_cur)
    uptime=$(read_uptime)

    export ATHENA_TS="$ts"
    export ATHENA_CPU_CUR="$cpu_cur_khz"
    export ATHENA_UPTIME="$uptime"
    export ATHENA_CPU_GOV="$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_governor 2>/dev/null || echo '?')"
    export ATHENA_CPU_MIN="$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_min_freq 2>/dev/null || echo 0)"
    export ATHENA_CPU_MAX="$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq 2>/dev/null || echo 0)"
    export ATHENA_MEM_TOTAL="$(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null || echo 0)"
    export ATHENA_MEM_AVAIL="$(awk '/^MemAvailable:/{print $2}' /proc/meminfo 2>/dev/null || echo 0)"
    export ATHENA_MEM_FREE="$(awk '/^MemFree:/{print $2}' /proc/meminfo 2>/dev/null || echo 0)"
    export ATHENA_BAT_STR="$(sense_battery_json)"
    export ATHENA_WIFI_STR="$(sense_wifi_json)"
    export ATHENA_LOC_STR="$(sense_location_json)"
    export ATHENA_SCREEN_STR="$(sense_screen_json)"
    export ATHENA_DEV_STR="$(sense_device_json)"

    python3 "$PYTHON_LIB/athena/sense_poll_tick.py" >> "$LOG" 2>/dev/null

    rotate_if_needed
    write_senses_json
}

# --- arg handling ------------------------------------------------------------
case "${1:-}" in
    _daemon)
        echo $$ > "$PIDFILE"
        while :; do
            tick
            sleep "$INTERVAL"
        done
        ;;
    one-shot)
        tick
        ;;
    *)
        echo "usage: $0 {_daemon|one-shot}" >&2
        exit 1
        ;;
esac
