import json, os, time

feedback_file = os.environ.get("FEEDBACK_FILE", "")
layer = os.environ.get("LAYER_NAME", "")
status = os.environ.get("LAYER_STATUS", "")

with open(feedback_file) as f:
    data = json.load(f) if feedback_file and os.path.exists(feedback_file) else {}

if layer not in data:
    data[layer] = {'success': 0, 'fail': 0, 'current_interval': None, 'adapted_interval': None, 'last_run': None, 'streak': 0}

if status == 'success':
    data[layer]['success'] += 1
    data[layer]['streak'] = data[layer].get('streak', 0) + 1
else:
    data[layer]['fail'] += 1
    data[layer]['streak'] = data[layer].get('streak', 0) - 1

data[layer]['last_run'] = time.time()
streak = data[layer]['streak']
base = data[layer].get('current_interval', 60)
if streak >= 5:
    data[layer]['adapted_interval'] = min(base * 2, base + (base * 0.2 * min(streak // 5, 5)))
elif streak <= -3:
    data[layer]['adapted_interval'] = max(base * 0.5, base * 0.5)
data[layer]['current_interval'] = base

with open(feedback_file, 'w') as fh:
    json.dump(data, fh, indent=2)
