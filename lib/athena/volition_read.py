#!/usr/bin/env python3
"""Read volition state and update timestamp."""
import json, os, time

state_path = os.environ.get('VOLITION_STATE_PATH', '')
if not state_path:
    print('{}')
    import sys
    sys.exit(1)

try:
    with open(state_path) as f:
        d = json.load(f)
    d['last_updated'] = int(time.time())
    with open(state_path, 'w') as f:
        json.dump(d, f, separators=(',',':'))
    print(json.dumps(d.get('last_decision', {}), indent=2))
except:
    print('No decision recorded yet.')
