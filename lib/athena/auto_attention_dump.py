#!/usr/bin/env python3
"""Dump attention state with concerns and focus."""
import json, os, sys, time

attention_file = os.environ.get('AUTO_ATTENTION_FILE', '')
try:
    with open(attention_file) as f:
        d = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    d = {}

now = int(time.time())
ts = d.get('last_updated', 0) or d.get('timestamp', 0)

result = {
    'concerns': d.get('concerns', []),
    'focus': d.get('focus', ''),
    'priority': d.get('priority', 0),
    'last_updated': ts,
    'age_seconds': now - ts if ts else None,
    'fresh': (now - ts <= 300) if ts else False,
    'concern_count': len(d.get('concerns', []))
}
print(json.dumps(result))
