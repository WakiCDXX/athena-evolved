#!/usr/bin/env python3
"""Validate an action against current screen state and degradation state."""
import json
import os
import sys

action = os.environ.get('VIEW_ACTION', '')
state_file = os.environ.get('VIEW_STRUCTURED_STATE_FILE', '')
degradation_file = os.environ.get('VIEW_DEGRADATION_FILE', '')

try:
    with open(state_file) as f:
        state = json.load(f)
except Exception:
    print(json.dumps({'valid': False, 'reason': 'validation_error'}))
    sys.exit(0)

# Check degradation state
try:
    with open(degradation_file) as f:
        deg = json.load(f)
    if deg.get('state') in ('suspended', 'safe_shutdown'):
        print(json.dumps({'valid': False, 'reason': 'system_degraded', 'action': action}))
        sys.exit(0)
except Exception:
    pass

# Check permissions
if action == 'ACTION_CLICK':
    if not state.get('accessibility_available') and not state.get('pixel_analysis_available'):
        print(json.dumps({'valid': False, 'reason': 'no_accessibility_or_pixel', 'action': action}))
        sys.exit(0)
    focused = state.get('focused_node', {})
    if focused.get('clickable') == False:
        print(json.dumps({'valid': False, 'reason': 'node_not_clickable', 'action': action}))
        sys.exit(0)
    print(json.dumps({'valid': True, 'reason': 'ok', 'action': action, 'confidence': state.get('confidence', 0.3)}))
elif action == 'ACTION_SCROLL':
    if not state.get('accessibility_available'):
        print(json.dumps({'valid': False, 'reason': 'accessibility_required', 'action': action}))
        sys.exit(0)
    print(json.dumps({'valid': True, 'reason': 'ok', 'action': action}))
elif action == 'ACTION_TYPE':
    if not state.get('accessibility_available'):
        print(json.dumps({'valid': False, 'reason': 'accessibility_required', 'action': action}))
        sys.exit(0)
    print(json.dumps({'valid': True, 'reason': 'ok', 'action': action}))
elif action == 'ACTION_BACK':
    print(json.dumps({'valid': True, 'reason': 'ok', 'action': action}))
elif action == 'ACTION_LAUNCH_APP':
    print(json.dumps({'valid': True, 'reason': 'ok', 'action': action, 'note': 'validate_package_allowlist'}))
else:
    print(json.dumps({'valid': False, 'reason': 'unknown_action', 'action': action}))
