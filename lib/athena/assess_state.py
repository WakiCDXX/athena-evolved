#!/usr/bin/env python3
"""Assess current consciousness layer state and return JSON assessment."""
import json
import os
import time

data_dir = os.environ.get("ATHENA_DATA_DIR", "/opt/athena/state")
now_ts = int(time.time())

# Load heartbeat
heartbeat = {}
hb_path = os.path.join(data_dir, "heartbeat.json")
if os.path.exists(hb_path) and os.path.getsize(hb_path) > 0:
    try:
        with open(hb_path) as f:
            heartbeat = json.load(f)
    except:
        pass

# Load attention for concerns
attention = {}
att_path = os.path.join(data_dir, "attention.json")
if os.path.exists(att_path) and os.path.getsize(att_path) > 0:
    try:
        with open(att_path) as f:
            attention = json.load(f)
    except:
        pass

# Load session context for tasks
session = {}
sess_path = os.path.join(data_dir, "session_context.json")
if os.path.exists(sess_path) and os.path.getsize(sess_path) > 0:
    try:
        with open(sess_path) as f:
            session = json.load(f)
    except:
        pass

# Build assessment
layer_status = heartbeat.get("layer_status", {})
alerts = heartbeat.get("alerts", [])
concerns = attention.get("concerns", [])
tasks = session.get("pending_tasks", [])

# Determine overall state
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

# Decide what to do
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
