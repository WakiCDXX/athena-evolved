#!/usr/bin/env python3
"""Print a summary of session context."""
import json, os, sys

p = os.environ.get("ATHENA_SESSION_FILE", "/opt/athena/state/session_context.json")
try:
    d = json.load(open(p))
    print(f'Time: {d.get("iso_time","?")}')
    print(f'Model: {d.get("model","?")}')
    print(f'Concerns: {len(d.get("active_concerns",[]))}')
    for c in d.get("active_concerns",[]):
        print(f'  • {c}')
except:
    print('No session context found.')
    sys.exit(1)
