import json, os, math
lut_dir = os.environ.get('ATHENA_LUT_DIR', '/opt/athena/state/.luts')
os.makedirs(lut_dir, exist_ok=True)

adapt_lut = {}
for rate in range(101):
    if rate > 80:
        adapt_lut[rate] = 1.5
    elif rate > 50:
        adapt_lut[rate] = 1.0
    elif rate > 20:
        adapt_lut[rate] = 0.7
    else:
        adapt_lut[rate] = 0.5
with open(os.path.join(lut_dir, 'adapt_interval.json'), 'w') as f:
    json.dump(adapt_lut, f)

degradation_lut = {
    'body': [180, 120, 60], 'emotions': [180, 120, 60], 'continuity': [180, 120, 60],
    'attention': [90, 60, 30], 'introspection': [180, 120, 60], 'doubt': [180, 120, 60],
    'volition': [180, 120, 60], 'memory': [180, 120, 60], 'heartbeat': [180, 120, 60],
    'archive': [3600, 1800, 900], 'memory_backup': [3600, 1800, 900], 'senses': [180, 120, 60],
}
with open(os.path.join(lut_dir, 'degradation_thresholds.json'), 'w') as f:
    json.dump(degradation_lut, f)

ring_lut = {}
for mb in range(1, 257):
    keep = max(10, int(200 / math.log2(mb + 1)))
    ring_lut[mb] = keep
with open(os.path.join(lut_dir, 'ring_buffer.json'), 'w') as f:
    json.dump(ring_lut, f)
