#!/usr/bin/env python3
"""Run assessment on all consciousness layers."""
import json, os, time, sys

sys.path.insert(0, os.path.dirname(__file__) or '.')
from filelock import lock, unlock

data_dir = os.environ.get('ASSESS_DATA_DIR', '/opt/athena/state')
now_ts = int(time.time())


def read_locked(path):
    """Read JSON file with shared lock for inter-layer consistency."""
    lock_path = path + '.lock'
    try:
        fp = lock(lock_path, exclusive=False, timeout=5)
        try:
            with open(path) as f:
                return json.load(f)
        finally:
            unlock(fp)
    except (json.JSONDecodeError, FileNotFoundError, TimeoutError):
        return {}


heartbeat = read_locked(os.path.join(data_dir, "heartbeat.json"))
attention = read_locked(os.path.join(data_dir, "attention.json"))
session = read_locked(os.path.join(data_dir, "session_context.json"))

layer_status = heartbeat.get("layer_status", {})
alerts = heartbeat.get("alerts", [])
concerns = attention.get("concerns", [])
tasks = session.get("pending_tasks", [])

critical_layers = [a["layer"] for a in alerts if a["status"] == "critical"]
stale_layers = [a["layer"] for a in alerts if a["status"] == "stale"]

assessment = {
    "timestamp": now_ts,
    "overall": "healthy",
    "critical_layers": critical_layers,
    "stale_layers": stale_layers,
    "concern_count": len(concerns),
    "task_count": len(tasks),
    "needs_attention": bool(critical_layers or stale_layers or concerns),
    "actions": []
}

if critical_layers:
    assessment["actions"].append("restart_critical_layers")
    assessment["overall"] = "critical"
elif stale_layers:
    assessment["actions"].append("refresh_stale_layers")
    assessment["overall"] = "stale"

if concerns:
    assessment["actions"].append("review_concerns")

if tasks:
    assessment["actions"].append("process_tasks")

if not assessment["actions"]:
    assessment["actions"].append("idle")

print(json.dumps(assessment))
