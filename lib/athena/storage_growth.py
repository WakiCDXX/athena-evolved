#!/usr/bin/env python3
"""Calculate storage growth projections."""
import os, time

data_dir = os.environ.get("ATHENA_DATA_DIR", "/opt/athena/state")
now = int(time.time())

total = 0
for root, dirs, files in os.walk(data_dir):
    for f in files:
        fp = os.path.join(root, f)
        if os.path.isfile(fp):
            total += os.path.getsize(fp)

print(f'Current total: {total / 1024 / 1024:.1f} MB')
print(f'SD card capacity: 250 GB')
print(f'Used: {total / (250 * 1024 * 1024) * 100:.2f}%')
print(f'Free: {(250 * 1024 * 1024 - total) / (1024 * 1024):.1f} MB')
print()

senses_per_day = 1440
senses_per_day_kb = senses_per_day * 0.7
archive_per_day_mb = senses_per_day_kb / 1024
training_per_day_kb = 50
emb_per_day_kb = 10

daily_total_mb = archive_per_day_mb + training_per_day_kb / 1024 + emb_per_day_kb / 1024 + 0.1
print(f'Daily growth: ~{daily_total_mb:.1f} MB/day')
print(f'Days to fill 250GB: ~{250 * 1024 / daily_total_mb:.0f} days')
print(f'Years to fill 250GB: ~{250 * 1024 / daily_total_mb / 365:.1f} years')
