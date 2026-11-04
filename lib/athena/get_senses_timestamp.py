import json, sys

line = sys.stdin.readline().strip()
if line:
    try:
        d = json.loads(line)
        print(d.get('ts', 0))
    except:
        print(0)
else:
    print(0)
