#!/usr/bin/env python3
"""Build structured state from accessibility snapshot into JSON for shell capture."""
import json
import os
import sys

acc_snapshot = os.environ.get('VIEW_ACC_SNAPSHOT', '')
timestamp = os.environ.get('VIEW_TIMESTAMP', '0')

try:
    acc_data = json.loads(acc_snapshot)
    windows = acc_data.get('windows', [])
    active_window = {}
    focused_node = {}
    dialogs = []
    nav = False
    for w in windows:
        if w.get('isFocused') or w.get('active'):
            active_window = {k: str(v) for k, v in w.items() if k != 'children'}
            focused_node = w.get('focusedNode', w.get('rootNode', {}))
            if isinstance(focused_node, dict):
                focused_node = {k: str(v) for k, v in focused_node.items() if k in ('text', 'className', 'bounds', 'clickable', 'resourceId')}
        if w.get('type') == 'dialog' or 'dialog' in str(w.get('className', '')).lower():
            dialogs.append(str(w.get('className', 'unknown')))
        if w.get('navigation'):
            nav = True
    print(json.dumps({
        'active_window': active_window,
        'focused_node': focused_node,
        'dialogs': dialogs,
        'navigation_present': nav,
        'accessibility_available': True,
        'timestamp': timestamp
    }))
except Exception:
    print(json.dumps({
        'active_window': {},
        'focused_node': {},
        'dialogs': [],
        'navigation_present': False,
        'accessibility_available': True,
        'timestamp': timestamp
    }))
