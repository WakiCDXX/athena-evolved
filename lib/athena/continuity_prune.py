#!/usr/bin/env python3
"""Prune continuity state."""
import json, os, sys

state_path = os.environ.get('CONTINUITY_STATE_PATH', '')
ts = int(os.environ.get('CONTINUITY_TS', '0'))
max_s = int(os.environ.get('CONTINUITY_MAX_SESSIONS', '50'))

if not state_path:
    sys.exit(1)

try:
    with open(state_path) as f:
        data = json.load(f)
    if len(data['sessions']) > max_s:
        data['sessions'] = data['sessions'][-max_s:]
    if len(data.get('narrative_thread', [])) > 100:
        data['narrative_thread'] = data['narrative_thread'][-100:]
    data['last_updated'] = ts
    with open(state_path, 'w') as f:
        json.dump(data, f, separators=(',', ':'))
except Exception as e:
    print(f'prune error: {e}', file=sys.stderr)
