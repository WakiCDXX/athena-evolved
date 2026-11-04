#!/usr/bin/env python3
"""Bootstrap continuity state for new session."""
import json, os, sys

state_path = os.environ.get('CONTINUITY_STATE_PATH', '')
ts = int(os.environ.get('CONTINUITY_TS', '0'))

if not state_path:
    sys.exit(1)

try:
    with open(state_path) as f:
        data = json.load(f)
    data['session_count'] = data.get('session_count', 0) + 1
    session_id = data['session_count']
    if not data.get('first_session'):
        data['first_session'] = ts
    data['last_session'] = ts
    data['sessions'].append({'id': session_id, 'start': ts, 'end': None, 'desc': None})
    data['last_updated'] = ts
    with open(state_path, 'w') as f:
        json.dump(data, f, separators=(',', ':'))
    print(f'Session {session_id} started')
except Exception as e:
    print(f'bootstrap error: {e}', file=sys.stderr)
