#!/usr/bin/env python3
"""Pixel-based fallback analysis when accessibility is unavailable.
Pure Python implementation — no numpy dependency."""
import json
import os
import sys
from PIL import Image

img_path = os.environ.get('VIEW_IMG', '')

try:
    img = Image.open(img_path).convert('RGB')
except Exception:
    print(json.dumps({'error': 'pixel analysis failed', 'accessibility_available': False}))
    sys.exit(0)

w, h = img.size
pixels = list(img.getdata())
total = len(pixels)

if total == 0:
    print(json.dumps({'error': 'empty image', 'accessibility_available': False}))
    sys.exit(0)

# Brightness (mean of all RGB values)
brightness = sum(sum(p) for p in pixels) / (total * 3)

# Edge density via simple gradient (Sobel-like)
gray = [sum(p) / 3 for p in pixels]
edge_count = 0
for y in range(h):
    for x in range(w):
        idx = y * w + x
        if x < w - 1:
            edge_count += abs(gray[idx] - gray[idx + 1])
        if y < h - 1:
            edge_count += abs(gray[idx] - gray[idx + w])
edge_density = edge_count / (w * h * 2) if (w * h) > 0 else 0

# Color variance (population)
r_sum = sum(p[0] for p in pixels)
g_sum = sum(p[1] for p in pixels)
b_sum = sum(p[2] for p in pixels)
r_mean = r_sum / total
g_mean = g_sum / total
b_mean = b_sum / total
color_var = (sum((p[0] - r_mean) ** 2 for p in pixels) +
             sum((p[1] - g_mean) ** 2 for p in pixels) +
             sum((p[2] - b_mean) ** 2 for p in pixels)) / (total * 3)

# Screen type classification
if brightness > 200 and edge_density < 50:
    screen_type = 'blank_or_white'
elif brightness > 100 and edge_density < 100:
    screen_type = 'simple_ui'
elif edge_density > 200:
    screen_type = 'content_rich'
else:
    screen_type = 'interactive_ui'

print(json.dumps({
    'brightness': round(brightness, 1),
    'edge_density': round(edge_density, 1),
    'color_variance': round(color_var, 1),
    'screen_type': screen_type,
    'confidence': 0.3,
    'accessibility_available': False
}))
