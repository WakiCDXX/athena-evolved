#!/usr/bin/env python3
"""Dump memory state with consolidation summary."""
import json, os, sys, time

memory_file = os.environ.get('AUTO_MEMORY_FILE', '')
try:
    with open(memory_file) as f:
        d = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    d = {}

now = int(time.time())
ts = d.get('last_updated', 0) or d.get('timestamp', 0)

result = {
    'consolidated': d.get('consolidated', []),
    'recent': d.get('recent', []),
    'episodes': d.get('episodes', []),
    'last_updated': ts,
    'age_seconds': now - ts if ts else None,
    'fresh': (now - ts <= 600) if ts else False,
    'consolidated_count': len(d.get('consolidated', []))
}
print(json.dumps(result))
