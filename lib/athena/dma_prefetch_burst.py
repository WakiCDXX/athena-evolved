import os
data_dir = os.environ.get('ATHENA_DATA_DIR', '/opt/athena/state')
files_str = os.environ.get('ATHENA_DMA_FILES', '')
files = files_str.split()
for fname in files:
    fpath = os.path.join(data_dir, fname)
    if os.path.exists(fpath):
        try:
            fd = os.open(fpath, os.O_RDONLY)
            os.posix_fadvise(fd, 0, 0, os.POSIX_FADV_SEQUENTIAL)
            os.posix_fadvise(fd, 0, 0, os.POSIX_FADV_WILLNEED)
            os.close(fd)
        except:
            pass
