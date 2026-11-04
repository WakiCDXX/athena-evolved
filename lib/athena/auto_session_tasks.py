#!/usr/bin/env python3
"""Get pending tasks with priority and staleness info."""
import json, os, sys, time

session_file = os.environ.get('AUTO_SESSION_FILE', '')
try:
    with open(session_file) as f:
        d = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    d = {}

now = int(time.time())
tasks = d.get('pending_tasks', [])
result = {
    'task_count': len(tasks),
    'tasks': [],
    'stale_count': 0
}
for t in tasks:
    age = now - t.get('created', 0) if t.get('created') else None
    stale = age is not None and age > 3600
    if stale:
        result['stale_count'] += 1
    result['tasks'].append({
        'id': t.get('id', ''),
        'action': t.get('action', ''),
        'layer': t.get('layer', ''),
        'priority': t.get('priority', 0),
        'created': t.get('created', 0),
        'age_seconds': age,
        'stale': stale
    })
print(json.dumps(result))
