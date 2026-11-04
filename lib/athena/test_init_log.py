#!/usr/bin/env python3
"""Initialize an empty test log JSON file."""
import json, os, sys

test_log = os.environ.get("ATHENA_TEST_LOG", "")

if not test_log:
    print("ERROR: ATHENA_TEST_LOG not set", file=sys.stderr)
    sys.exit(1)

data = {"runs": [], "summary": {"total": 0, "passed": 0, "failed": 0}}
with open(test_log, "w") as f:
    json.dump(data, f, indent=2)
