#!/usr/bin/env python3
"""Voice mode interaction handler."""
import json, os, sys

action = os.environ.get('INTERACT_ACTION', '')
text = os.environ.get('INTERACT_TEXT', '')
session_file = os.environ.get('INTERACT_SESSION', '')

# Process voice input and return response
result = {
    'action': action,
    'input': text,
    'session': session_file,
    'ts': int(os.environ.get('INTERACT_TS', 0))
}
print(json.dumps(result, indent=2))
