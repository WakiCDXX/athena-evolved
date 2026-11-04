#!/usr/bin/env python3
"""Read and print session context JSON."""
import json, os, sys

p = os.environ.get("ATHENA_SESSION_FILE", "/opt/athena/state/session_context.json")
try:
    d = json.load(open(p))
    print(json.dumps(d, indent=2))
except:
    print('No session context found.')
    sys.exit(1)
