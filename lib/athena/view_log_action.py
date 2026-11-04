#!/usr/bin/env python3
"""Log an action proposal to the action log file."""
import json
import os
import sys
import time

action = os.environ.get('VIEW_ACTION', '')
target = os.environ.get('VIEW_TARGET', '')
detail = os.environ.get('VIEW_DETAIL', '')
validation = os.environ.get('VIEW_VALIDATION', '{}')
action_log = os.environ.get('VIEW_ACTION_LOG', '')

entry = {
    'action': action,
    'target': target,
    'detail': detail,
    'timestamp': time.time(),
    'validation': json.loads(validation) if validation else {}
}

try:
    with open(action_log, 'a') as f:
        f.write(json.dumps(entry) + '\n')
except Exception:
    pass

print(json.dumps(entry, indent=2))
