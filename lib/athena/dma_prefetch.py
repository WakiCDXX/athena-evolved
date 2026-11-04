import os
data_dir = os.environ.get('ATHENA_DATA_DIR', '/opt/athena/state')
fname = os.environ.get('ATHENA_DMA_FILE', '')
fpath = os.path.join(data_dir, fname)
if os.path.exists(fpath):
    try:
        fd = os.open(fpath, os.O_RDONLY)
        try:
            os.posix_fadvise(fd, 0, 0, os.POSIX_FADV_SEQUENTIAL)
            os.posix_fadvise(fd, 0, 0, os.POSIX_FADV_WILLNEED)
        finally:
            os.close(fd)
    except:
        pass
