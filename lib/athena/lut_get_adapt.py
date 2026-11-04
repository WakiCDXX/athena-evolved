import json, os
lut_dir = os.environ.get('ATHENA_LUT_DIR', '/opt/athena/state/.luts')
rate = int(os.environ.get('ATHENA_LUT_RATE', '0'))
lut_file = os.path.join(lut_dir, 'adapt_interval.json')
if os.path.exists(lut_file):
    try:
        with open(lut_file) as f:
            lut = json.load(f)
        rate = max(0, min(100, rate))
        print(lut.get(str(rate), 1.0))
    except:
        print(1.0)
else:
    print(1.0)
