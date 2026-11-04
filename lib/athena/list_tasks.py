import json
import os

path = os.environ.get("ATHENA_LAYER_DATA_PATH", "")
try:
    with open(path) as f:
        d = json.load(f)
    print(d.get("pending_tasks", []))
except:
    print([])
