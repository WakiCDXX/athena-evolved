#!/usr/bin/env python3
"""Format device properties as compact JSON from command-line args."""
import json, sys

def raw(s): return str(s).strip().strip('"')

def to_int_or_raw(s):
    if s.isdigit():
        return int(s)
    return raw(s)

args = sys.argv[1:]
model = raw(args[0]) if len(args) > 0 else '?'
sdk = to_int_or_raw(args[1]) if len(args) > 1 else '?'
release = raw(args[2]) if len(args) > 2 else '?'
hardware = raw(args[3]) if len(args) > 3 else '?'
density = to_int_or_raw(args[4]) if len(args) > 4 else '?'
tz = raw(args[5]) if len(args) > 5 else '?'
zygote = raw(args[6]) if len(args) > 6 else '?'

print(json.dumps({
    'device': {
        'model': model, 'sdk': sdk, 'release': release,
        'hardware': hardware, 'density': density,
        'timezone': tz, 'zygote': zygote
    }
}, separators=(',', ':')))
