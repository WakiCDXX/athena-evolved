#!/usr/bin/env python3
"""Detect permission dialog on screen using PIL ImageStat."""
import os, sys

screen_file = os.environ.get("ATHENA_SCREEN_FILE", "")

if not screen_file or not os.path.exists(screen_file):
    print("false")
    sys.exit(0)

try:
    from PIL import Image, ImageStat
    img = Image.open(screen_file).convert("RGB")
    w, h = img.size

    # Constraint 1: Bottom region should have UI elements (dialog buttons)
    bottom = img.crop((0, int(h * 0.7), w, h))
    bottom_stat = ImageStat.Stat(bottom)
    bottom_rms = sum(bottom_stat.rms) / 3

    # Constraint 2: Center region should have content (dialog text/fields)
    center = img.crop((int(w * 0.1), int(h * 0.15), int(w * 0.9), int(h * 0.65)))
    center_stat = ImageStat.Stat(center.convert("RGB"))
    center_rms = sum(center_stat.rms) / 3

    # Constraint 3: Edge density suggests structured UI (dialog box)
    full_stat = ImageStat.Stat(img.convert("RGB"))
    edge_proxy = sum(full_stat.rms) / 3

    # Heuristic: dialog = high center + high bottom + structured edges
    score = 0
    if bottom_rms > 25:
        score += 1
    if center_rms > 30:
        score += 1
    if edge_proxy > 35:
        score += 1

    print("true" if score >= 2 else "false")
except Exception:
    print("false")
