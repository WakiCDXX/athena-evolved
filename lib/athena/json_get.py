#!/usr/bin/env python3
"""Get a value from a JSON file by key."""
import json, os, sys

path = os.environ.get('JSON_GET_PATH', '')
key = os.environ.get('JSON_GET_KEY', '')

if not path or not key:
    print('')
    sys.exit(1)

try:
    with open(path) as f:
        data = json.load(f)
    val = data.get(key)
    if val is None:
        print('')
    elif isinstance(val, bool):
        print('true' if val else 'false')
    elif isinstance(val, (int, float)):
        print(val)
    else:
        print(val)
except:
    print('')
