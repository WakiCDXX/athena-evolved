#!/usr/bin/env python3
"""Persist auto decision to session context."""
import json, sys, os, time, tempfile

sys.path.insert(0, os.path.dirname(__file__) or '.')
from filelock import atomic_write, lock, unlock

persist_path = os.environ.get('PERSIST_PATH', '')
persist_tmpfile = os.environ.get('PERSIST_TMPFILE', '')

# Read with shared lock
lock_path = persist_path + '.lock'
try:
    fp = lock(lock_path, exclusive=False, timeout=5)
    try:
        with open(persist_path) as f:
            d = json.load(f)
    finally:
        unlock(fp)
except (json.JSONDecodeError, FileNotFoundError):
    d = {}
except TimeoutError:
    d = {}

# Read tmpfile
try:
    with open(persist_tmpfile) as f:
        d["last_auto_decision"] = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    pass

d["last_auto_run"] = int(os.environ.get('PERSIST_NOW', 0)) or int(time.time())

# Atomic write with lock
try:
    atomic_write(persist_path, d, timeout=5)
except (OSError, json.JSONDecodeError):
    pass
