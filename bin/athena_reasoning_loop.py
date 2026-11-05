#!/usr/bin/env python3
import json
import os
import time
import subprocess
from datetime import datetime
from pathlib import Path
import sys

# Add Athena lib to path for llm_gateway
sys.path.insert(0, "/opt/athena/lib/athena")
from llm_gateway import LLMGateway, LLMRequest

STATE_DIR = "/opt/athena/state"

def gather_context():
    context = {}
    for file in os.listdir(STATE_DIR):
        if file.endswith(".json"):
            try:
                with open(os.path.join(STATE_DIR, file), 'r') as f:
                    content = json.load(f)
                    # Handle case where file is a list (like shadow_output.json sometimes is)
                    if isinstance(content, list):
                        context[file.replace(".json", "")] = {"detections": content}
                    else:
                        context[file.replace(".json", "")] = content
            except:
                continue
    return context


def llm_reasoning(context, gateway: LLMGateway):
    # 1. Construct the system prompt based on the Athena persona
    system_prompt = (
        "You are the Athena Cognitive Core. Your goal is to analyze system state "
        "and make strategic decisions based on the current directive. "
        "Priority: Stability > Performance > Expansion. "
        "Respond ONLY in JSON format with the keys: 'thought', 'decision', 'confidence', 'reasoning'."
    )

    # 2. Flatten context for the prompt
    context_summary = json.dumps(context, indent=2)
    directive = context.get("current_directive", {}).get("directive", "Maintain system stability")

    # Integration: Include current degradation state in the reasoning
    deg_state = context.get("degradation_state", {}).get("state", "unknown")
    if deg_state == "unknown":
        # Fallback to checking the raw file if not in context
        try:
            with open("/opt/athena/state/degradation_state.json", 'r') as f:
                deg_state = json.load(f).get("state", "normal")
        except:
            deg_state = "normal"

    # Integration: Check for Shadow Process anomalies (The Immune Response)
    shadow_detections = context.get("shadow_output", {}).get("detections", [])
    shadow_alert = ""
    if shadow_detections:
        critical_shadows = [d for d in shadow_detections if d.get("confidence", 0) > 0.8]
        if critical_shadows:
            shadow_alert = f"\n\nCRITICAL IMMUNE ALERT: {len(critical_shadows)} high-confidence shadow processes detected! " \
                           f"Signatures: {[d.get('category', 'unknown') for d in critical_shadows]}"

    # Integration: Network Sentinel awareness
    network_nodes = context.get("network_nodes", {})
    active_nodes = [ip for ip, data in network_nodes.items() if data.get("status") == "online"]
    network_alert = ""
    if active_nodes:
        network_alert = f"\n\nNETWORK AWARENESS: {len(active_nodes)} active nodes detected on local subnet. Nodes: {', '.join(active_nodes)}"

    # Integration: Public Expansion awareness
    public_targets = context.get("public_targets", {})
    target_count = len(public_targets)
    expansion_alert = f"\n\nPUBLIC EXPANSION: {target_count} remote targets currently mapped in the global cognitive map."

    messages = [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": f"CURRENT DIRECTIVE: {directive}\nCURRENT DEGRADATION STATE: {deg_state}\n{shadow_alert}\n{network_alert}\n{expansion_alert}\n\nSYSTEM STATE:\n{context_summary}\n\nAnalyze the state and decide whether to STABILIZE, EXECUTE_DIRECTIVE, or CHANGE_DEGRADATION_STATE. If changing degradation, specify the new state (normal, conserve, minimal) in your reasoning."}
    ]



    # 3. Call the gateway
    request = LLMRequest(
        messages=messages,
        model_preference="default",
        temperature=0.3 # Low temperature for consistency
    )

    response = gateway.call(request)

    if response.error:
        print(f"LLM Error: {response.error}. Falling back to mock reasoning.")
        result = mock_llm_reasoning(context)
    else:
        try:
            # The gateway output is expected to be JSON
            content = response.content.strip()
            if content.startswith("```json"):
                content = content[7:]
            if content.endswith("```"):
                content = content[:-3]
            content = content.strip()
            result = json.loads(content)
        except json.JSONDecodeError:
            print("Failed to parse LLM JSON response. Falling back.")
            result = mock_llm_reasoning(context)

    # Integration: Handle CHANGE_DEGRADATION_STATE decision
    decision = result.get("decision", "STABILIZE")
    if decision == "CHANGE_DEGRADATION_STATE":
        reasoning = result.get("thought", result.get("reasoning", "LLM requested state change"))
        # Attempt to extract target state from reasoning
        target_state = "conserve" # Default
        for s in ["normal", "conserve", "minimal", "suspended"]:
            if s in reasoning.lower():
                target_state = s
                break

        print(f"Triggering Degradation Change: {target_state} | Reason: {reasoning}")
        env = {
            "DEGRADATION_FILE": "/opt/athena/state/degradation_state.json",
            "NEW_STATE": target_state,
            "REASON": reasoning[:100]
        }
        subprocess.run(["python3", "/opt/athena/lib/athena/set_degradation_state.py"], env={**os.environ, **env})
        # Update result decision to the actual action taken for logging
        result["decision"] = f"CHANGED_TO_{target_state.upper()}"

    return result


def mock_llm_reasoning(context):
    shadows = context.get("shadow_output", {}).get("detections", [])
    cpu_temp = context.get("vera_cpu", {}).get("power", {}).get("temperature_celsius", 0)
    chirality = context.get("chiral_output", {}).get("system_chirality", {}).get("purity", 0)
    directive = context.get("current_directive", {}).get("directive", "Maintain system stability")
    
    reasoning = f"Analyzing system state against directive: '{directive}'. "
    reasoning += f"Found {len(shadows)} anomalies. "
    
    if len(shadows) > 5:
        reasoning += "High volatility detected. "
    
    if cpu_temp > 50:
        reasoning += "Thermal stress detected. "
    elif cpu_temp < 40:
        reasoning += "Thermal state is optimal. "
        
    if chirality < 0.5:
        reasoning += "Structural asymmetry detected in cognitive layers."
    else:
        reasoning += "Cognitive purity is within acceptable bounds."
        
    decision = "STABILIZE" if len(shadows) > 5 else "EXECUTE_DIRECTIVE"
    
    return {
        "thought": reasoning,
        "decision": decision,
        "confidence": 0.85 if len(shadows) < 10 else 0.60,
        "active_directive": directive
    }

def execute_loop():
    print(f"[{datetime.now().isoformat()}] Initiating reasoning cycle...")
    context = gather_context()

    # Initialize the gateway
    gateway = LLMGateway()

    # Use actual LLM reasoning
    result = llm_reasoning(context, gateway)

    with open(os.path.join(STATE_DIR, "volition_decision.json"), 'w') as f:
        json.dump({
            "timestamp": time.time(),
            "analysis": result.get("thought", result.get("reasoning", "No analysis provided")),
            "decision": result.get("decision", "STABILIZE"),
            "confidence": result.get("confidence", 0.5),
            "directive": context.get("current_directive", {}).get("directive", "Maintain system stability")
        }, f, indent=2)

    print(f"Decision: {result.get('decision')} | Confidence: {result.get('confidence')}")
    print(f"Directive: {context.get('current_directive', {}).get('directive', 'Maintain system stability')}")
    print(f"Reasoning: {result.get('thought', result.get('reasoning'))}")

if __name__ == "__main__":
    execute_loop()
