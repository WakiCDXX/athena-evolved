#!/usr/bin/env python3
"""Add narrative entry to continuity."""
import json, os, sys

state_path = os.environ.get('CONTINUITY_STATE_PATH', '')
text = os.environ.get('CONTINUITY_TEXT', '')
priority = os.environ.get('CONTINUITY_PRIORITY', '5')

if not state_path or not text:
    sys.exit(1)

try:
    with open(state_path) as f:
        data = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    data = {}
    entry = {'ts': int(os.environ.get('CONTINUITY_TS', 0)), 'text': text, 'priority': int(priority)}
    narrative = data.get('narrative_thread', [])
    narrative.append(entry)
    data['narrative_thread'] = narrative[-50:]
    data['last_updated'] = int(os.environ.get('CONTINUITY_TS', 0))
    with open(state_path, 'w') as f:
        json.dump(data, f, separators=(',', ':'))
except Exception as e:
    print(f'continuity_add_narrative error: {e}', file=sys.stderr)
