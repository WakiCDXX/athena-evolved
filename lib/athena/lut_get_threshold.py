import json, os
lut_dir = os.environ.get('ATHENA_LUT_DIR', '/opt/athena/state/.luts')
layer = os.environ.get('ATHENA_LAYER', '')
level = os.environ.get('ATHENA_LUT_LEVEL', 'normal')
lut_file = os.path.join(lut_dir, 'degradation_thresholds.json')
if os.path.exists(lut_file):
    try:
        with open(lut_file) as f:
            lut = json.load(f)
        thresholds = lut.get(layer, [180, 120, 60])
        level_map = {'normal': 0, 'conserve': 1, 'minimal': 2, 'suspended': 3}
        idx = level_map.get(level, 0)
        print(thresholds[idx] if idx < len(thresholds) else thresholds[0])
    except:
        print(180)
else:
    print(180)
