import json, os

degradation_file = os.environ.get("DEGRADATION_FILE", "")

try:
    with open(degradation_file) as f:
        data = json.load(f)
    print(data.get('state', 'normal'))
except:
    print('normal')
