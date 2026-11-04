import os, sys
logfile = os.environ.get('ATHENA_RING_LOG', '')
n = int(os.environ.get('ATHENA_RING_N', '20'))
if os.path.exists(logfile):
    with open(logfile, 'r') as f:
        lines = f.read().splitlines()
    print('\n'.join(lines[-n:]))
else:
    print("no_log")
