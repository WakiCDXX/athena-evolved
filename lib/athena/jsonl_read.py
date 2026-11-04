#!/usr/bin/env python3
"""Read a value from a JSONL file (last N entries)."""
import json, os, sys

path = os.environ.get('ATHENA_JSONL_PATH', '')
n = int(os.environ.get('ATHENA_JSONL_N', '5'))

try:
    with open(path) as f:
        lines = f.readlines()
    entries = []
    for line in lines[-n:]:
        line = line.strip()
        if line:
            try:
                entries.append(json.loads(line))
            except:
                pass
    print(json.dumps(entries))
except:
    print('[]')
