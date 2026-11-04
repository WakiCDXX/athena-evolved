#!/usr/bin/env python3
"""Refresh stale layers."""
import json, sys, subprocess, os, tempfile

exec_tmpfile = os.environ.get('EXEC_TMPFILE', '')

try:
    with open(exec_tmpfile) as f:
        d = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    d = {}

for layer in d.get("stale_layers", []):
    print(f"Refreshing {layer}...")
    if layer == "body":
        subprocess.run(["bash", "/root/.local/bin/body_update.sh", "poll"])
    elif layer == "emotions":
        subprocess.run(["bash", "/root/.local/bin/emotions_update.sh", "decay"])
    elif layer == "attention":
        subprocess.run(["bash", "/root/.local/bin/attention_update.sh", "read"])
    elif layer == "heartbeat":
        subprocess.run(["bash", "/root/.local/bin/heartbeat_update.sh", "check"])
try:
    os.remove(exec_tmpfile)
except OSError:
    pass
