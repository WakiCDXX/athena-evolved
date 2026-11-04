import json, os, time

session_state_file = os.environ.get("SESSION_STATE_FILE", "")
mode = os.environ.get("SESSION_MODE", "")

try:
    with open(session_state_file) as f:
        data = json.load(f)
except:
    data = {'mode': 'idle', 'active_since': 0, 'screen_hash': '', 'last_screen_change': 0, 'session_type': 'event_driven', 'layers_active': [], 'last_event': None, 'event_count': 0}

data['mode'] = mode
data['session_type'] = mode
data['active_since'] = time.time()
with open(session_state_file, 'w') as f:
    json.dump(data, f, indent=2)
print(mode)
