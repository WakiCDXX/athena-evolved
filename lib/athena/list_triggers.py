import json
import os

path = os.environ.get("ATHENA_TRIGGERS_PATH", "")
try:
    with open(path) as f:
        d = json.load(f)
    for k, v in d.get("triggers", {}).items():
        print(f"  {k} -> {v}")
except:
    pass
