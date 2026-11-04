import json, os

data_dir = os.environ.get("DATA_DIR", "")

try:
    with open(os.path.join(data_dir, "degradation_config.json")) as f:
        data = json.load(f)
    print(','.join(data.get('layers', [])))
except:
    print('body,emotions,continuity,attention,introspection,doubt,volition,memory,heartbeat,archive,memory_backup')
