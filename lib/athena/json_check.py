#!/usr/bin/env python3
"""Check if a file exists and return its size."""
import json, os, sys

path = os.environ.get('ATHENA_CHECK_PATH', '')

if not path:
    print('{"exists": false, "size": 0}')
    sys.exit(1)

if os.path.exists(path):
    size = os.path.getsize(path)
    print(f'{{"exists": true, "size": {size}}}')
else:
    print('{"exists": false, "size": 0}')
