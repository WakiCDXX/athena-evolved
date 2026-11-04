#!/usr/bin/env python3
"""Extract RSSI from WiFi JSON."""
import json, os, sys

wifi_json = os.environ.get('BODY_WIFI_JSON', '')
try:
    d = json.loads(wifi_json)
    print(d.get('rssi', 0))
except:
    print(0)
