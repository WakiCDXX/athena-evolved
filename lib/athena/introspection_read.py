#!/usr/bin/env python3
"""Update introspection state timestamp and print full state."""
import json, os, time, sys

state_path = os.environ.get('INTROSPECTION_STATE_PATH', '')
if not state_path:
    sys.exit(1)

try:
    with open(state_path) as f:
        state = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    state = {}
state['last_updated'] = int(time.time())
try:
    with open(state_path, 'w') as f:
        json.dump(state, f, separators=(',', ':'))
    print(json.dumps(state, indent=2))
except Exception as e:
    print(f'introspection_read error: {e}', file=sys.stderr)
