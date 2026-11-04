#!/usr/bin/env python3
"""Advisory file lock using fcntl.flock.

Helps prevent concurrent writes to shared JSON state files
(memory_backup + archive_maintenance both write body.json).
"""
import fcntl
import os
import time


def lock(path, exclusive=True, timeout=10):
    """Hold an advisory lock on a file path.

    Args:
        path: file path to lock
        exclusive: True = write lock, False = shared read lock
        timeout: seconds to wait before raising TimeoutError

    Returns:
        open file object (must be passed to unlock())

    Raises:
        TimeoutError: if lock cannot be acquired within timeout
    """
    op = fcntl.LOCK_EX if exclusive else fcntl.LOCK_SH
    # Ensure parent dir exists
    parent = os.path.dirname(path) or '.'
    os.makedirs(parent, exist_ok=True)
    fp = open(path, 'w')
    end = time.time() + timeout
    while True:
        try:
            fcntl.flock(fp.fileno(), op | fcntl.LOCK_NB)
            return fp
        except (IOError, OSError):
            if time.time() >= end:
                fp.close()
                raise TimeoutError(f"Could not acquire {'exclusive' if exclusive else 'shared'} lock within {timeout}s")
            time.sleep(0.1)


def unlock(fp):
    """Release advisory lock and close file."""
    fcntl.flock(fp.fileno(), fcntl.LOCK_UN)
    fp.close()


def atomic_write(path, data, timeout=10):
    """Write JSON data to path with advisory file locking.

    Uses tempfile + os.replace for atomicity, plus flock
    to prevent concurrent readers from seeing partial data.
    """
    import json
    import tempfile

    parent = os.path.dirname(path) or '.'
    tmp_fd, tmp_path = tempfile.mkstemp(dir=parent, suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w') as f:
            lock_f = lock(path + '.lock', exclusive=True, timeout=timeout)
            try:
                json.dump(data, f, indent=2)
                f.flush()
                os.fsync(f.fileno())
            finally:
                unlock(lock_f)
        os.replace(tmp_path, path)
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass