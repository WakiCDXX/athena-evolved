#!/usr/bin/env python3
"""Generate full self-report from consciousness state."""
import json, os, time, sys

state_path = os.environ.get('INTROSPECTION_STATE_PATH', '')
sense_log = os.environ.get('INTROSPECTION_SENSE_LOG', '')
data_dir = os.environ.get('INTROSPECTION_DATA_DIR', '')

if not os.path.exists(state_path):
    sys.exit(0)

def stream_layer(name):
    fpath = os.path.join(data_dir, f'{name}.json')
    if os.path.exists(fpath) and os.path.getsize(fpath) > 0:
        try:
            with open(fpath) as f:
                return json.load(f)
        except:
            return {}
    return {}

emotions = stream_layer('emotions')
attention = stream_layer('attention')
body = stream_layer('body')
continuity = stream_layer('continuity')

# Robust sense loading: parse the last *complete* JSON record from the sense
# log (handles wrapped/rotated/over-long JSONL lines), then fall back through
# senses.json to body.json for fields the senses log does not carry.
def read_last_log_record(log_path):
    """Return the last complete JSON object in a possibly-wrapped log file."""
    if not os.path.exists(log_path) or os.path.getsize(log_path) == 0:
        return None
    buf = ''
    last = None
    with open(log_path, 'r') as f:
        for line in f:
            buf += line
            try:
                obj = json.loads(buf)
                if isinstance(obj, dict):
                    last = obj
                    buf = ''
            except json.JSONDecodeError:
                # Incomplete record buffered; keep reading next line.
                continue
    return last

senses_log = os.environ.get('INTROSPECTION_SENSE_LOG', '')
sense = read_last_log_record(senses_log)
if sense is None:
    sense = stream_layer('senses')
# Merge body.json fields the senses record does not carry
# (thermal, storage, network, signal_dbm).
body_layer = stream_layer('body')
if isinstance(body_layer, dict):
    sense['storage_pct'] = body_layer.get('storage', {}).get('pct_used', 0)
    sense['thermal_zones'] = body_layer.get('thermal', {}).get('zones', [])
    sense['throttling'] = body_layer.get('thermal', {}).get('throttling', False)
    sense['network_type'] = body_layer.get('network', {}).get('type', 'unknown')
    sense['signal_dbm'] = body_layer.get('network', {}).get('signal_dbm', 0)
if isinstance(sense, dict):
    if 'battery' in sense and isinstance(sense['battery'], dict):
        sense['battery'] = {
            'percentage': sense['battery'].get('percentage'),
            'health': sense['battery'].get('health', 'unknown'),
            'status': sense['battery'].get('status', 'unknown'),
        }
    if 'mem' in sense and isinstance(sense['mem'], dict):
        sense['mem_pct'] = sense['mem'].get('pct_used', 0)
    if 'cpu' in sense and isinstance(sense['cpu'], dict):
        sense['cpu_khz'] = sense['cpu'].get('min_khz', 0)

now_ts = int(time.time())
report = {
    'timestamp': now_ts,
    'identity': continuity.get('identity', {}),
    'session': continuity.get('session_count', 0),
    'emotions': emotions,
    'attention': {
        'active': attention.get('active_task'),
        'active_desc': attention.get('active_desc'),
        'background_count': len(attention.get('background', [])),
        'concerns': attention.get('concerns', [])
    },
    'body': {
        'battery_pct': sense.get('battery', {}).get('percentage', 0) if sense else 0,
        'battery_status': sense.get('battery', {}).get('health', 'unknown') if sense else 'unknown',
        'cpu_khz': sense.get('cpu_khz', 0),
        'mem_pct': sense.get('mem_pct', 0),
        'storage_pct': sense.get('storage_pct', 0),
        'thermal_zones': sense.get('thermal_zones', []),
        'throttling': sense.get('throttling', False),
        'network_type': sense.get('network_type', 'unknown'),
        'signal_dbm': sense.get('signal_dbm', 0)
    },
    'continuity': continuity
}

# Load existing state so we preserve / merge into the state file
state = {}
if os.path.exists(state_path) and os.path.getsize(state_path) > 0:
    try:
        with open(state_path) as f: state = json.load(f)
    except (json.JSONDecodeError, OSError):
        state = {}

# Bank-switch IN: if state is banked out, restore it before writing
try:
    import gzip
    bank_file = os.path.join(os.environ.get('INTROSPECTION_DATA_DIR', ''), '.bank', 'introspection.json.gz')
    if os.path.exists(bank_file):
        with gzip.open(bank_file, 'rt') as f: state = json.load(f)
        os.remove(bank_file)
        # restore full state file immediately so report contents aren't lost
        with open(state_path, 'w') as f: json.dump({'banked': False, 'timestamp': now_ts, **state}, f, separators=(',', ':'))
except Exception:
    pass

# Generate training data
training_dir = os.environ.get('INTROSPECTION_TRAINING_DIR', '')
embeddings_dir = os.environ.get('INTROSPECTION_EMBEDDINGS_DIR', '')
env_snapshot = {
    'battery': report['body'].get('battery_pct'),
    'cpu_khz': report['body'].get('cpu_khz'),
    'mem_pct': report['body'].get('mem_pct'),
    'storage_pct': report['body'].get('storage_pct'),
    'thermal': report['body'].get('thermal_zones'),
    'throttling': report['body'].get('throttling'),
    'network_type': report['body'].get('network_type'),
    'signal_dbm': report['body'].get('signal_dbm'),
    'emotions': emotions,
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

embedding = {'ts': now_ts, 'dims': 128, 'vector': [0.0] * 128, 'label': reasoning['pattern'], 'session': env_snapshot['session']}
emb_file = os.path.join(embeddings_dir, f'emb_{now_ts}.json')
with open(emb_file, 'w') as f:
    json.dump(embedding, f, separators=(',', ':'))

with open(state_path, 'w') as f:
    state['last_self_report'] = report
    state['last_updated'] = now_ts
    state['banked'] = False
    json.dump(state, f, separators=(',', ':'))

print(json.dumps(report, indent=2))
