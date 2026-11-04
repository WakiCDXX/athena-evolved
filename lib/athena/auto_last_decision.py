#!/usr/bin/env python3
"""Print last auto decision."""
import json, os, sys

session_file = os.environ.get('AUTO_SESSION_FILE', '')
try:
    with open(session_file) as f:
        d = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    d = {}
if d:
    ld = d.get('last_auto_decision', {})
    print(f'  Time: {ld.get("timestamp", "?")}')
    print(f'  Overall: {ld.get("overall", "?")}')
    print(f'  Actions: {ld.get("actions", [])}')
    print(f'  Critical: {ld.get("critical_layers", [])}')
    print(f'  Stale: {ld.get("stale_layers", [])}')
    print(f'  Concerns: {ld.get("concern_count", "?")}')
    print(f'  Tasks: {ld.get("task_count", "?")}')
