#!/usr/bin/env python3
"""Record voice recognition result with metadata."""
import json
import os
import sys

transcript = os.environ.get("ATHENA_TRANSCRIPT", "")
backend = os.environ.get("ATHENA_BACKEND", "")
duration = os.environ.get("ATHENA_DURATION", "")
result_path = os.environ.get("ATHENA_RESULT_PATH", "")

result = {
    "transcript": transcript,
    "backend": backend,
    "duration": duration,
    "timestamp": int(os.environ.get("EPOCHREALTIME", 0)) if os.environ.get("EPOCHREALTIME") else 0
}

try:
    with open(result_path, "w") as f:
        json.dump(result, f, indent=2)
except:
    pass

print(json.dumps(result))
