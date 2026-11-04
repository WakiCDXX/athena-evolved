#!/usr/bin/env python3
"""Extract battery data from JSON stdin."""
import json, sys

try:
    d = json.load(sys.stdin)
    print(json.dumps(d, separators=(',', ':')))
except:
    print("")
