#!/usr/bin/env python3
"""Extract confidence from pixel analysis JSON on stdin."""
import json
import sys

try:
    data = json.load(sys.stdin)
    print(data.get('confidence', 0.3))
except Exception:
    print('0.3')
