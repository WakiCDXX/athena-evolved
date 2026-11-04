#!/usr/bin/env python3
"""Get timestamp from the structured state file."""
import json
import os
import sys

state_file = os.environ.get('VIEW_STRUCTURED_STATE_FILE', '')

try:
    with open(state_file) as f:
        data = json.load(f)
    print(data.get('timestamp', 0))
except Exception:
    print(0)
