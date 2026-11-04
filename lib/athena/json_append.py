#!/usr/bin/env python3
"""Append to a JSON array in a state file."""
import json, os, sys

state_path = os.environ.get('ATHENA_STATE_PATH', '')
key = os.environ.get('ATHENA_STATE_KEY', '')
val = os.environ.get('ATHENA_STATE_VAL', '')

if not state_path or not key:
    sys.exit(1)

try:
    with open(state_path) as f:
        data = json.load(f)
except:
    data = {}

arr = data.get(key, [])
# Try to parse val as JSON
try:
    parsed = json.loads(val)
except (json.JSONDecodeError, ValueError):
    parsed = val
arr.append(parsed)
data[key] = arr
with open(state_path, 'w') as f:
    json.dump(data, f, separators=(',', ':'))
