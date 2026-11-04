#!/usr/bin/env python3
"""Find trigger action for a phrase from triggers JSON file."""
import json
import sys
import os

triggers_path = os.environ.get("ATHENA_TRIGGERS_PATH", "")
phrase = os.environ.get("ATHENA_TRIGGER_PHRASE", "").lower().strip()

try:
    with open(triggers_path) as f:
        data = json.load(f)
    triggers = data.get("triggers", {})
    # Direct match
    if phrase in triggers:
        print(triggers[phrase])
    else:
        # Check for partial matches
        for key, val in triggers.items():
            if phrase in key or key in phrase:
                print(val)
                break
        else:
            print("unknown")
except:
    print("unknown")
