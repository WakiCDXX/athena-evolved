#!/usr/bin/env python3
"""Dump session context to JSON snapshot."""
import json, os, time

data_dir = os.environ.get("DATA", "/opt/athena/state")
out_path = os.environ.get("SESSION_FILE", os.path.join(data_dir, "session_context.json"))

layers = {}
for name in ["body", "emotions", "continuity", "attention", "introspection", "doubt", "volition", "memory", "heartbeat"]:
    fpath = os.path.join(data_dir, f"{name}.json")
    try:
        with open(fpath) as f:
            layers[name] = json.load(f)
    except:
        layers[name] = {"error": "not found"}

for name in ["ratelimit"]:
    fpath = os.path.join(data_dir, f"{name}.json")
    try:
        with open(fpath) as f:
            layers[name] = json.load(f)
    except:
        pass

senses_path = os.path.join(data_dir, "senses.log")
senses_tail = []
try:
    with open(senses_path) as f:
        lines = f.readlines()
        senses_tail = [l.strip() for l in lines[-5:]]
except:
    pass

snapshot = {
    "timestamp": int(time.time()),
    "iso_time": time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime()),
    "model": os.environ.get("OPENAI_MODEL", "unknown"),
    "layers": layers,
    "senses_recent": senses_tail,
    "active_concerns": layers.get("attention", {}).get("concerns", []),
    "pending_tasks": [],
}

try:
    with open(out_path) as f:
        existing = json.load(f)
        if "pending_tasks" in existing:
            snapshot["pending_tasks"] = existing.get("pending_tasks", [])
        if "conversation_summary" in existing:
            snapshot["conversation_summary"] = existing["conversation_summary"]
except:
    pass

with open(out_path, "w") as f:
    json.dump(snapshot, f, indent=2)

print(f"Session context dumped to {out_path}")
print(f"Model: {snapshot['model']}")
print(f"Concerns: {len(snapshot['active_concerns'])}")
print(f"Senses: {len(senses_tail)} recent entries")
