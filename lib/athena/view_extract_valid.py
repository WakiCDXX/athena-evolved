#!/usr/bin/env python3
"""Extract 'valid' boolean from validation JSON on stdin."""
import json
import sys

try:
    data = json.load(sys.stdin)
    print(data.get('valid', False))
except Exception:
    print(False)
