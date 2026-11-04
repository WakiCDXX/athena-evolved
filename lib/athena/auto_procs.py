#!/usr/bin/env python3
"""Get process info for body_update."""
import json, os, sys

termux_pid = os.environ.get('BODY_PROC_PID', '0')
top_cpu = os.environ.get('BODY_TOP_CPU', '[]')
top_mem = os.environ.get('BODY_TOP_MEM', '[]')
try:
    cpu = json.loads(top_cpu) if top_cpu else []
except json.JSONDecodeError:
    cpu = []
try:
    mem = json.loads(top_mem) if top_mem else []
except json.JSONDecodeError:
    mem = []
print(json.dumps({'termux_pid': int(termux_pid), 'top_cpu': cpu, 'top_mem': mem}))
