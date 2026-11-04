#!/usr/bin/env python3
"""Print volition decision history."""
import json, os, sys

log_path = os.environ.get('VOLITION_LOG_PATH', '')
if not os.path.exists(log_path):
    print("No decision history yet.")
    sys.exit(0)

with open(log_path) as f:
    for line in f:
        try:
            entry = json.loads(line.strip())
            ts = entry.get('ts', 0)
            q = entry.get('question', entry.get('consensus', ''))
            print(f"[{ts}] {entry.get('type', '?')}: {str(q)[:80]}")
        except:
            pass
