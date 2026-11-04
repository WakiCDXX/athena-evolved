import json, os

feedback_file = os.environ.get("FEEDBACK_FILE", "")
degradation_file = os.environ.get("DEGRADATION_FILE", "")
session_state_file = os.environ.get("SESSION_STATE_FILE", "")

try:
    layers = ['body', 'emotions', 'continuity', 'attention', 'introspection', 'doubt', 'volition', 'memory', 'heartbeat', 'archive', 'memory_backup', 'senses']
    data = {}
    for l in layers:
        data[l] = {'success': 0, 'fail': 0, 'current_interval': None, 'adapted_interval': None, 'last_run': None, 'streak': 0}
    with open(feedback_file, 'w') as f:
        json.dump(data, f, indent=2)

    degradation_data = {
        'state': 'normal',
        'timestamp': 0,
        'transitions': [],
        'triggers': {},
        'recovery_cooldowns': {}
    }
    with open(degradation_file, 'w') as f:
        json.dump(degradation_data, f, indent=2)

    session_data = {
        'mode': 'idle',
        'active_since': 0,
        'screen_hash': '',
        'last_screen_change': 0,
        'session_type': 'event_driven',
        'layers_active': [],
        'last_event': None,
        'event_count': 0
    }
    with open(session_state_file, 'w') as f:
        json.dump(session_data, f, indent=2)
except (OSError, TypeError) as e:
    print(f"daemon_init error: {e}")
