#!/usr/bin/env python3
"""Get screen hash for tap verification."""
import hashlib
import subprocess
import os

try:
    result = subprocess.run(["screencap", "-p"], capture_output=True)
    screen_hash = hashlib.sha256(result.stdout).hexdigest()[:16] if result.stdout else ""
except:
    screen_hash = ""

print(screen_hash)
