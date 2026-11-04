#!/usr/bin/env python3
"""Generate Jarvis-style narration text from conversation history."""
import json, os, random, sys

history_file = os.environ.get("ATHENA_HISTORY_FILE", "")
user_name = os.environ.get("ATHENA_USER_NAME", "user")

if not history_file or not os.path.exists(history_file):
    last = None
else:
    try:
        with open(history_file) as f:
            lines = [l.strip() for l in f if l.strip()]
        last = None
        for line in reversed(lines[-20:]):
            try:
                d = json.loads(line)
                if d.get("display") and d["display"] != "exit":
                    last = d["display"]
                    break
            except Exception:
                continue
    except Exception:
        last = None

if not last:
    last = "task complete"

phrases = [
    "Athena has processed your request, {user}.",
    "Task completed, {user}.",
    "Understood, {user}.",
    "Affirmative, {user}.",
    "Processing complete, {user}.",
    "Athena reports, {user}.",
    "Acknowledged, {user}.",
    "All systems nominal, {user}.",
]

phrase = random.choice(phrases)
result = phrase.format(user=user_name)

if last and len(str(last)) > 3:
    context = random.choice(
        [" regarding your inquiry.", " as requested.", " proceeding as directed."]
    )
    result += context

print(result)
