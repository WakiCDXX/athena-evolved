#!/usr/bin/env python3
"""Clamp a numeric value to a range."""
import os, sys

val = os.environ.get('JSON_CLAMP_VAL', '')
lo = os.environ.get('JSON_CLAMP_LO', '')
hi = os.environ.get('JSON_CLAMP_HI', '')

try:
    v = float(val)
    l = float(lo)
    h = float(hi)
    print(max(l, min(h, v)))
except:
    print(val)
