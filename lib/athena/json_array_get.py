#!/usr/bin/env python3
"""Get a comma-joined string from a JSON array key."""
import json, os, sys

path = os.environ.get('JSON_ARRAY_GET_PATH', '')
key = os.environ.get('JSON_ARRAY_GET_KEY', '')

if not path or not key:
    print('')
    sys.exit(1)

try:
    with open(path) as f:
        data = json.load(f)
    arr = data.get(key, [])
    print(','.join(str(x) for x in arr))
except:
    print('')
