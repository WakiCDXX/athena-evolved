#!/usr/bin/env python3
"""Analyze screen to hypothesize content (interact probe)."""
import json, os, sys

screen_file = os.environ.get('PROBE_SCREEN_FILE', '')
if not screen_file or not os.path.exists(screen_file):
    print(json.dumps({'error': 'no screen file'}))
    sys.exit(1)

try:
    from PIL import Image, ImageStat
    img = Image.open(screen_file).convert('RGB')
    w, h = img.size
    findings = []

    top = img.crop((0, 0, w, int(h*0.08)))
    top_stat = ImageStat.Stat(top.convert('RGB'))
    top_mean = sum(top_stat.mean) / 3
    if top_mean < 50:
        findings.append('status_bar_present')

    bottom = img.crop((0, int(h*0.92), w, h))
    bottom_stat = ImageStat.Stat(bottom.convert('RGB'))
    bottom_mean = sum(bottom_stat.mean) / 3
    if bottom_mean < 40:
        findings.append('navigation_bar_present')

    center = img.crop((int(w*0.1), int(h*0.15), int(w*0.9), int(h*0.65)))
    center_stat = ImageStat.Stat(center.convert('RGB'))
    center_rms = sum(center_stat.rms) / 3
    if center_rms > 30:
        findings.append('interactive_content_present')

    dialog_zone = img.crop((int(w*0.2), int(h*0.75), int(w*0.8), int(h*0.9)))
    dialog_stat = ImageStat.Stat(dialog_zone.convert('RGB'))
    dialog_rms = sum(dialog_stat.rms) / 3
    if dialog_rms > 25:
        findings.append('dialog_buttons_present')

    actions = []
    if 'dialog_buttons_present' in findings:
        actions.append('tap_center_bottom')
    if 'interactive_content_present' in findings and 'dialog_buttons_present' not in findings:
        actions.append('tap_center_content')
    if 'navigation_bar_present' in findings and 'dialog_buttons_present' not in findings:
        actions.append('navigate')
    if not findings:
        actions.append('observe')

    result = {
        'screen': f'{w}x{h}',
        'findings': findings,
        'recommended_actions': actions,
        'method': 'Enigma/Bombe hypothesis generation'
    }
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({'error': str(e)}))
