#!/usr/bin/env python3
"""Format heartbeat alerts for display."""
import json, os, sys

path = os.environ.get('JSON_GET_PATH', '')
key = os.environ.get('JSON_GET_KEY', '')

try:
    with open(path) as f:
        data = json.load(f)
    alerts = data.get(key, [])
    if not alerts:
        print("No active alerts.")
        sys.exit(0)
    for a in alerts:
        status = a.get('status', 'unknown')
        layer = a.get('layer', 'unknown')
        age = a.get('age_seconds', 0)
        if status == 'critical':
            print(f"\U0001f534 CRITICAL: {layer} is {age}s stale")
        elif status == 'stale':
            print(f"\u26a0\ufe0f  STALE: {layer} is {age}s stale")
except:
    print("No heartbeat data yet.")
