#!/usr/bin/env python3
"""Read and print a JSON layer data file."""
import json
import os
data_path = os.environ.get("ATHENA_LAYER_DATA_PATH", "")
try:
    with open(data_path) as f:
        d = json.load(f)
    print(d)
except:
    print({})
