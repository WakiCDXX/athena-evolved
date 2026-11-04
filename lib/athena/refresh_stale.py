#!/usr/bin/env python3
"""Refresh stale layers flagged in assessment JSON."""
import json
import sys
import subprocess
import os

tmpfile = os.environ.get("ATHENA_TMPFILE", "")
try:
    with open(tmpfile) as f:
        d = json.load(f)
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
    os.remove(tmpfile)
except:
    pass
