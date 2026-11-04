import json, os
lut_dir = os.environ.get('ATHENA_LUT_DIR', '/opt/athena/state/.luts')
max_bytes = int(os.environ.get('ATHENA_RING_MAX_BYTES', '51200'))
lut_file = os.path.join(lut_dir, 'ring_buffer.json')
if os.path.exists(lut_file):
    try:
        with open(lut_file) as f:
            lut = json.load(f)
        mb = max(1, min(256, max_bytes // 1024))
        keys = sorted(int(k) for k in lut.keys())
        closest = min(keys, key=lambda k: abs(k - mb))
        print(lut[str(closest)])
    except:
        print(50)
else:
    print(50)
