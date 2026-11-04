#!/usr/bin/env python3
"""Poll peer agent status."""
import json, os, glob

peer_dir = os.environ['_PEER_DIR']
peers = []
for f in glob.glob(os.path.join(peer_dir, '*.json')):
    try:
        with open(f) as fh:
            data = json.load(fh)
        pid_file = f.replace('.json', '.pid')
        status = 'running'
        if os.path.exists(pid_file):
            try:
                with open(pid_file) as pf:
                    pid = int(pf.read().strip())
                try:
                    os.kill(pid, 0)
                except OSError:
                    status = 'finished'
            except:
                pass
        else:
            status = 'finished'
        data['current_status'] = status
        peers.append(data)
    except:
        pass

for p in sorted(peers, key=lambda x: x.get('started', 0), reverse=True):
    print(json.dumps(p, indent=2))
