#!/usr/bin/env python3
"""Compute MD5 hash of a file and print first 12 hex chars."""
import hashlib
import os
import sys

img_path = os.environ.get('VIEW_IMG', '')

try:
    with open(img_path, 'rb') as f:
        print(hashlib.md5(f.read()).hexdigest()[:12])
except Exception:
    print('none')
