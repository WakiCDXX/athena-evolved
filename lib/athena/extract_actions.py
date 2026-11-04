import json
import sys

# Read JSON from stdin and print each action on a separate line
data = json.load(sys.stdin)
for action in data.get("actions", []):
    print(action)
