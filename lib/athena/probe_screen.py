#!/usr/bin/env python3
"""Probe screen for OCR, layout hash, and text analysis."""
import json
import subprocess
import hashlib
import os
import sys

screen_path = os.environ.get("ATHENA_SCREEN_PATH", "")

try:
    # Take screenshot and run OCR
    result = subprocess.run(
        ["screencap", "-p"],
        capture_output=True
    )
    screenshot_data = result.stdout
    screen_hash = hashlib.sha256(screenshot_data).hexdigest()[:16] if screenshot_data else ""
except:
    screen_hash = ""

# Build probe result
probe = {
    "hash": screen_hash,
    "timestamp": int(os.environ.get("EPOCHREALTIME", 0)) if os.environ.get("EPOCHREALTIME") else 0,
    "ocr_text": ""
}

# Try OCR if screenshotcapable
try:
    ocr = subprocess.run(
        ["tesseract", "-", "stdout"],
        input=screenshot_data if 'screenshot_data' in dir() else b'',
        capture_output=True
    )
    probe["ocr_text"] = ocr.stdout.decode("utf-8", errors="replace").strip()
except:
    probe["ocr_text"] = ""

# Try to get window info
try:
    win_info = subprocess.run(
        ["dumpsys", "window", "windows"],
        capture_output=True, text=True
    )
    probe["window_info"] = win_info.stdout[:500]
except:
    probe["window_info"] = ""

print(json.dumps(probe))
