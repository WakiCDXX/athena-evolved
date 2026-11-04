import json, os, time

cache_dir = os.environ.get('ATHENA_STREAM_CACHE', '/opt/athena/state/.stream_cache')
data_dir = os.environ.get('ATHENA_DATA_DIR', '/opt/athena/state')
layer = os.environ.get('ATHENA_LAYER', '')
keys_only = os.environ.get('ATHENA_KEYS_ONLY', 'false') == 'true'
ttl = int(os.environ.get('ATHENA_STREAM_TTL', '30'))

os.makedirs(cache_dir, exist_ok=True)

cache_path = os.path.join(cache_dir, f'{layer}.cache')
fpath = os.path.join(data_dir, f'{layer}.json')

cached = False
if os.path.exists(cache_path):
    try:
        with open(cache_path) as cf:
            cache_data = json.load(cf)
        if time.time() - cache_data.get('_cache_time', 0) < ttl:
            cached = True
    except:
        cached = False

if cached:
    result = cache_data.get('data')
    if keys_only and isinstance(result, dict):
        print(result.get('last_updated', 0))
    else:
        print(json.dumps(result))
else:
    if not os.path.exists(fpath) or os.path.getsize(fpath) == 0:
        if keys_only:
            print(0)
        else:
            print(json.dumps({}))
    else:
        try:
            with open(fpath) as f:
                data = json.load(f)
            with open(cache_path, 'w') as cf:
                json.dump({'data': data, '_cache_time': time.time()}, cf)
            if keys_only:
                print(data.get('last_updated', 0))
            else:
                print(json.dumps(data))
        except:
            if keys_only:
                print(0)
            else:
                print(json.dumps({}))
