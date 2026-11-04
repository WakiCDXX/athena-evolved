#!/usr/bin/env python3
"""Validate JSON from stdin. Exit 0 if valid, non-zero if not."""
import json
import sys

try:
    json.load(sys.stdin)
    sys.exit(0)
except Exception:
    sys.exit(1)
