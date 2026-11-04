import os, sys
logfile = os.environ.get('ATHENA_RING_LOG', '')
msg = os.environ.get('ATHENA_RING_MSG', '')
max_lines = int(os.environ.get('ATHENA_RING_MAX', '100'))
lines = []
if os.path.exists(logfile):
    try:
        with open(logfile, 'r') as f:
            lines = f.read().splitlines()
    except:
        lines = []
lines.append(msg)
if len(lines) > max_lines:
    lines = lines[-max_lines:]
os.makedirs(os.path.dirname(logfile), exist_ok=True)
with open(logfile, 'w') as f:
    f.write('\n'.join(lines) + '\n')
