#!/usr/bin/env python3
"""Get layer state with staleness detection."""
import json, os, sys, time

layer_file = os.environ.get('AUTO_LAYER_FILE', '')
layer_name = os.environ.get('AUTO_LAYER_NAME', '')
max_age = int(os.environ.get('AUTO_MAX_AGE', '300'))

try:
    with open(layer_file) as f:
        d = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    d = {}

now = int(time.time())
last_updated = d.get('last_updated', 0)
age = now - last_updated if last_updated else None

result = {
    'layer': layer_name or os.path.basename(layer_file).replace('.json', ''),
    'data': d,
    'last_updated': last_updated,
    'age_seconds': age,
    'fresh': age is not None and age <= max_age,
    'stale': age is not None and age > max_age
}
print(json.dumps(result))
