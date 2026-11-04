#!/usr/bin/env python3
# adapter: .json policy -> daemon-compatible bash/python mapping
# Place: .local/lib/python/athena/adapter_policy.py

import json
import sys

def load_policy(path):
    with open(path) as f:
        return json.load(f)

def map_memory_thresholds(policy):
    """Convert policy max/min_memory_kb to degradation_state ladder."""
    p = policy.get("policy", {})
    max_kb = p.get("max_memory_kb", 307200)
    min_kb = p.get("min_memory_kb", 153600)
    # Map to degradation ladder: normal/conserve/minimal/suspended/safe_shutdown
    thresholds = {
        "normal": max_kb,
        "conserve": int(max_kb * 0.75),
        "minimal": int(min_kb * 1.25),
        "suspended": min_kb,
        "safe_shutdown": int(min_kb * 0.5)
    }
    return thresholds

def generate_interval_env(policy):
    """Generate bash env line for interval."""
    layer = policy.get("layer_name", "layer").upper()
    interval = policy.get("interval_base", 120)
    return f"INTERVAL_{layer}={interval}"

def adapt_for_daemon(policy_path, output_mode="bash"):
    policy = load_policy(policy_path)
    if output_mode == "bash":
        print(generate_interval_env(policy))
        thresholds = map_memory_thresholds(policy)
        for state, kb in thresholds.items():
            print(f"# {state}: {kb}KB (mapped from policy)")
    return policy

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: adapter_policy.py <policy.json> [bash|python]")
        sys.exit(1)
    adapt_for_daemon(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "bash")
