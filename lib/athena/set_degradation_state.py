import json, os, time

degradation_file = os.environ.get("DEGRADATION_FILE", "")
new_state = os.environ.get("NEW_STATE", "")
reason = os.environ.get("REASON", "")

with open(degradation_file) as f:
    data = json.load(f) if os.path.exists(degradation_file) else {}

# Initialize missing keys
if 'transitions' not in data:
    data['transitions'] = []
if 'triggers' not in data:
    data['triggers'] = {}

old_state = data.get('state', 'normal')
if old_state != new_state:
    data['transitions'].append({
        'from': old_state,
        'to': new_state,
        'reason': reason,
        'timestamp': time.time()
    })
    if len(data['transitions']) > 20:
        data['transitions'] = data['transitions'][-20:]

data['state'] = new_state
data['timestamp'] = time.time()
data['triggers'][reason] = time.time()

with open(degradation_file, 'w') as fh:
    json.dump(data, fh, indent=2)
print(new_state)
