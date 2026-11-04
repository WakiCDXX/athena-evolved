#!/usr/bin/env python3
"""Consolidate doubt state from volition."""
import json, os, sys

doubt_path = os.environ.get('DOUBT_PATH', '')
volition_path = os.environ.get('VOLITION_PATH', '')

if not os.path.exists(volition_path) or os.path.getsize(volition_path) == 0:
    sys.exit(0)

with open(volition_path) as f:
    volition = json.load(f)

doubt_data = {'confidence': 0.8, 'last_updated': int(os.environ.get('DOUBT_TS', 0)), 'last_query': volition.get('last_decision', {}).get('type', 'unknown')}
try:
    with open(doubt_path) as f:
        existing = json.load(f)
    doubt_data['calibration_log'] = existing.get('calibration_log', [])
    doubt_data['confidence'] = existing.get('confidence', 0.8)
except:
    pass

with open(doubt_path, 'w') as f:
    json.dump(doubt_data, f, separators=(',', ':'))
