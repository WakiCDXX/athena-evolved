#!/usr/bin/env python3
"""Get session state summary."""
import json, os, sys, time

session_file = os.environ.get('AUTO_SESSION_FILE', '')
try:
    with open(session_file) as f:
        d = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    d = {}

now = int(time.time())
last_run = d.get('last_auto_run', 0)
last_decision = d.get('last_auto_decision', {})

result = {
    'session_start': d.get('session_start', ''),
    'layers': d.get('layers', []),
    'pending_tasks': d.get('pending_tasks', []),
    'last_auto_run': last_run,
    'last_auto_run_age': now - last_run if last_run else None,
    'last_decision': last_decision.get('overall', 'unknown'),
    'last_decision_time': last_decision.get('timestamp', 0),
    'needs_attention': last_decision.get('needs_attention', False),
    'data_dir': d.get('data_dir', '')
}
print(json.dumps(result))
