#!/usr/bin/env python3
"""Archive old sense entries."""
import json, os, sys

log_path = os.environ.get('SENSES_LOG_PATH', '')
archive_path = os.environ.get('SENSES_ARCHIVE_PATH', '')
cutoff = int(os.environ.get('SENSES_CUTOFF', '0'))

if not log_path or not archive_path:
    sys.exit(1)

try:
    with open(log_path) as f:
        lines = f.readlines()
    archived = []
    kept = []
    for l in lines:
        try:
            d = json.loads(l.strip())
            if d.get('ts', 0) < cutoff:
                archived.append(l)
            else:
                kept.append(l)
        except:
            kept.append(l)
    if archived:
        with open(archive_path, 'w') as f:
            f.writelines(archived)
        with open(log_path, 'w') as f:
            f.writelines(kept)
        print(f'Archived {len(archived)} old sense entries')
except Exception as e:
    print(f'Archive error: {e}')
