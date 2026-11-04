#!/usr/bin/env python3
"""Check peer agent status."""
import json, os, sys

peer_out = os.environ.get('ATHENA_PEER_OUT_FILE', '')
if not peer_out or not os.path.exists(peer_out):
    print('not_found')
    sys.exit(1)

try:
    with open(peer_out) as f:
        data = json.load(f)
    status = data.get('status', 'unknown')
    print(status)
except:
    print('error')
