import os
cache_dir = os.environ.get('ATHENA_STREAM_CACHE', '/opt/athena/state/.stream_cache')
for f in os.listdir(cache_dir):
    if f.endswith('.cache'):
        os.remove(os.path.join(cache_dir, f))
print("Stream cache cleared.")
