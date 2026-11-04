#!/usr/bin/env python3
"""Set a JSON array key from comma-separated env var values."""
import json, os, sys

path = os.environ.get('JSON_ARRAY_SET_PATH', '')
key = os.environ.get('JSON_ARRAY_SET_KEY', '')
values = os.environ.get('JSON_ARRAY_SET_VALUES', '')

if not path or not key:
    sys.exit(1)

try:
    with open(path) as f:
        data = json.load(f)
    if values:
        data[key] = [v.strip() for v in values.split(',') if v.strip()]
    else:
        data[key] = []
    with open(path, 'w') as f:
        json.dump(data, f, separators=(',', ':'))
except:
    pass
