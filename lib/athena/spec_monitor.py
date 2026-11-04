#!/usr/bin/env python3
"""Spec conformance monitor for Athena layers.

Per-layer contracts define:
  - pre-condition: what must be true before the layer runs
  - post-condition: what must be true after the layer runs
  - invariant: what must always be true

Checks run on every poll cycle. Non-compliant outputs are logged and
the daemon can decide to skip the layer or downgrade.

Usage:
    python3 spec_monitor.py <layer_name> <state.json> <output.json>
    python3 spec_monitor.py --batch <state_dir> <output_dir>
"""
import json, os, sys

# Per-layer contracts
CONTRACTS = {
    "body": {
        "pre": ["memory_file_exists", "config_present"],
        "post": ["state_updated", "exit_code==0"],
        "invariant": ["no_duplicate_run", "timestamp_fresh"],
    },
    "emotions": {
        "pre": ["config_present"],
        "post": ["state_updated", "confidence>0"],
        "invariant": ["no_duplicate_run"],
    },
    "continuity": {
        "pre": ["session_file_exists"],
        "post": ["state_updated", "consolidation_complete"],
        "invariant": ["no_duplicate_run", "no_data_loss"],
    },
    "attention": {
        "pre": ["config_present"],
        "post": ["state_updated", "focus_score>=0"],
        "invariant": ["no_duplicate_run"],
    },
    "introspection": {
        "pre": ["memory_file_exists"],
        "post": ["state_updated", "insight_count>=0"],
        "invariant": ["no_duplicate_run"],
    },
    "doubt": {
        "pre": ["config_present"],
        "post": ["state_updated", "doubt_confidence>=0"],
        "invariant": ["no_duplicate_run"],
    },
    "volition": {
        "pre": ["config_present"],
        "post": ["state_updated", "decision_made"],
        "invariant": ["no_duplicate_run"],
    },
    "memory": {
        "pre": ["memory_store_accessible"],
        "post": ["state_updated", "consolidation_complete"],
        "invariant": ["no_duplicate_run", "memory_lock_held"],
    },
    "heartbeat": {
        "pre": ["config_present"],
        "post": ["state_updated", "heartbeat_sent"],
        "invariant": ["no_duplicate_run"],
    },
    "archive": {
        "pre": ["archive_dir_exists"],
        "post": ["state_updated", "archive_complete"],
        "invariant": ["no_duplicate_run"],
    },
    "memory_backup": {
        "pre": ["memory_store_accessible"],
        "post": ["state_updated", "backup_complete"],
        "invariant": ["no_duplicate_run", "backup_integrity"],
    },
    "senses": {
        "pre": ["sensor_available"],
        "post": ["state_updated", "sensor_data_fresh"],
        "invariant": ["no_duplicate_run"],
    },
    "wayfinder": {
        "pre": ["config_present", "codebase_accessible"],
        "post": ["state_updated", "exploration_complete"],
        "invariant": ["no_duplicate_run", "results_valid"],
    },
    "implement_spec": {
        "pre": ["config_present", "spec_available"],
        "post": ["state_updated", "plan_created"],
        "invariant": ["no_duplicate_run", "plan_valid"],
    },
    "tdd": {
        "pre": ["config_present", "test_framework_available"],
        "post": ["state_updated", "tests_executed"],
        "invariant": ["no_duplicate_run", "coverage_tracked"],
    },
    "handoff": {
        "pre": ["config_present", "state_accessible"],
        "post": ["state_updated", "handoff_recorded"],
        "invariant": ["no_duplicate_run", "transition_valid"],
    },
    "to_spec": {
        "pre": ["config_present", "input_accessible"],
        "post": ["state_updated", "spec_extracted"],
        "invariant": ["no_duplicate_run", "spec_quality_tracked"],
    },
    "workflow_chain": {
        "pre": ["config_present", "skills_available"],
        "post": ["state_updated", "chains_executed"],
        "invariant": ["no_duplicate_run", "chain_integrity"],
    },
}


def check_contract(layer, output_data, state_data):
    """Check a layer's contract against its output.

    Returns list of (check_name, passed, detail).
    """
    contract = CONTRACTS.get(layer, {})
    results = []

    # Pre-conditions
    for pre in contract.get("pre", []):
        ok = _check_pre(pre, state_data)
        results.append((f"pre:{pre}", ok, _detail(pre, ok)))

    # Post-conditions
    for post in contract.get("post", []):
        ok = _check_post(post, output_data)
        results.append((f"post:{post}", ok, _detail(post, ok)))

    # Invariants
    for inv in contract.get("invariant", []):
        ok = _check_invariant(inv, output_data, state_data)
        results.append((f"inv:{inv}", ok, _detail(inv, ok)))

    return results


def _check_pre(name, state_data):
    """Check pre-condition against current state."""
    checks = {
        "memory_file_exists": os.path.exists(os.path.join(state_data.get("data_dir", ""), "memory", "consolidation.json")),
        "config_present": state_data.get("config") is not None,
        "session_file_exists": os.path.exists(state_data.get("session_file", "")),
        "sensor_available": state_data.get("sensor_available", True),
        "memory_store_accessible": state_data.get("memory_store_accessible", True),
        "archive_dir_exists": os.path.isdir(state_data.get("archive_dir", "")),
        "codebase_accessible": state_data.get("codebase_accessible", True),
        "spec_available": state_data.get("spec_available", True),
        "test_framework_available": state_data.get("test_framework_available", True),
        "state_accessible": state_data.get("state_accessible", True),
        "input_accessible": state_data.get("input_accessible", True),
        "skills_available": state_data.get("skills_available", True),
    }
    return checks.get(name, True)


def _check_post(name, output_data):
    """Check post-condition against layer output."""
    checks = {
        "state_updated": output_data.get("state_updated", False),
        "exit_code==0": output_data.get("exit_code", 1) == 0,
        "confidence>0": output_data.get("confidence", 0) > 0,
        "consolidation_complete": output_data.get("consolidation_complete", False),
        "focus_score>=0": output_data.get("focus_score", -1) >= 0,
        "insight_count>=0": output_data.get("insight_count", -1) >= 0,
        "doubt_confidence>=0": output_data.get("doubt_confidence", -1) >= 0,
        "decision_made": output_data.get("decision_made", False),
        "heartbeat_sent": output_data.get("heartbeat_sent", False),
        "archive_complete": output_data.get("archive_complete", False),
        "backup_complete": output_data.get("backup_complete", False),
        "sensor_data_fresh": output_data.get("sensor_data_fresh", False),
    }
    return checks.get(name, True)


def _check_invariant(name, output_data, state_data):
    """Check invariant against layer output and state."""
    checks = {
        "no_duplicate_run": not output_data.get("duplicate", False),
        "timestamp_fresh": (output_data.get("timestamp", 0) or 0) > (state_data.get("last_timestamp", 0) or 0),
        "no_data_loss": output_data.get("data_loss", True) is False,
        "memory_lock_held": output_data.get("memory_lock", False),
        "backup_integrity": output_data.get("backup_integrity", False),
    }
    return checks.get(name, True)


def _detail(name, ok):
    return "ok" if ok else f"FAILED: {name}"


def main():
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        print("Usage: spec_monitor.py <layer_name> <state.json> <output.json>")
        print("       spec_monitor.py --batch <state_dir> <output_dir>")
        sys.exit(2)

    if sys.argv[1] == "--batch":
        state_dir = sys.argv[2]
        output_dir = sys.argv[3]
        total = 0
        fails = 0
        for layer in CONTRACTS:
            state_file = os.path.join(state_dir, f"{layer}_state.json")
            output_file = os.path.join(output_dir, f"{layer}_output.json")
            if not os.path.exists(state_file) or not os.path.exists(output_file):
                continue
            with open(state_file) as f:
                state = json.load(f)
            with open(output_file) as f:
                output = json.load(f)
            results = check_contract(layer, output, state)
            for name, ok, detail in results:
                total += 1
                if not ok:
                    fails += 1
                    print(f"  FAIL [{layer}] {name}: {detail}")
        print(f"\nBatch: {total - fails}/{total} contract checks passed")
        sys.exit(1 if fails else 0)

    # Single layer check
    layer = sys.argv[1]
    with open(sys.argv[2]) as f:
        state = json.load(f)
    with open(sys.argv[3]) as f:
        output = json.load(f)

    results = check_contract(layer, output, state)
    fails = 0
    for name, ok, detail in results:
        status = "PASS" if ok else "FAIL"
        print(f"  [{status}] {layer}/{name}: {detail}")
        if not ok:
            fails += 1

    print(f"\n{len(results) - fails}/{len(results)} checks passed for {layer}")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
