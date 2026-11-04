#!/usr/bin/env python3
"""Dump doubt state with confidence metrics."""
import json, os, sys, time

doubt_file = os.environ.get('AUTO_DOUBT_FILE', '')
try:
    with open(doubt_file) as f:
        d = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    d = {}

now = int(time.time())
ts = d.get('timestamp', 0) or d.get('last_updated', 0)

result = {
    'confidence': d.get('confidence', 0),
    'uncertainty': d.get('uncertainty', 0),
    'doubt_level': d.get('doubt_level', 'none'),
    'reasons': d.get('reasons', []),
    'timestamp': ts,
    'age_seconds': now - ts if ts else None,
    'fresh': (now - ts <= 300) if ts else False,
    'model_used': d.get('model_used', 'cohere/north-mini-code:free')
}
print(json.dumps(result))
