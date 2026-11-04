#!/usr/bin/env python3
"""Dump volition state with decision context."""
import json, os, sys, time

volition_file = os.environ.get('AUTO_VOLITION_FILE', '')
try:
    with open(volition_file) as f:
        d = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    d = {}

now = int(time.time())
ts = d.get('timestamp', 0)

result = {
    'banked': d.get('banked', False),
    'timestamp': ts,
    'age_seconds': now - ts if ts else None,
    'decisions': d.get('decisions', []),
    'intent': d.get('intent', ''),
    'goals': d.get('goals', []),
    'constraints': d.get('constraints', [])
}
print(json.dumps(result))
