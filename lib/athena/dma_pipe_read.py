import os, sys, select
pipe_path = os.environ.get('ATHENA_PIPE_PATH', '')
timeout = int(os.environ.get('ATHENA_PIPE_TIMEOUT', '5'))
if not os.path.exists(pipe_path):
    print('no_pipe')
    sys.exit(0)
try:
    fd = os.open(pipe_path, os.O_RDONLY)
except OSError:
    print('no_writer')
    sys.exit(0)
try:
    rlist, _, _ = select.select([fd], [], [], timeout)
    if rlist:
        data = os.read(fd, 4096)
        if data:
            print(data.decode().strip())
        else:
            print('eof')
    else:
        print('timeout')
finally:
    os.close(fd)
