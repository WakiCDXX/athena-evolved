import json
import os

path = os.environ.get("SESSION_CONTEXT_PATH", "")
try:
    with open(path) as f:
        d = json.load(f)
    ld = d.get("last_auto_decision", {})
    print(f"  Time: {ld.get('timestamp', '?')}")
    print(f"  Overall: {ld.get('overall', '?')}")
    print(f"  Actions: {ld.get('actions', [])}")
    print(f"  Critical: {ld.get('critical_layers', [])}")
    print(f"  Stale: {ld.get('stale_layers', [])}")
    print(f"  Concerns: {ld.get('concern_count', '?')}")
    print(f"  Tasks: {ld.get('task_count', '?')}")
except:
    print("  No auto decisions yet.")
