#!/usr/bin/env python3
"""Add a doubt entry to the doubt log."""
import json, os, sys

doubt_path = os.environ.get('DOUBT_PATH', '')
category = os.environ.get('DOUBT_CATEGORY', '')
detail = os.environ.get('DOUBT_DETAIL', '')
level = os.environ.get('DOUBT_LEVEL', '5')
ts = os.environ.get('DOUBT_TS', '0')

if not doubt_path or not category:
    sys.exit(1)

try:
    with open(doubt_path) as f:
        data = json.load(f)
except:
    data = {'confidence': 0.8, 'calibration_log': []}

entry = {'category': category, 'detail': detail, 'level': int(level), 'ts': int(ts)}
if 'entries' not in data:
    data['entries'] = []
data['entries'].append(entry)

# Adjust confidence based on doubt level (higher doubt = lower confidence)
try:
    delta = (int(level) - 5) * 0.05
    data['confidence'] = max(0.0, min(1.0, data.get('confidence', 0.8) - delta))
except:
    pass

data['last_updated'] = int(ts)

try:
    with open(doubt_path, 'w') as f:
        json.dump(data, f, separators=(',', ':'))
except:
    pass
