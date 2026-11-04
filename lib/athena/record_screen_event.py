import json, os, time, hashlib

session_state_file = os.environ.get("SESSION_STATE_FILE", "")
structured_state_file = os.environ.get("STRUCTURED_STATE_FILE", "")
event_type = os.environ.get("EVENT_TYPE", "")
detail = os.environ.get("EVENT_DETAIL", "")

with open(session_state_file) as f:
    data = json.load(f)

data['last_event'] = event_type
data['last_event_detail'] = detail
data['last_screen_change'] = time.time()
data['event_count'] = data.get('event_count', 0) + 1

if os.path.exists(structured_state_file):
    try:
        with open(structured_state_file) as f:
            ss = json.load(f)
        raw = str(ss.get('active_window', '')) + str(ss.get('focused_node', '')) + str(ss.get('content_type', ''))
        data['screen_hash'] = hashlib.md5(raw.encode()).hexdigest()[:12]
    except:
        pass

with open(session_state_file, 'w') as f:
    json.dump(data, f, indent=2)
