#!/usr/bin/env python3
"""Calculate similarity between two recognition results."""
import json
import os
import difflib

result_path = os.environ.get("ATHENA_RESULT_PATH", "")
alt_path = os.environ.get("ATHENA_ALT_PATH", "")

try:
    with open(result_path) as f:
        primary = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    primary = {}
    with open(alt_path) as f:
        alt = json.load(f)
    text1 = primary.get("transcript", "")
    text2 = alt.get("transcript", "")

    if text1 and text2:
        similarity = difflib.SequenceMatcher(None, text1.lower(), text2.lower()).ratio()
    elif text1 or text2:
        similarity = 0.5
    else:
        similarity = 1.0

    # Determine agreement
    if similarity >= 0.8:
        agreement = "high"
    elif similarity >= 0.5:
        agreement = "partial"
    else:
        agreement = "divergent"

    print(json.dumps({"similarity": round(similarity, 2), "agreement": agreement}))
except:
    print(json.dumps({"similarity": 0.0, "agreement": "unknown"}))
