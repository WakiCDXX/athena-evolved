#!/usr/bin/env python3
"""Process auto_procs output and write body state."""
import json, os, sys, tempfile

sys.path.insert(0, os.path.dirname(__file__) or '.')
from filelock import lock, unlock, atomic_write

data = json.loads(sys.stdin.read())
proc_path = '/opt/athena/state/body.json'
state_path = os.environ.get('BODY_STATE_PATH', proc_path)
field = os.environ.get('BODY_FIELD', 'processes')
ts = os.environ.get('BODY_PROC_TS', '0')
pid = data.get('termux_pid', 0)

# Read with shared lock
lock_path = state_path + '.lock'
try:
    fp = lock(lock_path, exclusive=False, timeout=5)
    try:
        with open(state_path) as f:
            state = json.load(f)
    finally:
        unlock(fp)
except (json.JSONDecodeError, FileNotFoundError):
    state = {}
except TimeoutError:
    state = {}

state[field] = data
state['last_updated'] = int(ts)

# Atomic write with exclusive lock
try:
    atomic_write(state_path, state, timeout=5)
except (OSError, json.JSONDecodeError):
    pass
