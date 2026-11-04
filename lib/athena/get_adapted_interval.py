import json, os

feedback_file = os.environ.get("FEEDBACK_FILE", "")
layer = os.environ.get("LAYER_NAME", "")
base_interval = os.environ.get("BASE_INTERVAL", "")

with open(feedback_file) as f:
    data = json.load(f) if feedback_file and os.path.exists(feedback_file) else {}

if layer in data and data[layer].get('adapted_interval'):
    print(int(data[layer]['adapted_interval']))
else:
    print(base_interval)
