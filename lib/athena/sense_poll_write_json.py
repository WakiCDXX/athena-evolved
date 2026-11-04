#!/usr/bin/env python3
"""Write senses.json from senses.log."""
import json, os, sys

log_path = os.environ.get('SENSES_LOG_PATH', '')
json_path = os.environ.get('SENSES_JSON_PATH', '')

try:
    with open(log_path) as f:
        lines = [l.strip() for l in f if l.strip()]
    if not lines:
        sys.exit(0)
    d = json.loads(lines[-1])
    bat = d.get('battery', {})
    summary = {
        'layer': 'senses',
        'battery': bat.get('percentage', d.get('battery_pct', 0)),
        'temperature': bat.get('temperature', 0),
        'motion': 'stationary',
        'last_updated': d.get('ts', 0)
    }
    tmp = json_path + '.tmp'
    with open(tmp, 'w') as f:
        json.dump(summary, f, separators=(',', ':'))
    os.replace(tmp, json_path)
except Exception:
    pass
