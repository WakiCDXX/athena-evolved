#!/usr/bin/env python3
"""Calculate confidence score from last recognition result."""
import json
import os
import math

result_path = os.environ.get("ATHENA_RESULT_PATH", "")

try:
    with open(result_path) as f:
        data = json.load(f)
    backend = data.get("backend", "")
    transcript = data.get("transcript", "")
    duration = data.get("duration", 0)

    # Base confidence from backend
    if backend == "whisper":
        base = 0.85
    elif backend == "android":
        base = 0.70
    else:
        base = 0.50

    # Adjust by duration
    dur = float(duration) if duration else 0
    dur_bonus = min(0.15, dur / 30.0 * 0.10)

    # Adjust by transcript length
    text_len = len(transcript.split()) if transcript else 0
    len_bonus = min(0.10, text_len / 20.0 * 0.05)

    confidence = base + dur_bonus + len_bonus
    confidence = min(0.99, confidence)

    print(json.dumps({"confidence": round(confidence, 2), "backend": backend, "text_len": text_len}))
except:
    print(json.dumps({"confidence": 0.0, "backend": "unknown", "text_len": 0}))
