import json, os

statefile = os.environ.get("STATEFILE", "")

with open(statefile) as f:
    d = json.load(f)
print(d.get('last_updated', 0))
