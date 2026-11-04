#!/usr/bin/env python3
"""
Xenobiological Athena Daemon — Single-process sequential layer runner.
Runs all xenobiological layers in sequence within ONE Python process
to avoid OOM kills from parallel python3 forks.
"""

import json, os, sys, time, importlib.util

BASE_DIR = "/root"
PYTHON_LIB = "/opt/athena/lib"
DATA_DIR = "/opt/athena/state"

sys.path.insert(0, os.path.join(PYTHON_LIB, "athena"))
sys.path.insert(0, "/opt/athena/lib/athena/mocks")

# Import all xenobiological modules
from tropical_attention import TropicalAttention
from p_adic_memory import PadicMemory
from hyperreal_perception import HyperrealPerception
from bioelectric_coupling import BioelectricCouplingLayer
from multiway_volition import MultiwayVolitionSystem as MultiwayVolition
from xna_memory import XNAMemoryStore
from shadow_detector import ShadowDetector
from aihs_healing import AIHSOrchestrator
from metabolic_attention import MetabolicAttention
from chiral_continuity import ChiralContinuity

class XenobiologicalDaemon:
    def __init__(self):
        self.layers = {
            "attention_tropical": {
                "func": self.run_attention_tropical,
                "interval": 300,
                "last_run": 0
            },
            "memory_padic": {
                "func": self.run_memory_padic,
                "interval": 300,
                "last_run": 0
            },
            "perception_nsa": {
                "func": self.run_perception_nsa,
                "interval": 300,
                "last_run": 0
            },
            "bioelectric_coupling": {
                "func": self.run_bioelectric_coupling,
                "interval": 300,
                "last_run": 0
            },
            "multiway_volition": {
                "func": self.run_multiway_volition,
                "interval": 300,
                "last_run": 0
            },
            "memory_xna": {
                "func": self.run_memory_xna,
                "interval": 600,
                "last_run": 0
            },
            "shadow_detector": {
                "func": self.run_shadow_detector,
                "interval": 600,
                "last_run": 0
            },
            "aihs_healing": {
                "func": self.run_aihs_healing,
                "interval": 300,
                "last_run": 0
            },
            "metabolic_attention": {
                "func": self.run_metabolic_attention,
                "interval": 300,
                "last_run": 0
            },
            "chiral_continuity": {
                "func": self.run_chiral_continuity,
                "interval": 300,
                "last_run": 0
            },
        }
        self.running = True
        
    def run_attention_tropical(self):
        state_file = os.path.join(DATA_DIR, "attention.json")
        out_file = os.path.join(DATA_DIR, "attention_tropical_output.json")
        TropicalAttention.run_from_files(state_file, out_file)

    def run_memory_padic(self):
        in_file = os.path.join(DATA_DIR, "memory.json")
        out_file = os.path.join(DATA_DIR, "memory_padic_output.json")
        PadicMemory.run_from_files(in_file, out_file)

    def run_perception_nsa(self):
        in_file = os.path.join(DATA_DIR, "sensor.json")
        out_file = os.path.join(DATA_DIR, "perception_nsa_output.json")
        HyperrealPerception.run_from_files(in_file, out_file)

    def run_bioelectric_coupling(self):
        att_file = os.path.join(DATA_DIR, "attention.json")
        bio_file = os.path.join(DATA_DIR, "bioelectric_state.json")
        out_file = os.path.join(DATA_DIR, "bioelectric_output.json")
        BioelectricCouplingLayer.run_from_files(att_file, bio_file, out_file)

    def run_multiway_volition(self):
        in_file = os.path.join(DATA_DIR, "volition_input.json")
        state_file = os.path.join(DATA_DIR, "multiway_state.json")
        out_file = os.path.join(DATA_DIR, "multiway_output.json")
        MultiwayVolition.run_from_files(in_file, state_file, out_file)

    def run_memory_xna(self):
        in_file = os.path.join(DATA_DIR, "memory.json")
        out_file = os.path.join(DATA_DIR, "memory_xna_output.json")
        XNAMemoryStore.run_from_files(in_file, out_file)

    def run_shadow_detector(self):
        out_file = os.path.join(DATA_DIR, "shadow_output.json")
        ShadowDetector.run_from_files(None, out_file)

    def run_aihs_healing(self):
        state_file = os.path.join(DATA_DIR, "aihs_state.json")
        out_file = os.path.join(DATA_DIR, "aihs_output.json")
        AIHSOrchestrator.run_from_files(state_file, out_file)

    def run_metabolic_attention(self):
        in_file = os.path.join(DATA_DIR, "attention.json")
        out_file = os.path.join(DATA_DIR, "metabolic_attention_output.json")
        MetabolicAttention.run_from_files(in_file, out_file)

    def run_chiral_continuity(self):
        in_file = os.path.join(DATA_DIR, "chiral_state.json")
        out_file = os.path.join(DATA_DIR, "chiral_output.json")
        ChiralContinuity.run_from_files(in_file, out_file)
        
    def tick(self):
        now = time.time()
        for name, layer in self.layers.items():
            if now - layer["last_run"] >= layer["interval"]:
                try:
                    print(f"[{time.strftime('%H:%M:%S')}] Running {name}...")
                    layer["func"]()
                    layer["last_run"] = now
                    print(f"  {name} completed")
                except Exception as e:
                    print(f"  {name} ERROR: {e}")
                    
    def cross_layer_feedback(self):
        """Apply cross-layer feedback mechanisms based on alien biology principles."""
        try:
            # 1. Tropical Attention → p-adic Memory: Use allocation weights for memory prioritization
            tropical_file = os.path.join(DATA_DIR, "attention_tropical_output.json")
            padic_file = os.path.join(DATA_DIR, "memory_padic_output.json")
            if os.path.exists(tropical_file) and os.path.exists(padic_file):
                with open(tropical_file) as f:
                    tropical = json.load(f)
                with open(padic_file) as f:
                    padic = json.load(f)
                allocation = tropical.get("allocation", [])
                if allocation and padic.get("nodes"):
                    # Boost confidence of top-priority memories
                    max_alloc_idx = allocation.index(max(allocation))
                    for addr, node in padic["nodes"].items():
                        if isinstance(node, dict) and node.get("metadata"):
                            node["metadata"]["tropical_priority"] = allocation[max_alloc_idx] / sum(allocation) if sum(allocation) > 0 else 0
                # Preserve timestamp
                padic["timestamp"] = int(time.time())
                with open(padic_file, "w") as f:
                    json.dump(padic, f, separators=(',', ':'))

            # 2. Bioelectric Coupling → Metabolic Attention: Vmem state drives metabolic mode
            bio_file = os.path.join(DATA_DIR, "bioelectric_output.json")
            meta_file = os.path.join(DATA_DIR, "metabolic_attention_output.json")
            if os.path.exists(bio_file) and os.path.exists(meta_file):
                with open(bio_file) as f:
                    bio = json.load(f)
                with open(meta_file) as f:
                    meta = json.load(f)
                vmem = bio.get("mean_vmem", -70)
                # Depolarized (less negative) = stressed = glycolysis (fast ATP)
                # Hyperpolarized (more negative) = healthy = oxidative (efficient)
                if vmem > -50:
                    meta["mode"] = "glycolysis"
                elif vmem < -80:
                    meta["mode"] = "oxidative"
                else:
                    meta["mode"] = "ketogenesis"
                meta["timestamp"] = int(time.time())
                with open(meta_file, "w") as f:
                    json.dump(meta, f, separators=(',', ':'))

            # 3. Shadow Detector → AIHS Healing: Anomalies trigger targeted healing
            shadow_file = os.path.join(DATA_DIR, "shadow_output.json")
            aihs_state_file = os.path.join(DATA_DIR, "aihs_state.json")
            if os.path.exists(shadow_file) and os.path.exists(aihs_state_file):
                with open(shadow_file) as f:
                    shadow = json.load(f)
                with open(aihs_state_file) as f:
                    aihs = json.load(f)
                detections = shadow.get("detections", [])
                if detections:
                    for det in detections:
                        if det.get("severity") == "critical":
                            layer = det.get("process", "").split("_")[0] if "_" in det.get("process", "") else "unknown"
                            if layer in aihs.get("layers", {}):
                                aihs["layers"][layer]["health"] = "critical"
                                aihs["layers"][layer]["anomaly_score"] = max(
                                    aihs["layers"][layer].get("anomaly_score", 0),
                                    det.get("anomaly_score", 0.9)
                                )
                aihs["timestamp"] = int(time.time())
                with open(aihs_state_file, "w") as f:
                    json.dump(aihs, f, separators=(',', ':'))

            # 4. Hyperreal Perception → Tropical Attention: Infinitesimal timing for attention
            percep_file = os.path.join(DATA_DIR, "perception_nsa_output.json")
            if os.path.exists(percep_file) and os.path.exists(tropical_file):
                with open(percep_file) as f:
                    percep = json.load(f)
                with open(tropical_file) as f:
                    tropical = json.load(f)
                # Use standard part of hyperreal time for attention timing
                std_time = percep.get("standard_part", time.time())
                tropical["hyperreal_timestamp"] = std_time
                tropical["timestamp"] = int(time.time())
                with open(tropical_file, "w") as f:
                    json.dump(tropical, f, separators=(',', ':'))

        except Exception as e:
            print(f"  Cross-layer feedback ERROR: {e}")

    def run(self):
        print("=== Xenobiological Daemon Started (single-process) ===")
        print(f"Layers: {list(self.layers.keys())}")
        print("Press Ctrl+C to stop")

        while self.running:
            self.tick()
            self.cross_layer_feedback()
            time.sleep(10)  # Check every 10 seconds

        print("Daemon stopped")

if __name__ == "__main__":
    daemon = XenobiologicalDaemon()
    try:
        daemon.run()
    except KeyboardInterrupt:
        print("\nShutting down...")
