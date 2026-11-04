import json, os
DATA_DIR = "/storage/emulated/0/Android/data/com.termux/files/athena_data"
cfg = os.path.join(DATA_DIR, "degradation_config.json")
with open(cfg) as f:
    data = json.load(f)
if "layers" not in data:
    data["layers"] = []
for layer in ["openappa", "archestra", "vera_cpu"]:
    if layer not in data["layers"]:
        data["layers"].append(layer)
with open(cfg, "w") as f:
    json.dump(data, f, indent=2)
print("Updated layers:", data["layers"])
