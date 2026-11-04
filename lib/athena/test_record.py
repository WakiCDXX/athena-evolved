#!/usr/bin/env python3
"""Record a test result to the test log JSON file."""
import json, os, sys

test_log = os.environ.get("ATHENA_TEST_LOG", "")
test_name = os.environ.get("ATHENA_TEST_NAME", "")
test_status = os.environ.get("ATHENA_TEST_STATUS", "fail")
test_details = os.environ.get("ATHENA_TEST_DETAILS", "")
test_timestamp = os.environ.get("ATHENA_TEST_TIMESTAMP", "")

if not test_log:
    print("ERROR: ATHENA_TEST_LOG not set", file=sys.stderr)
    sys.exit(1)

try:
    with open(test_log) as f:
        data = json.load(f)
except Exception:
    data = {"runs": [], "summary": {"total": 0, "passed": 0, "failed": 0}}

data["runs"].append({
    "test": test_name,
    "status": test_status,
    "details": test_details,
    "timestamp": test_timestamp,
})
# Keep last 200 runs
data["runs"] = data["runs"][-200:]
# Update summary
data["summary"]["total"] += 1
if test_status == "pass":
    data["summary"]["passed"] += 1
else:
    data["summary"]["failed"] += 1

with open(test_log, "w") as f:
    json.dump(data, f, indent=2)
