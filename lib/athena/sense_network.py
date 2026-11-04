#!/usr/bin/env python3
"""Extract WiFi and network interface data as compact JSON."""
import json, sys

iface_map = {}
for line in sys.stdin:
    parts = line.strip().split()
    if len(parts) >= 3:
        iface = parts[1].rstrip(':')
        state = parts[2] if len(parts) > 2 else 'UNKNOWN'
        if iface != 'lo':
            iface_map[iface] = state

for line in sys.stdin:
    parts = line.strip().split()
    if len(parts) >= 4:
        addr = parts[3]
        iface = parts[1].rstrip(':')
        if iface != 'lo' and addr != '127.0.0.1':
            iface_map[iface] = addr

print(json.dumps({'interfaces': iface_map, 'source': 'shizuku'}, separators=(',', ':')))
