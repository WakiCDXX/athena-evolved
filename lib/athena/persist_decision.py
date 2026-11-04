#!/usr/bin/env python3
"""Persist auto decision to session_context.json."""
import json
import sys
import os
import time

session_path = os.environ.get("ATHENA_SESSION_PATH", "")
tmpfile = os.environ.get("ATHENA_TMPFILE", "")
try:
    with open(session_path) as f:
        d = json.load(f)
except:
    d = {}
with open(tmpfile) as f:
    d["last_auto_decision"] = json.load(f)
d["last_auto_run"] = int(time.time())
with open(session_path, "w") as f:
    json.dump(d, f, indent=2)
os.remove(tmpfile)
