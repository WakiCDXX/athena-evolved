#!/usr/bin/env python3
"""Heartbeat health check - assess all layer freshness."""
import json, os, time, sys

data_dir = os.environ.get('ATHENA_DATA_DIR', '/opt/athena/state')
heartbeat_path = os.environ.get('ATHENA_HEARTBEAT_PATH', os.path.join(data_dir, 'heartbeat.json'))
critical = int(os.environ.get('ATHENA_CRITICAL_THRESHOLD', '1800'))
stale = int(os.environ.get('ATHENA_STALE_THRESHOLD', '900'))

layers = {
    "body": "body.json",
    "emotions": "emotions.json",
    "continuity": "continuity.json",
    "attention": "attention.json",
    "introspection": "introspection.json",
    "doubt": "doubt.json",
    "volition": "volition.json",
    "memory": "memory.json",
    "senses": "senses.log",
}

def stream_timestamp(fname):
    fpath = os.path.join(data_dir, fname)
    if not os.path.exists(fpath) or os.path.getsize(fpath) == 0:
        return 0
    try:
        with open(fpath) as f:
            d = json.load(f)
            return int(d.get("last_updated", 0))
    except:
        return 0

state = {}
if os.path.exists(heartbeat_path) and os.path.getsize(heartbeat_path) > 0:
    try:
        with open(heartbeat_path) as f:
            state = json.load(f)
    except json.JSONDecodeError:
        state = {}

now_ts = int(time.time())
alerts = []
layer_status = {}

for name, fname in layers.items():
    ts = 0
    if fname.endswith(".json"):
        ts = stream_timestamp(fname)
    elif fname == "senses.log" and os.path.exists(os.path.join(data_dir, fname)):
        try:
            with open(os.path.join(data_dir, fname)) as f:
                last = f.read().strip().split("\n")[-1]
                if last:
                    ts = json.loads(last).get("ts", 0)
        except:
            ts = 0

    age = now_ts - ts if ts else now_ts
    status = "ok"
    if age > critical:
        status = "critical"
    elif age > stale:
        status = "stale"

    layer_status[name] = {"status": status, "age_seconds": age, "last_update": ts}
    if status != "ok":
        alerts.append({"layer": name, "status": status, "age_seconds": age})

state["last_check"] = now_ts
state["last_updated"] = now_ts
state["layer_status"] = layer_status
state["alerts"] = alerts
state["alert_count"] = len(alerts)
state["overall"] = "critical" if any(a["status"] == "critical" for a in alerts) else ("stale" if alerts else "healthy")

with open(heartbeat_path, "w") as f:
    json.dump(state, f, separators=(",", ":"))

print(f"Heartbeat: {state['overall']} ({len(alerts)} alerts)")
