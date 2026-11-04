#!/usr/bin/env python3
"""Transcribe audio file using specified backend."""
import json
import os
import sys

audio_path = os.environ.get("ATHENA_AUDIO_PATH", "")
backend = os.environ.get("ATHENA_BACKEND", "")

result = {"transcript": "", "backend": backend, "duration": ""}

try:
    if backend == "whisper":
        import subprocess
        proc = subprocess.run(
            ["whisper", audio_path, "--output_format", "json"],
            capture_output=True, text=True
        )
        result["transcript"] = proc.stdout.strip()
    elif backend == "android":
        import subprocess
        proc = subprocess.run(
            ["monkey", "-p", "com.google.android.googlequicksearchbox", "1"],
            capture_output=True, text=True
        )
        result["transcript"] = proc.stdout.strip()
    result["duration"] = str(os.path.getsize(audio_path))
except:
    pass

print(json.dumps(result))
