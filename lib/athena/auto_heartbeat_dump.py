#!/usr/bin/env python3
"""Dump heartbeat with layer status summary."""
import json, os, sys, time

heartbeat_file = os.environ.get('AUTO_HEARTBEAT_FILE', '')
try:
    with open(heartbeat_file) as f:
        d = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    d = {}

now = int(time.time())
layer_status = d.get('layer_status', {})
alerts = d.get('alerts', [])

statuses = {}
for layer, info in layer_status.items():
    if isinstance(info, dict):
        last = info.get('last_updated', 0)
        age = now - last if last else None
        statuses[layer] = {
            'status': info.get('status', 'unknown'),
            'age_seconds': age,
            'fresh': age is not None and age <= 300
        }
    else:
        statuses[layer] = {'status': str(info), 'age_seconds': None, 'fresh': False}

critical = [a['layer'] for a in alerts if a.get('status') == 'critical']
stale = [a['layer'] for a in alerts if a.get('status') == 'stale']

result = {
    'timestamp': d.get('timestamp', 0),
    'layer_status': statuses,
    'alerts': alerts,
    'critical_layers': critical,
    'stale_layers': stale,
    'healthy_count': sum(1 for s in statuses.values() if s.get('fresh')),
    'total_layers': len(statuses)
}
print(json.dumps(result))
