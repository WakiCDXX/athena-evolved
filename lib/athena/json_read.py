#!/usr/bin/env python3
"""Read a key from a JSON file and print it."""
import json, os, sys

path = os.environ.get('ATHENA_READ_PATH', '')
key = os.environ.get('ATHENA_READ_KEY', '')

try:
    with open(path) as f:
        data = json.load(f)
    if key:
        print(json.dumps(data.get(key, [])))
    else:
        print(json.dumps(data))
except:
    print('{}' if key else '[]')
