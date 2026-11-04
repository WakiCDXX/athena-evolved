#!/bin/bash
# =============================================================================
# Athena Health-First Dashboard
#
# Provides real-time health overview of all daemon layers with latency
# percentiles, cost tracking, guardrail violations, spin alerts, and
# state machine progress visualization.
# =============================================================================

set -euo pipefail

DATA_DIR="${DATA_DIR:-/opt/athena/state}"
OBS_SCRIPT="${OBS_SCRIPT:-/root/.local/lib/python/athena/observability.py}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Icons
ICON_GREEN="🟢"
ICON_YELLOW="🟡"
ICON_RED="🔴"
ICON_UNKNOWN="⚪"
ICON_ALERT="⚠️"
ICON_SPIN="🔄"
ICON_COST="💰"
ICON_LATENCY="⏱️"
ICON_STATE="🔄"

print_header() {
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║                    ${ICON_STATE} ATHENA FLEET HEALTH DASHBOARD ${ICON_STATE}                    ║${NC}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    echo
}

print_footer() {
    echo
    echo -e "${CYAN}Last updated: $(date '+%Y-%m-%d %H:%M:%S') | Data dir: ${DATA_DIR}${NC}"
    echo -e "${CYAN}Refresh: watch -n 5 $0${NC}"
}

status_icon() {
    case "$1" in
        green) echo -e "${GREEN}${ICON_GREEN}${NC}" ;;
        yellow) echo -e "${YELLOW}${ICON_YELLOW}${NC}" ;;
        red) echo -e "${RED}${ICON_RED}${NC}" ;;
        *) echo -e "${ICON_UNKNOWN}" ;;
    esac
}

format_duration() {
    local seconds=$1
    if [ $seconds -lt 60 ]; then
        echo "${seconds}s"
    elif [ $seconds -lt 3600 ]; then
        echo "$((seconds / 60))m $((seconds % 60))s"
    else
        echo "$((seconds / 3600))h $((seconds % 3600 / 60))m"
    fi
}

run_observability() {
    python3 "$OBS_SCRIPT" "$@"
}

show_overall_health() {
    local data=$(run_observability full 2>/dev/null || echo '{}')

    if [ "$data" = "{}" ]; then
        echo -e "${RED}Failed to fetch dashboard data. Is observability.py working?${NC}"
        return 1
    fi

    # Parse JSON with jq if available, otherwise use python
    if command -v jq >/dev/null 2>&1; then
        echo "$data" | jq -r '
            "OVERALL_HEALTH=\(.groups | map(.overall) | unique | join(","))"
        ' 2>/dev/null || true
    fi

    # Use python for robust parsing
    python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
groups = data.get('groups', {})
state = data.get('state_machine', {})
cost = data.get('cost_metrics', {})

# Overall health
statuses = [g.get('overall', 'unknown') for g in groups.values()]
if 'red' in statuses:
    overall = 'red'
elif 'yellow' in statuses:
    overall = 'yellow'
elif 'green' in statuses:
    overall = 'green'
else:
    overall = 'unknown'

healthy_count = sum(g.get('green', 0) for g in groups.values())
total_count = sum(g.get('total', 0) for g in groups.values())

print(f'OVERALL={overall}')
print(f'HEALTHY_COUNT={healthy_count}')
print(f'TOTAL_COUNT={total_count}')
print(f'STATE={state.get(\"current_state\", \"UNKNOWN\")}')
print(f'DEGRADATION={state.get(\"degradation\", \"normal\")}')
print(f'SESSION={state.get(\"session_mode\", \"event_driven\")}')
print(f'PROGRESS={state.get(\"progress_pct\", 0)}')
print(f'COST_TOTAL={cost.get(\"total_usd\", 0):.4f}')
" <<< "$data"
}

show_group_health() {
    local data=$(run_observability groups 2>/dev/null || echo '{}')

    if [ "$data" = "{}" ]; then
        echo -e "${RED}No group health data available${NC}"
        return
    fi

    echo -e "${BOLD}Layer Groups:${NC}"

    python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
for name, g in data.items():
    icon = '🟢' if g['overall'] == 'green' else ('🟡' if g['overall'] == 'yellow' else ('🔴' if g['overall'] == 'red' else '⚪'))
    healthy = g.get('green', 0)
    total = g.get('total', 0)
    stale = g.get('stale', [])
    stale_str = ''
    if stale:
        stale_str = ' ' + ' '.join(stale)
    print(f'  {icon} {name:20s} ({healthy}/{total} green){stale_str}')
    for layer, status in g.get('layers', {}).items():
        lic = '🟢' if status == 'green' else ('🟡' if status == 'yellow' else ('🔴' if status == 'red' else '⚪'))
        print(f'    {lic} {layer}')
" <<< "$data"
}

show_latency() {
    local data=$(run_observability latency 2>/dev/null || echo '{}')

    if [ "$data" = "{}" ]; then
        echo -e "${YELLOW}No latency data available${NC}"
        return
    fi

    echo -e "${BOLD}${ICON_LATENCY} Latency Percentiles (ms):${NC}"

    python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
for layer, p in sorted(data.items()):
    if p.get('count', 0) > 0:
        print(f'  {layer:25s} p50={p[\"p50\"]:>6.1f}  p95={p[\"p95\"]:>6.1f}  p99={p[\"p99\"]:>6.1f}  avg={p[\"avg\"]:>6.1f}  n={p[\"count\"]}')
    else:
        print(f'  {layer:25s} (no samples)')
" <<< "$data"
}

show_cost() {
    local data=$(run_observability cost 2>/dev/null || echo '{}')

    if [ "$data" = "{}" ]; then
        echo -e "${YELLOW}No cost data available${NC}"
        return
    fi

    echo -e "${BOLD}${ICON_COST} Cost Tracking (USD):${NC}"

    python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
total = data.get('total_usd', 0)
print(f'  Total: \${total:.4f}')
print(f'  By Layer:')
for layer, cost in sorted(data.get('by_layer', {}).items(), key=lambda x: -x[1]):
    if cost > 0:
        print(f'    {layer:25s} \${cost:.4f}')
print(f'  By Model:')
for model, cost in sorted(data.get('by_model', {}).items(), key=lambda x: -x[1]):
    if cost > 0:
        print(f'    {model:25s} \${cost:.4f}')
print(f'  By Phase:')
for phase, cost in sorted(data.get('by_phase', {}).items(), key=lambda x: -x[1]):
    if cost > 0:
        print(f'    {phase:25s} \${cost:.4f}')
" <<< "$data"
}

show_state_machine() {
    local data=$(run_observability state 2>/dev/null || echo '{}')

    if [ "$data" = "{}" ]; then
        echo -e "${YELLOW}No state machine data available${NC}"
        return
    fi

    echo -e "${BOLD}${ICON_STATE} State Machine Progress:${NC}"

    python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
state = data.get('current_state', 'UNKNOWN')
progress = data.get('progress_pct', 0)
degradation = data.get('degradation', 'normal')
session = data.get('session_mode', 'event_driven')
next_states = data.get('next_states', [])

print(f'  Current State: {state} ({progress}%)')
print(f'  Degradation: {degradation}')
print(f'  Session Mode: {session}')
print(f'  Next Valid: {', '.join(next_states) if next_states else 'none'}')

# Progress bar
bar_len = 40
filled = int(bar_len * progress / 100)
bar = '█' * filled + '░' * (bar_len - filled)
print(f'  Progress: [{bar}] {progress}%')
" <<< "$data"
}

show_spin_alerts() {
    local data=$(run_observability spin 2>/dev/null || echo '[]')

    if [ "$data" = "[]" ]; then
        echo -e "${GREEN}${ICON_SPIN} No spin alerts detected${NC}"
        return
    fi

    echo -e "${BOLD}${ICON_ALERT} Spin Detection Alerts:${NC}"

    python3 -c "
import json, sys, time
data = json.loads(sys.stdin.read())
for alert in data[-10:]:
    ts = time.strftime('%H:%M:%S', time.localtime(alert.get('timestamp', 0)))
    layer = alert.get('layer', 'unknown')
    zdc = alert.get('zero_delta_count', 0)
    stale = alert.get('stale_seconds', 0)
    rec = alert.get('recommendation', 'escalate')
    print(f'  {ts} {ICON_SPIN} {layer}: zero_delta={zdc}, stale={stale}s → {rec}')
" <<< "$data"
}

show_guardrails() {
    local data=$(run_observability guardrails 2>/dev/null || echo '{}')

    if [ "$data" = "{}" ]; then
        echo -e "${GREEN}No guardrail violations${NC}"
        return
    fi

    echo -e "${BOLD}${ICON_ALERT} Guardrail Violations:${NC}"

    python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
if not data:
    print('  None')
else:
    for layer, count in sorted(data.items(), key=lambda x: -x[1]):
        print(f'  {layer:25s} {count}')
" <<< "$data"
}

show_help() {
    cat <<EOF
${BOLD}Athena Health-First Dashboard${NC}

Usage: $0 [OPTIONS] [COMMAND]

Commands:
    overview      Show overall health summary (default)
    groups        Show detailed layer group health
    latency       Show latency percentiles (p50/p95/p99)
    cost          Show cost tracking per layer/model/phase
    state         Show state machine progress
    spin          Show spin detection alerts
    guardrails    Show guardrail violation counts
    full          Show all sections
    watch         Continuous refresh (every 5s)
    json          Output raw JSON for all data

Options:
    -d, --data-dir DIR    Override DATA_DIR (default: \$DATA_DIR)
    -h, --help            Show this help

Examples:
    $0                  # Overview
    $0 full             # Full dashboard
    $0 watch            # Live dashboard
    $0 latency          # Just latency
    $0 json | jq .      # Raw JSON

Environment:
    DATA_DIR              Data directory (default: /opt/athena/state)
EOF
}

main() {
    local cmd="${1:-overview}"

    case "$cmd" in
        -h|--help|help)
            show_help
            ;;
        overview)
            print_header
            show_overall_health
            echo
            show_group_health
            echo
            show_state_machine
            print_footer
            ;;
        groups)
            print_header
            show_group_health
            print_footer
            ;;
        latency)
            print_header
            show_latency
            print_footer
            ;;
        cost)
            print_header
            show_cost
            print_footer
            ;;
        state)
            print_header
            show_state_machine
            print_footer
            ;;
        spin)
            print_header
            show_spin_alerts
            print_footer
            ;;
        guardrails)
            print_header
            show_guardrails
            print_footer
            ;;
        full)
            print_header
            show_overall_health
            echo
            show_group_health
            echo
            show_latency
            echo
            show_cost
            echo
            show_state_machine
            echo
            show_spin_alerts
            echo
            show_guardrails
            print_footer
            ;;
        watch)
            while true; do
                clear
                $0 full
                sleep 5
            done
            ;;
        json)
            run_observability full
            ;;
        *)
            echo "Unknown command: $cmd"
            show_help
            exit 1
            ;;
    esac
}

main "$@"