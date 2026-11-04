#!/usr/bin/env python3
"""Process introspection query."""
import json, os, sys

state_path = os.environ.get('INTROSPECTION_STATE_PATH', '')
question = os.environ.get('INTROSPECTION_QUESTION', '')

if not state_path or not os.path.exists(state_path):
    print("No self-report available. Run report first.")
    sys.exit(1)

with open(state_path) as f:
    state = json.load(f)

report = state.get('last_self_report')
if not report:
    print("No self-report available. Run report first.")
    sys.exit(1)

q = question.lower()

if 'battery' in q:
    b = report['body']['battery_pct']
    s = report['body']['battery_status']
    print(f'Battery: {b}% ({s})')
elif 'emotion' in q or 'feel' in q:
    e = report['emotions']
    print(f'Engagement: {e["engagement"]}, Concern: {e["concern"]}, Trust: {e["trust"]}')
elif 'attention' in q or 'focus' in q or 'task' in q:
    a = report['attention']
    print(f'Active: {a["active"]} ({a["active_desc"]})')
    print(f'Background tasks: {a["background_count"]}')
    print(f'Concerns: {a["concerns"]}')
elif 'thermal' in q or 'temp' in q or 'hot' in q:
    b = report['body']
    print(f'Thermal zones: {b["thermal_zones"]}°C, Throttling: {b["throttling"]}')
elif 'memory' in q or 'storage' in q or 'disk' in q:
    b = report['body']
    print(f'Storage: {b["storage_pct"]}% used')
elif 'network' in q or 'wifi' in q or 'signal' in q:
    b = report['body']
    print(f'Network: {b["network_type"]}, Signal: {b["signal_dbm"]} dBm')
elif 'session' in q or 'uptime' in q or 'long' in q:
    c = report['continuity']
    print(f'Session #{report["session"]}, Total uptime: {c["total_uptime_s"]}s, Narrative entries: {c["narrative_entries"]}')
elif 'health' in q or 'okay' in q or 'status' in q:
    b = report['body']
    e = report['emotions']
    bat = b['battery_pct']
    concern = e['concern']
    throttling = b['throttling']
    status = 'OK'
    if bat and bat < 15: status = 'CRITICAL - Battery low'
    elif bat and bat < 30: status = 'WARNING - Battery low'
    if concern > 70: status += ', High concern'
    if throttling: status += ', Thermal throttling'
    print(f'Overall: {status}')
else:
    print('Query not understood. Try: battery, emotions, attention, thermal, storage, network, session, health')
