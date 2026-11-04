import json, os

session_state_file = os.environ.get("SESSION_STATE_FILE", "")

try:
    with open(session_state_file) as f:
        data = json.load(f)
    print(data.get('mode', 'event_driven'))
except:
    print('event_driven')
