#!/usr/bin/env python3
"""Sense poll tick - build senses JSON from env vars."""
import json, os

ts = int(os.environ['ATHENA_TS'])
cpu_cur = int(os.environ.get('ATHENA_CPU_CUR', '0') or 0)
uptime = int(os.environ.get('ATHENA_UPTIME', '0') or 0)
gov = os.environ.get('ATHENA_CPU_GOV', '?')
cpu_min = int(os.environ.get('ATHENA_CPU_MIN', '0') or 0)
cpu_max = int(os.environ.get('ATHENA_CPU_MAX', '0') or 0)
mem_total = int(os.environ.get('ATHENA_MEM_TOTAL', '0') or 0)
mem_avail = int(os.environ.get('ATHENA_MEM_AVAIL', '0') or 0)
mem_free = int(os.environ.get('ATHENA_MEM_FREE', '0') or 0)

result = {
    'ts': ts,
    'uptime_s': uptime,
    'cpu_cur_khz': cpu_cur,
    'cpu': {'gov': gov, 'min_khz': cpu_min, 'max_khz': cpu_max},
    'mem': {'total_kb': mem_total, 'avail_kb': mem_avail, 'free_kb': mem_free,
            'pct_used': (mem_total - mem_avail) * 100 // mem_total if mem_total > 0 else 0}
}

bat_str = os.environ.get('ATHENA_BAT_STR', '').strip()
if bat_str:
    try:
        result['battery'] = json.loads(bat_str)
    except:
        pass

wifi_str = os.environ.get('ATHENA_WIFI_STR', '').strip()
if wifi_str:
    try:
        result['wifi'] = json.loads(wifi_str)
    except:
        pass

dev_str = os.environ.get('ATHENA_DEV_STR', '').strip()
if dev_str:
    try:
        dev = json.loads(dev_str)
        result.update(dev)
    except:
        pass

loc_str = os.environ.get('ATHENA_LOC_STR', '').strip()
if loc_str:
    try:
        result['location'] = json.loads(loc_str)
    except:
        pass

screen_str = os.environ.get('ATHENA_SCREEN_STR', '').strip()
if screen_str:
    try:
        result['screen'] = json.loads(screen_str)
    except:
        pass

print(json.dumps(result, separators=(',',':')))
