#!/usr/bin/env python3
"""Update attention layer for volition."""
import json, os, sys

state_path = os.environ.get('INTROSPECTION_STATE_PATH', '')
question = os.environ.get('INTROSPECTION_QUESTION', '')
model_name = os.environ.get('INTROSPECTION_MODEL_NAME', '')
model_provider = os.environ.get('INTROSPECTION_MODEL_PROVIDER', '')

if not state_path:
    sys.exit(1)

try:
    with open(state_path) as f:
        attention = json.load(f)
    attention['active_task'] = 'volition-decision'
    attention['active_desc'] = question
    attention['delegated_to'] = model_name
    with open(state_path, 'w') as f:
        json.dump(attention, f, separators=(',', ':'))
except Exception as e:
    print(f'volition_attention error: {e}', file=sys.stderr)
