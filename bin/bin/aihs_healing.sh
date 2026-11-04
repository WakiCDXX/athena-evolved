#!/usr/bin/bash
# aihs_healing.sh — AIHS Healing Daemons for Athena.
# Alien Medicine analogue: Autonomous Integrated Healing System per layer.
# Each layer gets a healing daemon with homeostatic setpoints (bioelectric Vmem targets).
#
# Usage:
#   aihs_healing.sh health          → show system health summary
#   aihs_healing.sh heal            → run one healing cycle for all layers
#   aihs_healing.sh layer <name>    → show/heal specific layer
#   aihs_healing.sh daemon [interval] → run continuous healing daemon
#   aihs_healing.sh demo            → run demonstration
#   aihs_healing.sh read            → print healing state

set -o pipefail

BASE_DIR="/root"
source "$BASE_DIR/.local/bin/athena_env.sh" 2>/dev/null

AIHS_STATE="/opt/athena/state/aihs_state.json"
PYTHON_LIB="${PYTHON_LIB:-$BASE_DIR/.local/lib/python}"

case "${1:-read}" in
    health)
        echo "AIHS System Health Check..."
        python3 -c "
import json, sys, os
sys.path.insert(0, '$PYTHON_LIB/athena')
from aihs_healing import AIHSOrchestrator

orchestrator = AIHSOrchestrator()

if os.path.exists('$AIHS_STATE'):
    with open('$AIHS_STATE') as f:
        data = json.load(f)
    for name, layer_data in data.get('layers', {}).items():
        if name in orchestrator.daemons:
            for h in layer_data.get('healing_history', []):
                orchestrator.daemons[name].healing_history.append(type('obj', (object,), h)())

result = orchestrator.get_system_health()
print(json.dumps(result, indent=2))

# Save state
with open('$AIHS_STATE', 'w') as f:
    json.dump(orchestrator.export_state(), f, separators=(',', ':'))
"
        ;;

    heal)
        echo "Running AIHS healing cycle..."
        python3 -c "
import json, sys, os
sys.path.insert(0, '$PYTHON_LIB/athena')
from aihs_healing import AIHSOrchestrator

orchestrator = AIHSOrchestrator()

if os.path.exists('$AIHS_STATE'):
    with open('$AIHS_STATE') as f:
        data = json.load(f)
    for name, layer_data in data.get('layers', {}).items():
        if name in orchestrator.daemons:
            for h in layer_data.get('healing_history', []):
                orchestrator.daemons[name].healing_history.append(type('obj', (object,), h)())

events = orchestrator.heal_all_layers()

result = {
    'healed': len(events),
    'events': [
        {'layer': e.layer, 'action': e.action.value, 'success': e.success, 'reason': e.reason}
        for e in events
    ]
}
print(json.dumps(result, indent=2))

with open('$AIHS_STATE', 'w') as f:
    json.dump(orchestrator.export_state(), f, separators=(',', ':'))
"
        ;;

    layer)
        if [ -z "$2" ]; then
            echo "usage: \$0 layer <layer_name>" >&2
            exit 1
        fi
        python3 -c "
import json, sys, os
sys.path.insert(0, '$PYTHON_LIB/athena')
from aihs_healing import AIHSOrchestrator

orchestrator = AIHSOrchestrator()

if os.path.exists('$AIHS_STATE'):
    with open('$AIHS_STATE') as f:
        data = json.load(f)
    for name, layer_data in data.get('layers', {}).items():
        if name in orchestrator.daemons:
            for h in layer_data.get('healing_history', []):
                orchestrator.daemons[name].healing_history.append(type('obj', (object,), h)())

daemon = orchestrator.daemons.get('$2')
if not daemon:
    print(json.dumps({'error': 'Unknown layer: $2'}))
    sys.exit(1)

# Run heal for this layer
event = daemon.heal()

print(json.dumps({
    'layer': '$2',
    'health': daemon.state.health.value,
    'anomaly': daemon.state.anomaly_score,
    'metrics': {
        'cpu': daemon.state.cpu_percent,
        'mem': daemon.state.mem_mb,
        'latency': daemon.state.latency_ms,
        'errors': daemon.state.error_rate,
        'throughput': daemon.state.throughput,
        'vmem': daemon.state.vmem
    },
    'setpoint': {
        'cpu': daemon.setpoint.cpu_target,
        'mem': daemon.setpoint.mem_target,
        'latency': daemon.setpoint.latency_target,
        'errors': daemon.setpoint.error_rate_target,
        'vmem': daemon.setpoint.vmem_target
    },
    'healing_action': {
        'action': event.action.value if event else 'none',
        'success': event.success if event else None,
        'reason': event.reason if event else None
    } if event else None
}, indent=2))
"
        ;;

    daemon)
        interval="${2:-30}"
        echo "Starting AIHS healing daemon (interval: ${interval}s)..."
        python3 -c "
import json, sys, time, signal
sys.path.insert(0, '$PYTHON_LIB/athena')
from aihs_healing import AIHSOrchestrator

orchestrator = AIHSOrchestrator()
orchestrator.cycle_interval = $interval

if os.path.exists('$AIHS_STATE'):
    with open('$AIHS_STATE') as f:
        data = json.load(f)
    for name, layer_data in data.get('layers', {}).items():
        if name in orchestrator.daemons:
            for h in layer_data.get('healing_history', []):
                orchestrator.daemons[name].healing_history.append(type('obj', (object,), h)())

def save_and_exit(signum, frame):
    print('\\nShutting down AIHS daemon...')
    with open('$AIHS_STATE', 'w') as f:
        json.dump(orchestrator.export_state(), f, separators=(',', ':'))
    sys.exit(0)

signal.signal(signal.SIGINT, save_and_exit)
signal.signal(signal.SIGTERM, save_and_exit)

orchestrator.run_daemon()
"
        ;;

    demo)
        echo "Running AIHS Healing Daemons demo..."
        python3 "$PYTHON_LIB/athena/aihs_healing.py" demo
        ;;

    read)
        if [ -f "$AIHS_STATE" ]; then
            cat "$AIHS_STATE" | python3 -m json.tool
        else
            echo '{"error": "No AIHS state found. Run health or heal first."}'
        fi
        ;;

    *)
        echo "usage: \$0 {health|heal|layer <name>|daemon [interval]|demo|read}" >&2
        exit 1
        ;;
esac