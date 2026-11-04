import json, os

statefile = os.environ.get("STATEFILE", "")

with open(statefile) as f:
    d = json.load(f)
ts = d.get('last_updated') or d.get('timestamp') or d.get('ts', 0)
if isinstance(ts, str):
    try:
        ts = int(ts)
    except:
        ts = 0
print(ts)
