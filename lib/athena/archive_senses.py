#!/usr/bin/env python3
"""Archive old sense entries from senses.log."""
import json, os, gzip, time

log_path = os.environ.get("ATHENA_SENSES_LOG", "/opt/athena/state/senses.log")
archive_dir = os.environ.get("ATHENA_ARCHIVE_DIR", "/opt/athena/state/corpus/senses_historical")
cutoff = int(os.environ.get("ATHENA_CUTOFF_SECONDS", "0"))

if cutoff == 0:
    import sys
    sys.exit(0)

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
    ts_str = time.strftime("%Y%m%d_%H%M%S", time.localtime())
    archive_file = os.path.join(archive_dir, f'senses_{ts_str}.log')
    with open(archive_file, 'w') as f:
        f.writelines(archived)
    with open(archive_file, 'rb') as f_in:
        with gzip.open(archive_file + '.gz', 'wb') as f_out:
            f_out.write(f_in.read())
    os.remove(archive_file)
    with open(log_path, 'w') as f:
        f.writelines(kept)
    print(f'Archived {len(archived)} entries to {archive_file}.gz')
