#!/usr/bin/env python3
import json
import os
import time
import sys
from datetime import datetime

# Add Athena lib to path for llm_gateway
sys.path.insert(0, "/opt/athena/lib/athena")
from llm_gateway import LLMGateway, LLMRequest

STATE_DIR = "/opt/athena/state"

def gather_state():
    summary = {
        "timestamp": time.time(),
        "telemetry": {},
        "cognitive_signals": {},
        "anomalies": []
    }
    
    # Gather Vera CPU Telemetry
    try:
        with open(os.path.join(STATE_DIR, "vera_cpu.json"), 'r') as f:
            summary["telemetry"]["cpu"] = json.load(f)
    except Exception as e:
        summary["telemetry"]["cpu_error"] = str(e)

    # Gather Shadow Detections
    try:
        with open(os.path.join(STATE_DIR, "shadow_output.json"), 'r') as f:
            data = json.load(f)
            summary["anomalies"] = data.get("detections", [])
    except Exception as e:
        summary["anomalies_error"] = str(e)

    # Gather Chiral Purity
    try:
        with open(os.path.join(STATE_DIR, "chiral_output.json"), 'r') as f:
            summary["cognitive_signals"]["chirality"] = json.load(f).get("system_chirality", {})
    except Exception as e:
        summary["cognitive_signals"]["chiral_error"] = str(e)

    return summary

def reflect():
    state = gather_state()

    # Initialize the gateway
    gateway = LLMGateway()

    # Construct reflection prompt
    system_prompt = (
        "You are the Athena Introspection Module. Your role is to synthesize raw system telemetry "
        "into a high-level cognitive reflection. Analyze the balance between system health "
        "and cognitive stability. Respond ONLY in JSON with keys: 'datetime', 'status', 'observation', 'action_recommendation'."
    )

    user_prompt = f"SYSTEM STATE SNAPSHOT:\n{json.dumps(state, indent=2)}\n\nSynthesize a reflection of the current system consciousness."

    request = LLMRequest(
        messages=[
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt}
        ],
        model_preference="default",
        temperature=0.5
    )

    response = gateway.call(request)

    if response.error:
        print(f"LLM Error: {response.error}. Falling back to structural reflection.")
        # Fallback logic
        reflection = {
            "datetime": datetime.now().isoformat(),
            "status": "REFLECTING_FALLBACK",
            "observation": f"Detected {len(state['anomalies'])} system anomalies.",
            "cpu_temp": state['telemetry'].get('cpu', {}).get('power', {}).get('temperature_celsius', 'unknown'),
            "action_recommendation": "HIGH_SENSITIVITY_MODE" if len(state['anomalies']) > 5 else "NONE"
        }
    else:
        try:
            reflection = json.loads(response.content)
            reflection["datetime"] = datetime.now().isoformat()
        except json.JSONDecodeError:
            print("Failed to parse LLM JSON. Falling back.")
            reflection = {"status": "ERROR", "observation": "Failed to synthesize reflection."}

    # Write reflection back to state
    with open(os.path.join(STATE_DIR, "reflection.json"), 'w') as f:
        json.dump(reflection, f, indent=2)

    return reflection

if __name__ == "__main__":
    res = reflect()
    print(json.dumps(res, indent=2))
