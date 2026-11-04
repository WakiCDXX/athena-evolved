#!/usr/bin/env python3
"""Update memory.json timestamp and print contents."""
import json, os, time, sys

state_path = os.environ.get('MEMORY_CONSOLIDATE_PATH', '')
if not state_path:
    sys.exit(1)

try:
    with open(state_path) as f:
        d = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    d = {'memory_files': 0}
d['last_updated'] = int(time.time())
with open(state_path, 'w') as f:
    json.dump(d, f, separators=(',', ':'))
print(json.dumps(d))
