#!/usr/bin/env python3
"""Dump senses state with environmental context."""
import json, os, sys, time

senses_file = os.environ.get('AUTO_SENSES_FILE', '')
try:
    with open(senses_file) as f:
        d = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    d = {}

now = int(time.time())
ts = d.get('last_updated', 0)

result = {
    'layer': d.get('layer', 'senses'),
    'battery': d.get('battery', None),
    'temperature': d.get('temperature', None),
    'motion': d.get('motion', ''),
    'last_updated': ts,
    'age_seconds': now - ts if ts else None,
    'fresh': (now - ts <= 120) if ts else False
}
print(json.dumps(result))
