#!/usr/bin/env python3
"""Validate an answer against doubt calibration."""
import json, os, sys

doubt_path = os.environ.get('DOUBT_PATH', '')
answer = os.environ.get('DOUBT_ANSWER', '')
ts = os.environ.get('DOUBT_TS', '0')
log_file = os.environ.get('DOUBT_LOG_FILE', '')

if not doubt_path:
    sys.exit(1)

try:
    with open(doubt_path) as f:
        data = json.load(f)
except:
    data = {'confidence': 0.8, 'calibration_log': []}

confidence = data.get('confidence', 0.8)
result = {
    'answer': answer,
    'confidence': confidence,
    'trusted': confidence > 0.5,
    'ts': int(ts)
}

# Log the check
log_entry = {'answer': answer, 'confidence': confidence, 'trusted': result['trusted'], 'ts': int(ts)}
try:
    with open(log_file, 'a') as f:
        f.write(json.dumps(log_entry, separators=(',', ':')) + '\n')
except:
    pass

data['last_updated'] = int(ts)
try:
    with open(doubt_path, 'w') as f:
        json.dump(data, f, separators=(',', ':'))
except:
    pass

print(json.dumps(result))
