#!/usr/bin/env python3
"""Calculate storage utilization statistics."""
import os

data_dir = os.environ.get("ATHENA_DATA_DIR", "/opt/athena/state")

senses_log = os.path.join(data_dir, 'senses.log')
entries = 0
if os.path.exists(senses_log):
    with open(senses_log) as f:
        entries = sum(1 for l in f if l.strip())

hist_dir = os.path.join(data_dir, 'corpus', 'senses_historical')
hist_count = 0
hist_size = 0
if os.path.exists(hist_dir):
    for f in os.listdir(hist_dir):
        fp = os.path.join(hist_dir, f)
        if os.path.isfile(fp):
            hist_count += 1
            hist_size += os.path.getsize(fp)

train_dir = os.path.join(data_dir, 'corpus', 'training')
train_size = 0
train_count = 0
if os.path.exists(train_dir):
    for f in os.listdir(train_dir):
        fp = os.path.join(train_dir, f)
        if os.path.isfile(fp):
            train_count += 1
            train_size += os.path.getsize(fp)

print(f'  Active senses: {entries} entries (~{entries//1000}KB)')
print(f'  Archived sense batches: {hist_count} files (~{hist_size//1024//1024}MB)')
print(f'  Training files: {train_count} files (~{train_size//1024}KB)')
print(f'  Daily growth estimate: ~{(entries * 1024 + hist_size // 3600) // 1024}KB/day from senses alone')
print(f'  Projected 250GB fill: ~{250 * 1024 * 1024 // max(1, (entries * 1024 + hist_size // 3600)) // 365:.0f} years')
