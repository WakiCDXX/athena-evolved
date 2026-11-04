#!/usr/bin/env python3
"""Initialize doubt state file."""
import json, os, sys

path = os.environ.get('JSON_INIT_PATH', '')
ts = os.environ.get('JSON_INIT_TS', '0')

if not path:
    sys.exit(1)

if os.path.exists(path):
    sys.exit(0)

data = {
    'decisions': [],
    'calibration_log': [],
    'last_updated': int(ts)
}

try:
    with open(path, 'w') as f:
        json.dump(data, f, separators=(',', ':'))
except:
    pass
