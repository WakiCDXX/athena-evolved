import re

with open('/data/data/com.termux/files/usr/lib/node_modules/@twigpine/openclaude/dist/cli.mjs', 'r') as f:
    content = f.read()

# Change the default timeout from 1500ms to 30000ms (30 seconds)
old = 'SESSION_END_HOOK_TIMEOUT_MS_DEFAULT=1500'
new = 'SESSION_END_HOOK_TIMEOUT_MS_DEFAULT=30000'

if old in content:
    content = content.replace(old, new)
    with open('/data/data/com.termux/files/usr/lib/node_modules/@twigpine/openclaude/dist/cli.mjs', 'w') as f:
        f.write(content)
    print(f"SUCCESS: Changed timeout from 1500ms to 30000ms")
else:
    print("ERROR: Constant not found")

