import os
logfile = os.environ.get('ATHENA_LOG_FILE', '')
max_bytes = int(os.environ.get('ATHENA_LOG_MAX_BYTES', '51200'))
keep_lines = int(os.environ.get('ATHENA_LOG_KEEP', '50'))
if os.path.exists(logfile):
    size = os.path.getsize(logfile)
    if size > max_bytes:
        with open(logfile, 'r') as f:
            lines = f.read().splitlines()
        with open(logfile, 'w') as f:
            f.write('\n'.join(lines[-keep_lines:]) + '\n')
