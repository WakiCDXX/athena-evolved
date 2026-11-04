import json, os

degradation_file = os.environ.get("DEGRADATION_FILE", "")

with open(degradation_file) as f:
    data = json.load(f)

print(f"  State: {data.get('state', 'normal')}")
print(f"  Timestamp: {data.get('timestamp', 0)}")
print(f"  Transitions: {len(data.get('transitions', []))}")
for t in data.get('transitions', [])[-5:]:
    print(f"    {t['from']} -> {t['to']}: {t['reason']}")
