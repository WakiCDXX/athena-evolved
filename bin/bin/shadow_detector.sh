#!/usr/bin/bash
# shadow_detector.sh — Shadow Process Detector for Athena.
# Alien Chemistry analogue: Shadow biosphere detection for unknown metabolic pathways.
#
# Usage:
#   shadow_detector.sh scan         → single scan for shadow processes
#   shadow_detector.sh baseline [s] → establish resource baseline (default 60s)
#   shadow_detector.sh monitor      → continuous monitoring
#   shadow_detector.sh history      → show detection history
#   shadow_detector.sh signatures   → show known process signatures
#   shadow_detector.sh demo         → run demonstration
#   shadow_detector.sh read         → print detector state

set -o pipefail

BASE_DIR="/root"
source "$BASE_DIR/.local/bin/athena_env.sh" 2>/dev/null

SHADOW_STATE="/opt/athena/state/shadow_state.json"
PYTHON_LIB="${PYTHON_LIB:-$BASE_DIR/.local/lib/python}"

case "${1:-read}" in
    scan)
        echo "Scanning for shadow processes..."
        python3 -c "
import json, sys, os
sys.path.insert(0, '$PYTHON_LIB/athena')
from shadow_detector import ShadowDetector

detector = ShadowDetector()

if os.path.exists('$SHADOW_STATE'):
    with open('$SHADOW_STATE') as f:
        data = json.load(f)
    detector.import_state(data)

detections = detector.scan_once()

result = {
    'detections': [
        {
            'pid': d.pid,
            'category': d.category.value,
            'confidence': d.confidence,
            'evidence': d.evidence,
            'mitigation': d.mitigation_suggestion,
            'command': d.process_info.get('command', '')
        }
        for d in detections
    ]
}

print(json.dumps(result, indent=2))

# Save state
with open('$SHADOW_STATE', 'w') as f:
    json.dump(detector.export_state(), f, separators=(',', ':'))
"
        ;;

    baseline)
        duration="${2:-60}"
        echo "Establishing baseline over ${duration}s..."
        python3 -c "
import json, sys
sys.path.insert(0, '$PYTHON_LIB/athena')
from shadow_detector import ShadowDetector

detector = ShadowDetector()
detector.establish_baseline($duration)

with open('$SHADOW_STATE', 'w') as f:
    json.dump(detector.export_state(), f, separators=(',', ':'))

print(json.dumps(detector.export_state()['baseline'], indent=2))
"
        ;;

    monitor)
        echo "Starting continuous shadow monitoring (Ctrl+C to stop)..."
        python3 -c "
import json, sys, time
sys.path.insert(0, '$PYTHON_LIB/athena')
from shadow_detector import ShadowDetector

detector = ShadowDetector()

if os.path.exists('$SHADOW_STATE'):
    with open('$SHADOW_STATE') as f:
        data = json.load(f)
    detector.import_state(data)

print('Monitoring started...')
try:
    while True:
        detections = detector.scan_once()
        if detections:
            print(f'[{time.strftime(\"%H:%M:%S\")}] {len(detections)} detection(s):')
            for d in detections:
                cmd = d.process_info.get('command', '')[:60]
                print(f'  PID {d.pid}: {d.category.value} ({d.confidence:.2f}) - {cmd}')
        time.sleep(5)
except KeyboardInterrupt:
    print('\\nMonitoring stopped.')

with open('$SHADOW_STATE', 'w') as f:
    json.dump(detector.export_state(), f, separators=(',', ':'))
"
        ;;

    history)
        python3 -c "
import json, sys, os
sys.path.insert(0, '$PYTHON_LIB/athena')
from shadow_detector import ShadowDetector

detector = ShadowDetector()

if os.path.exists('$SHADOW_STATE'):
    with open('$SHADOW_STATE') as f:
        data = json.load(f)
    detector.import_state(data)

# Show last 20 detections
detections = detector.get_detections(0)
print(json.dumps({
    'total_detections': len(detections),
    'recent': [
        {
            'pid': d.pid,
            'category': d.category.value,
            'confidence': d.confidence,
            'evidence': d.evidence,
            'timestamp': d.timestamp,
            'mitigation': d.mitigation_suggestion
        }
        for d in detections[-20:]
    ]
}, indent=2))
"
        ;;

    signatures)
        python3 -c "
import json, sys
sys.path.insert(0, '$PYTHON_LIB/athena')
from shadow_detector import ShadowDetector

detector = ShadowDetector()
print(json.dumps(detector.export_state()['known_signatures'], indent=2))
"
        ;;

    demo)
        echo "Running Shadow Process Detector demo..."
        python3 "$PYTHON_LIB/athena/shadow_detector.py" demo
        ;;

    read)
        if [ -f "$SHADOW_STATE" ]; then
            cat "$SHADOW_STATE" | python3 -m json.tool
        else
            echo '{"error": "No shadow state found. Run baseline or scan first."}'
        fi
        ;;

    *)
        echo "usage: \$0 {scan|baseline [seconds]|monitor|history|signatures|demo|read}" >&2
        exit 1
        ;;
esac