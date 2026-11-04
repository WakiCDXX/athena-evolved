#!/data/data/com.termux/files/usr/bin/python3
"""
Entry point for Athena Sensor Sidecar.
Run as: python3 -m athena.sensor_sidecar
"""

import sys
import os

# Add python lib to path
sys.path.insert(0, "/root/.local/lib/python")

from athena.sensor_sidecar import main

if __name__ == "__main__":
    main()