import os, sys
pipe_path = os.environ.get('ATHENA_PIPE_PATH', '')
msg = os.environ.get('ATHENA_PIPE_MSG', '')
if not os.path.exists(pipe_path):
    sys.exit(0)
try:
    fd = os.open(pipe_path, os.O_WRONLY | os.O_NONBLOCK)
    try:
        os.write(fd, msg.encode() + b'\n')
    finally:
        os.close(fd)
except (BlockingIOError, OSError):
    pass
