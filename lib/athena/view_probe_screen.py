#!/usr/bin/env python3
"""Print screen probe information from structured state."""
import json
import os
import sys

state_file = os.environ.get('VIEW_STRUCTURED_STATE_FILE', '')

try:
    with open(state_file) as f:
        state = json.load(f)
except Exception:
    sys.exit(0)

print(f'Content type: {state.get("content_type", "unknown")}')
print(f'Navigation present: {state.get("navigation_present", False)}')
print(f'Dialogs: {state.get("dialogs", [])}')
print(f'Active window: {state.get("active_window", {})}')
print(f'Focused node: {state.get("focused_node", {})}')
print(f'Accessibility available: {state.get("accessibility_available", False)}')
print(f'Confidence: {state.get("confidence", 0.3):.2f}')
