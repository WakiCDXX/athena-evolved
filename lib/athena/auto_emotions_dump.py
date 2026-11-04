#!/usr/bin/env python3
"""Dump emotions state with mood summary."""
import json, os, sys, time

emotions_file = os.environ.get('AUTO_EMOTIONS_FILE', '')
try:
    with open(emotions_file) as f:
        d = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    d = {}

now = int(time.time())
ts = d.get('last_updated', 0) or d.get('timestamp', 0)

result = {
    'mood': d.get('mood', ''),
    'valence': d.get('valence', 0),
    'arousal': d.get('arousal', 0),
    'dominant_emotion': d.get('dominant_emotion', ''),
    'emotions': d.get('emotions', {}),
    'last_updated': ts,
    'age_seconds': now - ts if ts else None,
    'fresh': (now - ts <= 300) if ts else False
}
print(json.dumps(result))
