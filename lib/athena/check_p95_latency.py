import json, os

data_dir = os.environ.get("DATA_DIR", "")
latency_file = os.path.join(data_dir, "daemon_latency.json")

try:
    with open(latency_file) as f:
        data = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    data = {}
    times = sorted(data.get('recent_latencies', []))
    if len(times) >= 10:
        print(times[int(len(times) * 0.95)])
    else:
        print(0)
except:
    print(0)
