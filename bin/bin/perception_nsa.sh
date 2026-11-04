#!/usr/bin/bash
# perception_nsa.sh — Non-Standard Analysis perception for Athena.
# Hyperreal sensor processing with infinitesimal time steps.
#
# Usage:
#   perception_nsa.sh process <sensor.json>  → process sensor data through NSA pipeline
#   perception_nsa.sh demo                   → run demo with synthetic data
#   perception_nsa.sh read                   → print last NSA output

set -o pipefail

BASE_DIR="/root"
source "$BASE_DIR/.local/bin/athena_env.sh" 2>/dev/null

SENSOR_JSON="/opt/athena/state/sensor_input.json"
NSA_OUTPUT="/opt/athena/state/perception_nsa.json"
PYTHON_LIB="${PYTHON_LIB:-$BASE_DIR/.local/lib/python}"

case "${1:-read}" in
    process)
        input="${2:-$SENSOR_JSON}"
        echo "Processing sensor data through NSA pipeline..."
        python3 "$PYTHON_LIB/athena/hyperreal_perception.py" "$input" "$NSA_OUTPUT"
        ;;

    demo)
        echo "Generating demo sensor data..."
        python3 -c "
import json, math, random, time

# Synthetic sensor streams
streams = {
    'accelerometer_x': [math.sin(i * 0.1) + random.gauss(0, 0.01) for i in range(1000)],
    'accelerometer_y': [math.cos(i * 0.1) + random.gauss(0, 0.01) for i in range(1000)],
    'gyroscope_z': [0.5 * math.sin(i * 0.05) + random.gauss(0, 0.005) for i in range(1000)],
    'light': [100 + 50 * math.sin(i * 0.02) + random.gauss(0, 2) for i in range(1000)],
    'proximity': [max(0, 10 - i * 0.01) + random.gauss(0, 0.1) for i in range(1000)]
}

data = {
    'streams': streams,
    'emotion_events': [
        {'valence': 0.5, 'arousal': 0.3},
        {'valence': -0.2, 'arousal': 0.7},
        {'valence': 0.8, 'arousal': 0.4}
    ],
    'arousal': 0.4,
    'valence': 0.2,
    'attention': 0.7
}

with open('$SENSOR_JSON', 'w') as f:
    json.dump(data, f)

print('Demo data written to', '$SENSOR_JSON')
"
        $0 process
        ;;

    read)
        if [ -f "$NSA_OUTPUT" ]; then
            cat "$NSA_OUTPUT" | python3 -m json.tool
        else
            echo '{"error": "No NSA output found. Run process or demo first."}'
        fi
        ;;

    gradient)
        # Quick infinitesimal gradient demo
        python3 -c "
import sys
sys.path.insert(0, '$PYTHON_LIB/athena')
from hyperreal_perception import HyperrealPerception, HyperrealEmotion

hr = HyperrealPerception()

# Demo: infinitesimal delta
print('Infinitesimal delta:')
for i in range(5):
    curr = math.sin(i * 0.1)
    prev = math.sin((i-1) * 0.1) if i > 0 else 0
    delta = hr.perceive_infinitesimal_delta(curr, prev)
    print(f'  sin({i*0.1:.2f}) - sin({(i-1)*0.1:.2f}) = {delta}')

# Demo: mood gradient
print()
print('Mood gradient:')
emo = HyperrealEmotion()
for t in range(10):
    emo.update(0.1 * math.sin(t * 0.5))
print(f'  Gradient: {emo.get_gradient()}')
print(f'  Conscious feeling: {emo.conscious_feeling()}')

# Demo: hyperfinite average
print()
print('Hyperfinite average of [1,2,3,4,5]:')
vals = [1,2,3,4,5]
avg = hr.hyperfinite_average(vals)
print(f'  Result: {avg}')
"
        ;;

    *)
        echo "usage: $0 {process [input.json]|demo|read|gradient}" >&2
        exit 1
        ;;
esac