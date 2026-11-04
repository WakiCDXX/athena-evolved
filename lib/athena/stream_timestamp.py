import json, os
data_dir = os.environ.get('ATHENA_DATA_DIR', '/opt/athena/state')
layer = os.environ.get('ATHENA_LAYER', '')
fpath = os.path.join(data_dir, f'{layer}.json')
if os.path.exists(fpath) and os.path.getsize(fpath) > 0:
    try:
        with open(fpath) as f:
            d = json.load(f)
        print(d.get('last_updated', 0))
    except:
        print(0)
else:
    print(0)
