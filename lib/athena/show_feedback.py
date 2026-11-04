import json, os

feedback_file = os.environ.get("FEEDBACK_FILE", "")

with open(feedback_file) as f:
    data = json.load(f)

print('=== Athena Daemon Feedback ===')
print()
print(f"{'Layer':<15} {'Success':>8} {'Fail':>6} {'Streak':>7} {'Adapted':>10}")
print('-' * 55)
for layer, stats in data.items():
    s = stats.get('success', 0)
    f_ = stats.get('fail', 0)
    st = stats.get('streak', 0)
    ai = stats.get('adapted_interval', 'N/A')
    if isinstance(ai, float):
        ai = f'{ai:.0f}s'
    elif isinstance(ai, int):
        ai = f'{ai}s'
    else:
        ai = 'N/A'
    print(f"{layer:<15} {s:>8} {f_:>6} {st:>+7} {ai:>10}")
