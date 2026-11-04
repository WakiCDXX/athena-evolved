import json, os, time, hashlib

session_state_file = os.environ.get("SESSION_STATE_FILE", "")
screen_hash = os.environ.get("SCREEN_HASH", "")
base_interval = os.environ.get("BASE_INTERVAL", "")

with open(session_state_file) as f:
    sess = json.load(f)

mode = sess.get('mode', 'event_driven')
last_change = sess.get('last_screen_change', 0)
current_hash = sess.get('screen_hash', '')

stable = (current_hash and current_hash == screen_hash)
time_since_change = time.time() - last_change

# Conservative intervals for low-RAM device (1.8GB)
# Event-driven should not trigger sub-minute polling on this hardware
if mode == 'event_driven':
    if stable and time_since_change > 300:
        print(120)    # stable > 5 min: check every 2 minutes
    elif stable and time_since_change > 60:
        print(60)     # stable > 1 min: check every minute
    elif stable and time_since_change > 30:
        print(30)     # stable > 30s: check every 30s
    elif time_since_change > 10:
        print(30)     # recent change: check every 30s
    else:
        print(30)     # active interaction: check every 30s (MIN_EVENT_INTERVAL floor)
elif mode == 'quiet':
    print(120)
elif mode == 'interactive':
    print(30)
else:
    print(base_interval)
