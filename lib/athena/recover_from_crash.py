import json, os, time

degradation_file = os.environ.get("DEGRADATION_FILE", "")
layer = os.environ.get("CRASH_LAYER", "")
crash_type = os.environ.get("CRASH_TYPE", "")

with open(degradation_file) as f:
    data = json.load(f) if os.path.exists(degradation_file) else {}

cooldowns = data.get('recovery_cooldowns', {})
now = time.time()

if layer in cooldowns and (now - cooldowns[layer]) < 60:
    print('cooldown')
    exit(0)

if crash_type == 'ocr':
    cooldowns[layer] = now
    data['recovery_cooldowns'] = cooldowns
    data['triggers']['ocr_crash_' + layer] = now
elif crash_type == 'detector':
    cooldowns[layer] = now
    data['recovery_cooldowns'] = cooldowns
    data['triggers']['detector_crash_' + layer] = now
elif crash_type == 'llm':
    cooldowns[layer] = now
    data['recovery_cooldowns'] = cooldowns
    data['triggers']['llm_crash_' + layer] = now

with open(degradation_file, 'w') as fh:
    json.dump(data, fh, indent=2)
print('recovered')
