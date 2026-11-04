#!/usr/bin/env python3
"""Show a summary report from the test log JSON file."""
import json, os, sys

test_log = os.environ.get("ATHENA_TEST_LOG", "")

if not test_log or not os.path.exists(test_log):
    print("No test data available yet.")
    sys.exit(0)

try:
    with open(test_log) as f:
        data = json.load(f)
    s = data["summary"]
    print("=== Athena Test Report ===")
    print(f"Total tests: {s['total']}")
    print(f"Passed: {s['passed']}")
    print(f"Failed: {s['failed']}")
    if s["total"] > 0:
        print(f"Pass rate: {s['passed']/s['total']*100:.1f}%")
    print()
    print("Last 10 runs:")
    for r in data["runs"][-10:]:
        status = "✅" if r["status"] == "pass" else "❌"
        print(f"  {status} {r['test']} ({r['timestamp']}): {r['details'][:80]}")
except Exception:
    print("No test data available yet.")
