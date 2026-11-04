#!/usr/bin/env python3
"""Dump continuity.json content."""
import json, os, sys

continuity_file = os.environ.get('AUTO_CONTINUITY_FILE', '')
try:
    with open(continuity_file) as f:
        d = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    d = {}
print(json.dumps(d))
