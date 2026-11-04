#!/usr/bin/env python3
"""Print a JSON value to stdout."""
import json, os, sys

data_path = os.environ.get('ATHENA_DATA_PATH', '')
key = os.environ.get('ATHENA_DATA_KEY', '')

if not data_path or not key:
    print('{}')
    sys.exit(1)

try:
    with open(data_path) as f:
        data = json.load(f)
    val = data.get(key, [])
    print(json.dumps(val))
except:
    print('[]')
