#!/usr/bin/env python3
"""Restart critical layers flagged in assessment JSON."""
import json
import sys
import subprocess
import os

tmpfile = os.environ.get("ATHENA_TMPFILE", "")
try:
    with open(tmpfile) as f:
        d = json.load(f)
    for layer in d.get("critical_layers", []):
        if layer == "heartbeat":
            subprocess.run(["bash", "/root/.local/bin/heartbeat_update.sh", "check"])
        elif layer in ["body", "emotions", "continuity", "attention", "introspection", "doubt", "volition", "memory"]:
            pidfile = f"/opt/athena/state/{layer}.pid"
            try:
                os.remove(pidfile)
            except:
                pass
        print(f"Restarted/flagged {layer}")
    os.remove(tmpfile)
except:
    pass
