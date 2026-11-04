#!/usr/bin/env python3
"""Targeted doubt query — returns confidence and relevant doubt entries."""
import json, os, sys

doubt_path = os.environ.get('DOUBT_PATH', '')
question = os.environ.get('DOUBT_QUESTION', '')

if not doubt_path:
    sys.exit(1)

try:
    with open(doubt_path) as f:
        data = json.load(f)
except:
    data = {'confidence': 0.8, 'calibration_log': [], 'entries': []}

confidence = data.get('confidence', 0.8)
entries = data.get('entries', [])

# Filter entries related to the question (category match)
relevant = [e for e in entries if question.lower() in e.get('category', '').lower() or question.lower() in e.get('detail', '').lower()]

result = {
    'question': question,
    'confidence': confidence,
    'trusted': confidence > 0.5,
    'relevant_doubts': relevant[-5:],  # last 5 relevant entries
    'total_entries': len(entries)
}

data['last_query'] = question
data['last_updated'] = int(os.environ.get('DOUBT_TS', '0'))

try:
    with open(doubt_path, 'w') as f:
        json.dump(data, f, separators=(',', ':'))
except:
    pass

print(json.dumps(result))
