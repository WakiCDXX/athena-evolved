#!/usr/bin/env python3
"""Get current concerns from attention.json."""
import json, os, sys

attention_file = os.environ.get('AUTO_ATTENTION_FILE', '')
try:
    with open(attention_file) as f:
        d = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    d = {}
print(d.get('concerns', []))
