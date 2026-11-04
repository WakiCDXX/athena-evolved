#!/usr/bin/env python3
"""Get the focused node's text from the structured state file."""
import json
import os
import sys

state_file = os.environ.get('VIEW_STRUCTURED_STATE_FILE', '')

try:
    with open(state_file) as f:
        state = json.load(f)
    focused = state.get('focused_node', {})
    if isinstance(focused, dict):
        print(focused.get('text', ''))
    else:
        print('')
except Exception:
    print('')
