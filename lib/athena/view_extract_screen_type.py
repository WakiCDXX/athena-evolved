#!/usr/bin/env python3
"""Extract screen_type from pixel analysis JSON on stdin."""
import json
import sys

try:
    data = json.load(sys.stdin)
    print(data.get('screen_type', 'unknown'))
except Exception:
    print('unknown')
