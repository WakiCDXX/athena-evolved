#!/usr/bin/env python3
"""Show all triggers from trigger file."""
import json, os, sys

trigger_file = os.environ.get('AUTO_TRIGGER_FILE', '')
try:
    with open(trigger_file) as f:
        d = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    d = {}
for k, v in d.get('triggers', {}).items():
    print(f'  {k} -> {v}')
