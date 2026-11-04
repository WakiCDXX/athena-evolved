#!/usr/bin/env python3
"""Calculate confidence from similarity score."""
import sys

sim_str = sys.stdin.read().strip()
try:
    sim = float(sim_str)
    confidence = round(sim * 0.5 + 0.5, 2)
    print(confidence)
except:
    print("0.5")
