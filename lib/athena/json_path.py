#!/usr/bin/env python3
"""Get a nested value from JSON state using dot-notation path."""
import json, os, sys

state_path = os.environ.get('ATHENA_STATE_PATH', '')
path = os.environ.get('ATHENA_STATE_PATH_NESTED', '')
default = os.environ.get('ATHENA_STATE_DEFAULT', '')

if not state_path or not path:
    print(default)
    sys.exit(1)

try:
    with open(state_path) as f:
        data = json.load(f)
    parts = path.split('.')
    val = data
    for p in parts:
        if isinstance(val, dict):
            val = val.get(p)
        elif isinstance(val, list):
            val = val[int(p)] if p.isdigit() and int(p) < len(val) else None
        else:
            val = None
            break
    if val is None:
        print(default)
    elif isinstance(val, (str, int, float, bool)):
        print(val)
    else:
        print(json.dumps(val))
except:
    print(default)
