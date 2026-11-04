#!/usr/bin/env python3
"""Write a field to vera_cpu.json."""
import json, os, sys

state_path = os.environ.get('VERA_CPU_STATE_PATH', '')
field = os.environ.get('VERA_CPU_FIELD', '')
field_json = os.environ.get('VERA_CPU_FIELD_JSON', '')

if not state_path or not field or not field_json:
    sys.exit(1)

try:
    with open(state_path) as f:
        data = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    data = {}
data[field] = json.loads(field_json)
with open(state_path, 'w') as f:
    json.dump(data, f, separators=(',', ':'))