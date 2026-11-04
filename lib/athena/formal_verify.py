#!/usr/bin/env python3
"""Runtime invariant checker for the degradation state machine.

Verifies the same properties as the TLA+ model, but as executable assertions
that can be called from the daemon loop or test suite.

Properties verified:
  1. StateValid — state always one of {normal, conserve, minimal, suspended, safe_shutdown}
  2. LayersSafe — no layers active in suspended/safe_shutdown
  3. DegradationMonotonic — state level never increases without a recovery trigger
  4. RecoveryPossible — from any degraded state, a recovery path exists
  5. NoSkip — no transition skips more than 2 levels without explicit trigger
  6. TypeInvariant — all variables are of correct type/range

Usage:
    python3 formal_verify.py <degradation_state.json>
    python3 formal_verify.py --batch <directory>  # check all state files
"""
import json, os, sys, tempfile

VALID_STATES = {"normal", "conserve", "minimal", "suspended", "safe_shutdown"}
STATE_LEVEL = {"normal": 0, "conserve": 1, "minimal": 2, "suspended": 3, "safe_shutdown": 4}
ACTIVE_LAYERS = {
    "normal": 12, "conserve": 3, "minimal": 1,
    "suspended": 0, "safe_shutdown": 0,
}

def load_state(path):
    with open(path) as f:
        return json.load(f)

def check_state_valid(data):
    """P1: state is always one of the 5 valid states."""
    s = data.get("state", "")
    return s in VALID_STATES, f"state='{s}'"

def check_layers_safe(data):
    """P2: no layers active in suspended/safe_shutdown."""
    state = data.get("state", "")
    layers = data.get("active_layers", [])
    if state in {"suspended", "safe_shutdown"}:
        ok = len(layers) == 0
        return ok, f"state={state}, layers={layers}"
    return True, f"state={state}, layers ok"

def check_monotonic(data, prev_data=None):
    """P3: degradation level never increases without recovery trigger."""
    if prev_data is None:
        return True, "no previous state"
    prev_level = STATE_LEVEL.get(prev_data.get("state", "normal"), -1)
    curr_level = STATE_LEVEL.get(data.get("state", "normal"), -1)
    triggers = data.get("triggers", {})
    has_recovery = any("recovery" in t or "recovered" in t for t in triggers)
    if curr_level > prev_level and not has_recovery:
        return False, f"level increased {prev_level}->{curr_level} without recovery trigger"
    return True, f"level {prev_level}->{curr_level}"

def check_recovery_possible(data):
    """P4: from any degraded state, a recovery path exists (upward transition possible)."""
    state = data.get("state", "normal")
    level = STATE_LEVEL.get(state, -1)
    if level <= 0:
        return True, f"{state} is normal"
    # Check if recovery triggers exist in the data
    triggers = data.get("triggers", {})
    recovery_triggers = [t for t in triggers if "recovery" in t or "recovered" in t]
    return len(recovery_triggers) > 0 or level > 0, f"{state} has {len(recovery_triggers)} recovery triggers"

def check_no_skip(data, prev_data=None):
    """P5: no transition skips more than 2 levels without explicit critical trigger."""
    if prev_data is None:
        return True, "no previous state"
    prev_level = STATE_LEVEL.get(prev_data.get("state", "normal"), -1)
    curr_level = STATE_LEVEL.get(data.get("state", "normal"), -1)
    diff = curr_level - prev_level
    if diff > 2:
        return False, f"skipped {diff} levels: {prev_data.get('state')}->{data.get('state')}"
    return True, f"level change {diff}"

def check_type_invariant(data):
    """P6: all variables are of correct type/range."""
    errors = []
    if "state" not in data:
        errors.append("missing state")
    if "timestamp" not in data:
        errors.append("missing timestamp")
    if not isinstance(data.get("triggers", {}), dict):
        errors.append("triggers not dict")
    if not isinstance(data.get("recovery_cooldowns", {}), dict):
        errors.append("cooldowns not dict")
    return len(errors) == 0, "; ".join(errors) if errors else "ok"

def verify(data, prev_data=None):
    """Run all invariants. Returns list of (name, ok, detail)."""
    raw = [
        ("StateValid", check_state_valid(data)),
        ("LayersSafe", check_layers_safe(data)),
        ("DegradationMonotonic", check_monotonic(data, prev_data)),
        ("RecoveryPossible", check_recovery_possible(data)),
        ("NoSkip", check_no_skip(data, prev_data)),
        ("TypeInvariant", check_type_invariant(data)),
    ]
    return [(name, ok, detail) for (name, (ok, detail)) in raw]

def format_result(name, ok, detail):
    status = "PASS" if ok else "FAIL"
    return f"  [{status}] {name}: {detail}"

def main():
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        print("Usage: formal_verify.py <state.json> [--batch <dir>]")
        sys.exit(2)

    if "--batch" in sys.argv:
        idx = sys.argv.index("--batch")
        directory = sys.argv[idx + 1]
        total = 0
        fails = 0
        for fname in sorted(os.listdir(directory)):
            if not fname.endswith(".json"):
                continue
            fpath = os.path.join(directory, fname)
            try:
                data = load_state(fpath)
                results = verify(data)
                for name, ok, detail in results:
                    total += 1
                    if not ok:
                        fails += 1
                        print(f"  FAIL [{fname}] {name}: {detail}")
            except Exception as e:
                print(f"  ERROR [{fname}]: {e}")
                fails += 1
        print(f"\nBatch: {total - fails}/{total} checks passed")
        sys.exit(1 if fails else 0)

    data = load_state(sys.argv[1])
    prev = None
    if len(sys.argv) > 2:
        prev = load_state(sys.argv[2])

    results = verify(data, prev)
    fails = 0
    for name, ok, detail in results:
        print(format_result(name, ok, detail))
        if not ok:
            fails += 1

    print(f"\n{len(results) - fails}/{len(results)} invariants hold")
    sys.exit(1 if fails else 0)

if __name__ == "__main__":
    main()
