#!/usr/bin/env python3
"""Record a screen event to the event log."""
import json
import os
import sys
import time

event = os.environ.get('VIEW_EVENT', '')
hash_val = os.environ.get('VIEW_HASH', '')
log_file = os.environ.get('VIEW_LOG_FILE', '')

entry = {'event': event, 'hash': hash_val, 'timestamp': time.time()}

try:
    with open(log_file, 'a') as f:
        f.write(json.dumps(entry) + '\n')
except Exception:
    pass
