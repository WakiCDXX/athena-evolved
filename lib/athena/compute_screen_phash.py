#!/usr/bin/env python3
"""Compute perceptual hash of screen image for comparison."""
import os, sys

screen_file = os.environ.get("ATHENA_SCREEN_FILE", "")

if not screen_file or not os.path.exists(screen_file):
    print("none")
    sys.exit(0)

try:
    from PIL import Image, ImageHash
    img = Image.open(screen_file).convert("RGB")
    print(img.phash)
except Exception:
    print("none")
