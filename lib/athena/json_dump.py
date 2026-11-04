import json
import os

path = os.environ.get("JSON_PATH", "")
try:
    with open(path) as f:
        d = json.load(f)
    print(d)
except:
    print({})
