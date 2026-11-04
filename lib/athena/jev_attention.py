#!/usr/bin/env python3
"""Update attention layer for Jev."""
import json, os, sys

state_path = os.environ.get('INTROSPECTION_STATE_PATH', '')
question = os.environ.get('INTROSPECTION_QUESTION_JEV', '')

if not state_path:
    sys.exit(1)
try:
    with open(state_path) as f:
        attention = json.load(f)
    attention['active_task'] = 'jev-decision'
    attention['active_desc'] = question
    attention['delegated_to'] = 'jev'
    with open(state_path, 'w') as f:
        json.dump(attention, f, separators=(',', ':'))
except:
    pass
