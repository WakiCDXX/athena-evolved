#!/usr/bin/env python3
"""Print introspection query history."""
import json, os, sys

state_path = os.environ.get('INTROSPECTION_STATE_PATH', '')

try:
    with open(state_path) as f:
        state = json.load(f)
    for q in state.get('queries', []):
        print(f"[{q['ts']}] {q['question']}")
except:
    print('No query history yet.')
