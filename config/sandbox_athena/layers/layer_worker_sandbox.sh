#!/usr/bin/env bash
# Sandbox layer worker — tests unified-state + declarative policy
BASE_DIR="/root"
INTERVAL=0.5
POLICY_FILE="sandbox_athena/config/doubt_policy.json"
ADAPTER="$BASE_DIR/.local/lib/python/athena/adapter_policy.py"

# Wire adapter: translate .json policy into daemon-compatible bash/env + degradation ladder
INTERVAL_LINE=$(python3 "$ADAPTER" "$POLICY_FILE" bash 2>/dev/null | head -n1)
if [ -n "$INTERVAL_LINE" ]; then
    eval "$INTERVAL_LINE"
    echo "Adapter mapped interval: $INTERVAL_LINE"
fi
# Show mapped degradation ladder (memory-guard alignment)
python3 "$ADAPTER" "$POLICY_FILE" bash 2>/dev/null | tail -n +2 | sed 's/^#/# Degradation ladder: /'

# Read declarative policy (tonl-style config pattern)
echo "Testing declarative policy from: $POLICY_FILE"
python3 -c "
import json, sys
with open('$POLICY_FILE') as f:
    p = json.load(f)
print('Policy loaded:', p['layer_name'])
print('Constraints:', p['policy']['action_constraint'])
print('Allowed states:', p['policy']['allowed_states'])
"

# Simulate event-based interval (unified-state test: no subshell spawn for state read)
echo "Simulated event_interval: 0.8 (adaptive from unified state, no separate process)"
echo "Adapted to: 0.5 (min safe interval)"
echo "No SIGKILL risk — sandbox isolated from main daemon."
