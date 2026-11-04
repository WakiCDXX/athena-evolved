import json, os

data_dir = os.environ.get("DATA_DIR", "")
latency_file = os.path.join(data_dir, "daemon_latency.json")

with open(latency_file, 'w') as f:
    json.dump({'recent_latencies': [], 'window_start': 0}, f, indent=2)
