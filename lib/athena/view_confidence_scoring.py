#!/usr/bin/env python3
"""Print confidence scoring and evidence source information."""
import json
import os
import sys

state_file = os.environ.get('VIEW_STRUCTURED_STATE_FILE', '')

try:
    with open(state_file) as f:
        state = json.load(f)
except Exception:
    print(f'Error: could not read state file')
    sys.exit(0)

acc = state.get('accessibility_available', False)
pixel = state.get('pixel_analysis_available', False)
conf = state.get('confidence', 0)

print(f'Accessibility: {"available" if acc else "unavailable"}')
print(f'Pixel analysis: {"available" if pixel else "unavailable"}')
print(f'Confidence score: {conf:.2f}')
if acc and pixel:
    print('Evidence source: BOTH (highest confidence)')
elif acc:
    print('Evidence source: Accessibility (primary)')
elif pixel:
    print('Evidence source: Pixel fallback')
else:
    print('Evidence source: NONE (low confidence)')
