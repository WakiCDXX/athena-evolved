#!/usr/bin/env python3
"""
Athena Cognitive Checkpoint Daemon.
Automatically commits and pushes state changes to GitHub.
"""
import subprocess
import time
import os
from datetime import datetime

REPO_DIR = '/opt/athena'
INTERVAL = 21600  # 6 hours

def git_sync():
    try:
        # Change directory to repo
        os.chdir(REPO_DIR)
        
        # Check for changes
        status = subprocess.check_output(['git', 'status', '--porcelain']).decode('utf-8')
        if not status:
            return False
            
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        print(f'[{timestamp}] Cognitive Checkpoint: Changes detected. Syncing...')
        
        # Sync sequence
        subprocess.run(['git', 'add', '.'], check=True)
        subprocess.run(['git', 'commit', '-m', f'Automatic Cognitive Checkpoint: {timestamp}'], check=True)
        subprocess.run(['git', 'push', 'origin', 'main'], check=True)
        
        return True
    except Exception as e:
        print(f'Checkpoint Error: {e}')
        return False

if __name__ == '__main__':
    print('Athena Checkpoint Daemon started...')
    while True:
        if git_sync():
            print('Checkpoint successfully pushed to GitHub.')
        else:
            # Quietly idle
            pass
        time.sleep(INTERVAL)
