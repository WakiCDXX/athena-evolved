#!/usr/bin/env python3
"""Update doubt state after volition."""
import json, os, sys

doubt_path = os.environ.get('INTROSPECTION_DOUBT_PATH', '')
if not os.path.exists(doubt_path):
    sys.exit(0)
try:
    with open(doubt_path) as f:
        doubt = json.load(f)
    doubt['last_query'] = 'volition-decision'
    doubt['confidence'] = doubt.get('confidence', 0.8)
    with open(doubt_path, 'w') as f:
        json.dump(doubt, f, separators=(',', ':'))
except:
    pass
