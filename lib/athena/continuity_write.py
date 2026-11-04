#!/usr/bin/env python3
"""Write continuity JSON fields."""
import json, os, sys

state_path = os.environ.get('CONTINUITY_STATE_PATH', '')
field = os.environ.get('CONTINUITY_FIELD', '')
field_json = os.environ.get('CONTINUITY_FIELD_JSON', '')

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
