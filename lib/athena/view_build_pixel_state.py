#!/usr/bin/env python3
"""Build state with pixel-only data when accessibility is unavailable."""
import json
import os
import sys

screen_type = os.environ.get('VIEW_SCREEN_TYPE', 'unknown')
confidence = os.environ.get('VIEW_CONFIDENCE', '0.3')
timestamp = os.environ.get('VIEW_TIMESTAMP', '0')

state = {
    'active_window': {'package': 'unknown', 'class': 'unknown', 'accessibility_available': False},
    'focused_node': {'text': '', 'clickable': False, 'bounds': [0, 0, 0, 0]},
    'dialogs': [],
    'navigation_present': False,
    'content_type': screen_type,
    'accessibility_available': False,
    'pixel_analysis_available': True,
    'confidence': float(confidence),
    'timestamp': timestamp
}
print(json.dumps(state))
