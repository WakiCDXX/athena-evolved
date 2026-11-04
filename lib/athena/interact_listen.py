#!/usr/bin/env python3
"""Interact listen: read JSON from stdin and return summary."""
import json, os, sys

# Reads from stdin (the pipe content)
text = sys.stdin.read().strip()
if not text:
    print("No input received.")
    sys.exit(0)

try:
    d = json.loads(text)
    print(json.dumps(d, indent=2))
except:
    print(f"Raw input: {text[:200]}")
