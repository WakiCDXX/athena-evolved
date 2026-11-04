#!/usr/bin/env python3
"""Process auto triggers from trigger file."""
import json, os, sys

trigger_file = os.environ.get('AUTO_TRIGGER_FILE', '')
data_dir = os.environ.get('AUTO_DATA_DIR', '')

triggers = {}
try:
    with open(trigger_file) as f:
        triggers = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    pass

for name, value in triggers.get('triggers', {}).items():
    print(f'  {name} -> {value}')
