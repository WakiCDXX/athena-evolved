#!/usr/bin/env python3
"""
Athena Satellite Bridge
Role: Server-side listener for Project Janus Satellite Nodes.
"""
import json
import os
import time
from typing import Dict, Any, Optional
from threading import Thread
from flask import Flask, request, jsonify

app = Flask(__name__)
STATE_DIR = "/opt/athena/state"

class SatelliteBridge:
    def __init__(self):
        self.active_nodes = {}
        self.last_syncs = {}

    def handle_payload(self, payload: Dict[str, Any]):
        """Route payload based on type: percept or chiral_sync."""
        p_type = payload.get("type")
        timestamp = payload.get("timestamp", time.time())
        node_id = payload.get("node_id", "unknown_satellite")

        if p_type == "percept":
            return self._process_percept(node_id, payload["data"], timestamp)
        elif p_type == "chiral_sync":
            return self._process_chiral_sync(node_id, payload["data"], timestamp)
        
        return {"status": "error", "message": "unknown payload type"}, 400

    def _process_percept(self, node_id, data, timestamp):
        """Integrate remote sensing data into the main sensor state."""
        # Update the main sensor.json with a remote-node prefix
        sensor_file = os.path.join(STATE_DIR, "sensor.json")
        try:
            # Read current state
            if os.path.exists(sensor_file):
                with open(sensor_file, 'r') as f:
                    state = json.load(f)
            else:
                state = {"streams": {}}

            # Merge remote data into streams (prefixed by node_id)
            streams = state.get("streams", {})
            for s_id, readings in data.items():
                remote_id = f"{node_id}_{s_id}"
                if remote_id not in streams:
                    streams[remote_id] = []
                
                # Append new reading (simplified)
                if isinstance(readings, list):
                    streams[remote_id].extend(readings)
                else:
                    streams[remote_id].append(readings)
                
                # Keep history bounded
                streams[remote_id] = streams[remote_id][-1000:]

            state["streams"] = streams
            state["last_satellite_update"] = timestamp
            
            with open(sensor_file, 'w') as f:
                json.dump(state, f)
            
            return {"status": "success", "integrated": True}, 200
        except Exception as e:
            return {"status": "error", "message": str(e)}, 500

    def _process_chiral_sync(self, node_id, data, timestamp):
        """Store the remote chiral anchor as a redundancy backup."""
        backup_path = os.path.join(STATE_DIR, f"chiral_anchor_{node_id}.json")
        try:
            with open(backup_path, 'w') as f:
                json.dump(data, f)
            return {"status": "success", "anchor_saved": True}, 200
        except Exception as e:
            return {"status": "error", "message": str(e)}, 500

bridge = SatelliteBridge()

@app.route('/satellite', methods=['POST'])
def satellite_endpoint():
    payload = request.json
    if not payload:
        return jsonify({"status": "error", "message": "no payload"}), 400
    
    result, code = bridge.handle_payload(payload)
    return jsonify(result), code

if __name__ == "__main__":
    # Run as a lightweight background service
    app.run(host='0.0.0.0', port=8080)
