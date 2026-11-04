#!/usr/bin/env python3
"""Restart critical layers."""
import json, sys, subprocess, os

exec_tmpfile = os.environ.get('EXEC_TMPFILE', '')
exec_data_dir = os.environ.get('EXEC_DATA_DIR', '')

try:
    with open(exec_tmpfile) as f:
        d = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    d = {}

for layer in d.get("critical_layers", []):
    if layer == "heartbeat":
        subprocess.run(["bash", "/root/.local/bin/heartbeat_update.sh", "check"])
    elif layer in ["body", "emotions", "continuity", "attention", "introspection", "doubt", "volition", "memory"]:
        pidfile = os.path.join(exec_data_dir, f'{layer}.pid')
        try:
            os.remove(pidfile)
        except OSError:
            pass
    print(f"Restarted/flagged {layer}")
try:
    os.remove(exec_tmpfile)
except OSError:
    pass
