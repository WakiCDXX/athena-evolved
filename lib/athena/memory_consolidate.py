#!/usr/bin/env python3
"""Consolidate memory from layers into memory.json."""
import json, os, sys

memory_path = os.environ.get('MEMORY_CONSOLIDATE_PATH', '')
data_dir = os.environ.get('MEMORY_CONSOLIDATE_DATA_DIR', '')

if not os.path.exists(memory_path) or os.path.getsize(memory_path) == 0:
    memory_data = {'key_events': [], 'insights': [], 'last_consolidation': 0}
else:
    with open(memory_path) as f:
        memory_data = json.load(f)

consolidation_entry = {
    'ts': int(os.environ.get('MEMORY_TS', 0)),
    'source_layers': os.environ.get('MEMORY_SOURCES', '').split(','),
    'events': [],
    'insights': []
}

# Collect key events from each layer
for layer in ['attention', 'doubt', 'volition', 'introspection']:
    fpath = os.path.join(data_dir, f'{layer}.json')
    if os.path.exists(fpath) and os.path.getsize(fpath) > 0:
        try:
            with open(fpath) as f:
                d = json.load(f)
            if 'last_decision' in d:
                consolidation_entry['events'].append({'layer': layer, 'event': d['last_decision']})
            if 'active_task' in d:
                consolidation_entry['events'].append({'layer': layer, 'task': d['active_task']})
        except:
            pass

# Update consolidation log
log = memory_data.get('consolidation_log', [])
log.append(consolidation_entry)
memory_data['consolidation_log'] = log[-20:]
memory_data['last_consolidation'] = int(os.environ.get('MEMORY_TS', 0))

with open(memory_path, 'w') as f:
    json.dump(memory_data, f, separators=(',', ':'))
