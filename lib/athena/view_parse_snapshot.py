#!/usr/bin/env python3
"""Parse accessibility snapshot into structured state (active/focused/dialogs/nav)."""
import json
import os
import sys

acc_snapshot = os.environ.get('VIEW_ACC_SNAPSHOT', '')

try:
    data = json.loads(acc_snapshot)
    windows = data.get('windows', [])
    active = {}
    focused = {}
    dialogs = []
    nav = False
    for w in windows:
        if w.get('isFocused') or w.get('active'):
            active = w
            focused = w.get('focusedNode', w.get('rootNode', {}))
        if w.get('type') == 'dialog' or 'dialog' in w.get('className', '').lower():
            dialogs.append(w.get('className', 'unknown'))
        if w.get('navigation'):
            nav = True
    print(json.dumps({
        'active_window': active,
        'focused_node': focused,
        'dialogs': dialogs,
        'navigation_present': nav
    }))
except Exception:
    print(json.dumps({}))
