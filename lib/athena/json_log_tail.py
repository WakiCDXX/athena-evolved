#!/usr/bin/env python3
"""Get the last N lines from a JSON log file."""
import json, os, sys

log_path = os.environ.get('ATHENA_LOG_PATH', '')
n = int(os.environ.get('ATHENA_LOG_N', '5'))

try:
    with open(log_path) as f:
        lines = f.readlines()
    for line in lines[-n:]:
        print(line.strip())
except:
    pass
