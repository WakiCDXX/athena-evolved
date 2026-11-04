import json, time, os, sys, fcntl

data_dir = os.environ.get('ATHENA_DATA_DIR', '/opt/athena/state')

lock_file = os.path.join(data_dir, 'daemon_feedback.jsonl.lock')
name = os.environ.get('ATHENA_LAYER_NAME', '')
script = os.environ.get('ATHENA_LAYER_SCRIPT', '')
cmd_args = os.environ.get('ATHENA_CMD_ARGS', 'poll')
interval = int(os.environ.get('ATHENA_INTERVAL', '120'))
success = int(os.environ.get('ATHENA_SUCCESS', '0'))
fail = int(os.environ.get('ATHENA_FAIL', '0'))

# Check degradation state
try:
    with open(os.path.join(data_dir, 'degradation_state.json')) as f:
        current_state = json.load(f).get('state', 'normal')
except (json.JSONDecodeError, FileNotFoundError):
    current_state = 'normal'

if current_state in ('suspended', 'safe_shutdown'):
    sys.exit(0)

# Compute adapted_interval from LUT
lut_dir = os.path.join(data_dir, '.luts')
adapt_lut = {}
try:
    with open(os.path.join(lut_dir, 'adapt_interval.json')) as f:
        adapt_lut = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    adapt_lut = {}
rate = success * 100 // (success + fail) if (success + fail) > 0 else 0
rate = max(0, min(100, rate))
adapted_mult = adapt_lut.get(str(rate), 1.0)
adapted_interval = int(interval * adapted_mult)

# Record result in daemon_feedback.json
feedback_file = os.path.join(data_dir, 'daemon_feedback.json')
try:
    lock_fd = os.open(lock_file, os.O_CREAT | os.O_RDWR, 0o600)
    fcntl.flock(lock_fd, fcntl.LOCK_EX)
    try:
        with open(feedback_file) as f:
            d = json.load(f)
        n = d.setdefault(name, {'success':0,'fail':0,'current_interval':interval,'adapted_interval':adapted_interval,'last_run':0,'streak':0})
        n['last_run'] = int(time.time())
        if fail == 0: n['success'] += 1
        else: n['fail'] += 1
        n['adapted_interval'] = adapted_interval
        with open(feedback_file, 'w') as fh: json.dump(d, fh, separators=(',',':'))
    finally:
        fcntl.flock(lock_fd, fcntl.LOCK_UN)
        os.close(lock_fd)
except (json.JSONDecodeError, OSError):
    pass

# Output adapted_interval for shell capture
print(adapted_interval)
