#!/usr/bin/env python3
"""Get a single scalar value from JSON state."""
import json, os, sys

state_path = os.environ.get('ATHENA_STATE_PATH', '')
key = os.environ.get('ATHENA_STATE_KEY', '')

if not state_path or not key:
    print('')
    sys.exit(1)

try:
    with open(state_path) as f:
        data = json.load(f)
    val = data.get(key)
    if val is None:
        print('')
    elif isinstance(val, bool):
        print('true' if val else 'false')
    elif isinstance(val, (int, float)):
        print(val)
    else:
        print(str(val))
except:
    print('')
