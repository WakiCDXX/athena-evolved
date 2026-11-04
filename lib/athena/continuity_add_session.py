#!/usr/bin/env python3
"""Add session to continuity state."""
import json, os, sys

state_path = os.environ.get('CONTINUITY_STATE_PATH', '')
ts = int(os.environ.get('CONTINUITY_TS', '0'))
desc = os.environ.get('CONTINUITY_DESC', '')

if not state_path:
    sys.exit(1)

try:
    with open(state_path) as f:
        data = json.load(f)
    end_time = ts
    if data['sessions']:
        data['sessions'][-1]['end'] = end_time
        data['sessions'][-1]['desc'] = desc
        data['total_uptime_s'] = data.get('total_uptime_s', 0) + end_time - data['sessions'][-1]['start']
    data['last_updated'] = end_time
    with open(state_path, 'w') as f:
        json.dump(data, f, separators=(',', ':'))
except Exception as e:
    print(f'add_session error: {e}', file=sys.stderr)
