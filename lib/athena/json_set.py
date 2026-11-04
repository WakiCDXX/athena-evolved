#!/usr/bin/env python3
"""Set a key in a JSON file."""
import json, os, sys

path = os.environ.get('JSON_SET_PATH', '')
key = os.environ.get('JSON_SET_KEY', '')
val = os.environ.get('JSON_SET_VAL', '')

if not path or not key:
    sys.exit(1)

try:
    with open(path) as f:
        data = json.load(f)
    # Parse val as JSON if possible, else treat as string
    try:
        parsed = json.loads(val)
    except:
        parsed = val
    data[key] = parsed
    with open(path, 'w') as f:
        json.dump(data, f, separators=(',', ':'))
except:
    pass
