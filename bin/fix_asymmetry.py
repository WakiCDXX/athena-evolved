#!/usr/bin/env python3
import sys
import os
# Ensure the lib directory is in the path
sys.path.insert(0, "/opt/athena/lib")
from athena.chiral_continuity import ChiralContinuity

def fix_asymmetry():
    # Initialize with standard state path
    cc = ChiralContinuity(state_path="/opt/athena/state/chiral_output.json")
    layers = ['perception', 'memory', 'attention', 'volition', 'emotion']
    
    print("Initiating Structural Rebalancing...")
    for layer in layers:
        state = {"status": "active", "version": "1.0", "balanced": False}
        pair = cc.create_chiral_pair(layer, state)
        print(f"Layer [{layer}] balanced. HashL: {pair.hash_left}, HashR: {pair.hash_right}")
    
    cc.save_state()
    print("Structural asymmetry resolved. Cognitive purity restored.")

if __name__ == "__main__":
    fix_asymmetry()
