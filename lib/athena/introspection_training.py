#!/usr/bin/env python3
"""Generate training data from consciousness state."""
import json, os, time, sys

state_path = os.environ.get('INTROSPECTION_STATE_PATH', '')
training_dir = os.environ.get('INTROSPECTION_TRAINING_DIR', '')
embeddings_dir = os.environ.get('INTROSPECTION_EMBEDDINGS_DIR', '')

if not os.path.exists(state_path):
    sys.exit(0)

with open(state_path) as f:
    state = json.load(f)

report = state.get('last_self_report')
if not report:
    sys.exit(0)

now_ts = int(time.time())
env_snapshot = {
    'battery': report['body'].get('battery_pct'),
    'cpu_khz': report['body'].get('cpu_khz'),
    'mem_pct': report['body'].get('mem_pct'),
    'storage_pct': report['body'].get('storage_pct'),
    'thermal': report['body'].get('thermal_zones'),
    'throttling': report['body'].get('throttling'),
    'network_type': report['body'].get('network_type'),
    'signal_dbm': report['body'].get('signal_dbm'),
    'emotions': report['emotions'],
    'attention_active': report['attention'].get('active'),
    'session': report['session']
}

reasoning = {
    'pattern': 'normal' if env_snapshot.get('battery') and env_snapshot['battery'] > 30 else 'low_power',
    'thermal_status': 'normal' if not env_snapshot.get('throttling') else 'throttling',
    'engagement': env_snapshot.get('emotions', {}).get('engagement', 0) if isinstance(env_snapshot.get('emotions'), dict) else 0,
    'action': 'continue_monitoring'
}

training_entry = {'input': env_snapshot, 'output': reasoning, 'ts': now_ts}
day_str = time.strftime('%Y%m%d', time.localtime(now_ts))
train_file = os.path.join(training_dir, f'training_{day_str}.jsonl')
with open(train_file, 'a') as f:
    f.write(json.dumps(training_entry) + '\n')

embedding = {
    'ts': now_ts, 'dims': 128,
    'vector': [0.0] * 128,
    'label': reasoning['pattern'],
    'session': env_snapshot['session']
}
emb_file = os.path.join(embeddings_dir, f'emb_{now_ts}.json')
with open(emb_file, 'w') as f:
    json.dump(embedding, f, separators=(',',':'))
