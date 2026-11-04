#!/usr/bin/env python3
"""
Metabolic Mode Switching for Attention.

Based on Alien Chemistry research: Alternative metabolic pathways
(Calvin cycle, reductive TCA, Wood-Ljungdahl, CETCH cycle) applied
as pluggable attention processing modes.

Each mode represents a different "metabolic strategy" for attention:
- CALVIN: Carbon fixation style - steady, cyclic, builds structure
- REDUCTIVE_TCA: Reverse Krebs - high energy investment, deep processing
- WOOD_LJUNGDAHL: Acetogenesis - efficient, minimal waste, recycling
- CETCH: Synthetic CETCH cycle - burst processing, high throughput

Switching is triggered by context: task type, resource availability, urgency.
"""

import json
import os
import sys
import time
import threading
import struct
from typing import Dict, List, Optional, Tuple, Any, Callable
from dataclasses import dataclass, field
from enum import Enum
from collections import deque, defaultdict
from abc import ABC, abstractmethod
import random

# Import Huffman codec
sys.path.insert(0, os.path.dirname(__file__))
try:
    from huffman_codec import HuffmanCodec
    HUFFMAN_AVAILABLE = True
except ImportError:
    HUFFMAN_AVAILABLE = False


class MetabolicMode(Enum):
    """Attention metabolic modes (alien biochemistry analogues)."""
    CALVIN = "calvin"                    # Steady cyclic processing - carbon fixation
    REDUCTIVE_TCA = "reductive_tca"      # Deep processing - reverse Krebs cycle
    WOOD_LJUNGDAHL = "wood_ljungdahl"    # Efficient recycling - acetogenesis
    CETCH = "cetch"                      # Burst synthesis - CETCH cycle
    HYBRID = "hybrid"                    # Mixed mode


@dataclass
class MetabolicConfig:
    """Configuration for a metabolic mode."""
    name: MetabolicMode
    cpu_budget: float          # % CPU allocation
    mem_budget: float          # MB memory allocation
    cycle_duration: float      # seconds per attention cycle
    depth: int                 # processing depth (layers)
    throughput: float          # items per cycle
    energy_cost: float         # relative energy cost
    waste_tolerance: float     # error/tolerance threshold
    recovery_time: float       # seconds to recover
    substrates: List[str]      # input types this mode handles best
    products: List[str]        # output types this mode produces
    enzymes: List[str]         # required "enzymes" (sub-processes)


# Metabolic pathway configurations (from alien chemistry research)
METABOLIC_CONFIGS = {
    MetabolicMode.CALVIN: MetabolicConfig(
        name=MetabolicMode.CALVIN,
        cpu_budget=10.0,
        mem_budget=50.0,
        cycle_duration=5.0,
        depth=3,
        throughput=20.0,
        energy_cost=1.0,
        waste_tolerance=0.1,
        recovery_time=2.0,
        substrates=["raw_sensory", "short_term", "pattern"],
        products=["structured_attention", "consolidated_memory"],
        enzymes=["rubisco_analogue", "pga_reductase", "regeneration"]
    ),
    MetabolicMode.REDUCTIVE_TCA: MetabolicConfig(
        name=MetabolicMode.REDUCTIVE_TCA,
        cpu_budget=30.0,
        mem_budget=200.0,
        cycle_duration=30.0,
        depth=8,
        throughput=5.0,
        energy_cost=3.0,
        waste_tolerance=0.01,
        recovery_time=10.0,
        substrates=["complex_problem", "deep_reasoning", "planning"],
        products=["insight", "strategy", "decision"],
        enzymes=["atp_citrate_lyase", "ferredoxin", "reductive_carboxylation"]
    ),
    MetabolicMode.WOOD_LJUNGDAHL: MetabolicConfig(
        name=MetabolicMode.WOOD_LJUNGDAHL,
        cpu_budget=5.0,
        mem_budget=30.0,
        cycle_duration=2.0,
        depth=2,
        throughput=50.0,
        energy_cost=0.5,
        waste_tolerance=0.2,
        recovery_time=0.5,
        substrates=["routine_task", "maintenance", "recall"],
        products=["quick_response", "cached_result"],
        enzymes=["co_dehydrogenase", "methyltransferase", "carbonyl_synthase"]
    ),
    MetabolicMode.CETCH: MetabolicConfig(
        name=MetabolicMode.CETCH,
        cpu_budget=50.0,
        mem_budget=100.0,
        cycle_duration=1.0,
        depth=1,
        throughput=100.0,
        energy_cost=5.0,
        waste_tolerance=0.3,
        recovery_time=5.0,
        substrates=["urgent", "high_volume", "stream"],
        products=["rapid_classification", "triage"],
        enzymes=["crotonyl_coa_reductase", "ethylmalonyl_coa_mutase", "glyoxylate_cycle"]
    ),
    MetabolicMode.HYBRID: MetabolicConfig(
        name=MetabolicMode.HYBRID,
        cpu_budget=15.0,
        mem_budget=80.0,
        cycle_duration=10.0,
        depth=4,
        throughput=15.0,
        energy_cost=1.5,
        waste_tolerance=0.15,
        recovery_time=3.0,
        substrates=["mixed", "adaptive"],
        products=["balanced"],
        enzymes=["mixed_pathway"]
    ),
}


@dataclass
class MetabolicState:
    """Current metabolic state of attention."""
    mode: MetabolicMode
    cycle_count: int = 0
    total_processed: int = 0
    total_energy: float = 0.0
    waste_accumulated: float = 0.0
    last_switch: float = field(default_factory=time.time)
    efficiency: float = 1.0
    substrate_buffer: List[str] = field(default_factory=list)
    product_buffer: List[str] = field(default_factory=list)
    cofactors: Dict[str, float] = field(default_factory=dict)  # ATP, NADPH, etc.


class MetabolicProcessor(ABC):
    """Base class for metabolic attention processors."""

    def __init__(self, config: MetabolicConfig):
        self.config = config
        self.state = MetabolicState(mode=config.name)

    @abstractmethod
    def process(self, substrates: List[str], context: Dict) -> List[str]:
        """Process substrates into products."""
        pass

    def can_process(self, substrate: str) -> bool:
        """Check if this mode can handle a substrate type."""
        return substrate in self.config.substrates or "mixed" in self.config.substrates

    def get_efficiency(self) -> float:
        """Calculate current metabolic efficiency."""
        if self.state.total_processed == 0:
            return 1.0
        return self.state.total_processed / max(self.state.total_energy, 0.001)

    def consume_energy(self, amount: float):
        """Consume metabolic energy (ATP analogue)."""
        self.state.total_energy += amount
        self.state.cofactors["ATP"] = self.state.cofactors.get("ATP", 100.0) - amount
        self.state.cofactors["ATP"] = max(self.state.cofactors["ATP"], 0)

    def produce_waste(self, amount: float):
        """Accumulate metabolic waste."""
        self.state.waste_accumulated += amount
        if self.state.waste_accumulated > self.config.waste_tolerance * 10:
            self.state.efficiency *= 0.95  # Efficiency drops with waste


class CalvinProcessor(MetabolicProcessor):
    """Calvin cycle: Steady cyclic carbon fixation - builds structured attention."""

    def process(self, substrates: List[str], context: Dict) -> List[str]:
        products = []
        for sub in substrates:
            if sub in ["raw_sensory", "pattern"]:
                # Fixation phase: incorporate CO2 (new info) into PGA
                self.consume_energy(1.0)
                # Reduction phase: PGA -> G3P (structured attention)
                self.consume_energy(2.0)
                products.append("structured_attention")
                self.state.total_processed += 1
            elif sub == "short_term":
                # Regeneration phase: recycle RuBP
                self.consume_energy(0.5)
                products.append("consolidated_memory")
                self.state.total_processed += 1

        self.state.cycle_count += 1
        return products


class ReductiveTCAProcessor(MetabolicProcessor):
    """Reductive TCA: Reverse Krebs - deep processing, high energy investment."""

    def process(self, substrates: List[str], context: Dict) -> List[str]:
        products = []
        for sub in substrates:
            if sub in ["complex_problem", "deep_reasoning"]:
                # Reductive carboxylation steps (high ATP)
                self.consume_energy(5.0)
                # Multiple reduction steps
                for _ in range(self.config.depth):
                    self.consume_energy(1.5)
                products.append("insight")
                self.state.total_processed += 1
            elif sub == "planning":
                self.consume_energy(3.0)
                products.append("strategy")
                self.state.total_processed += 1

        self.state.cycle_count += 1
        return products


class WoodLjungdahlProcessor(MetabolicProcessor):
    """Wood-Ljungdahl: Acetogenesis - efficient, minimal waste, recycling."""

    def process(self, substrates: List[str], context: Dict) -> List[str]:
        products = []
        for sub in substrates:
            if sub in ["routine_task", "maintenance"]:
                # Carbonyl branch (low energy)
                self.consume_energy(0.3)
                # Methyl branch (recycled)
                self.consume_energy(0.2)
                products.append("quick_response")
                self.state.total_processed += 1
            elif sub == "recall":
                # Direct from cache - almost free
                self.consume_energy(0.1)
                products.append("cached_result")
                self.state.total_processed += 1

        self.state.cycle_count += 1
        return products


class CETCHProcessor(MetabolicProcessor):
    """CETCH cycle: Synthetic - burst processing, high throughput."""

    def process(self, substrates: List[str], context: Dict) -> List[str]:
        products = []
        for sub in substrates:
            if sub in ["urgent", "high_volume"]:
                # Crotonyl-CoA carboxylase/reductase - fast CO2 fixation
                self.consume_energy(2.0)
                # Ethylmalonyl-CoA mutase - rearrangement
                self.consume_energy(1.0)
                # Glyoxylate cycle bypass - rapid turnover
                self.consume_energy(1.0)
                products.append("rapid_classification")
                self.state.total_processed += 1
            elif sub == "stream":
                # Continuous flow processing
                self.consume_energy(0.5)
                products.append("triage")
                self.state.total_processed += 1

        self.state.cycle_count += 1
        return products


class HybridProcessor(MetabolicProcessor):
    """Hybrid: Adaptive mixed pathway."""

    def __init__(self, config: MetabolicConfig):
        super().__init__(config)
        self.sub_processors = {
            MetabolicMode.CALVIN: CalvinProcessor(METABOLIC_CONFIGS[MetabolicMode.CALVIN]),
            MetabolicMode.REDUCTIVE_TCA: ReductiveTCAProcessor(METABOLIC_CONFIGS[MetabolicMode.REDUCTIVE_TCA]),
            MetabolicMode.WOOD_LJUNGDAHL: WoodLjungdahlProcessor(METABOLIC_CONFIGS[MetabolicMode.WOOD_LJUNGDAHL]),
            MetabolicMode.CETCH: CETCHProcessor(METABOLIC_CONFIGS[MetabolicMode.CETCH]),
        }

    def process(self, substrates: List[str], context: Dict) -> List[str]:
        products = []
        # Route each substrate to best sub-processor
        for sub in substrates:
            best_mode = self._select_sub_mode(sub)
            if best_mode:
                sub_products = self.sub_processors[best_mode].process([sub], context)
                products.extend(sub_products)
                self.state.total_processed += len(sub_products)
                self.state.total_energy += self.sub_processors[best_mode].state.total_energy

        self.state.cycle_count += 1
        return products

    def _select_sub_mode(self, substrate: str) -> Optional[MetabolicMode]:
        """Select best sub-mode for substrate."""
        for mode, proc in self.sub_processors.items():
            if proc.can_process(substrate):
                return mode
        return MetabolicMode.CALVIN


class MetabolicAttention:
    """
    Metabolic Attention System - switches between metabolic modes
    based on task demands, resource state, and efficiency.
    """

    def __init__(self, state_path: str = None):
        self.state_path = state_path or "/opt/athena/state/metabolic_attention.json"
        self.processors: Dict[MetabolicMode, MetabolicProcessor] = {
            MetabolicMode.CALVIN: CalvinProcessor(METABOLIC_CONFIGS[MetabolicMode.CALVIN]),
            MetabolicMode.REDUCTIVE_TCA: ReductiveTCAProcessor(METABOLIC_CONFIGS[MetabolicMode.REDUCTIVE_TCA]),
            MetabolicMode.WOOD_LJUNGDAHL: WoodLjungdahlProcessor(METABOLIC_CONFIGS[MetabolicMode.WOOD_LJUNGDAHL]),
            MetabolicMode.CETCH: CETCHProcessor(METABOLIC_CONFIGS[MetabolicMode.CETCH]),
            MetabolicMode.HYBRID: HybridProcessor(METABOLIC_CONFIGS[MetabolicMode.HYBRID]),
        }
        self.current_mode = MetabolicMode.CALVIN
        self.mode_history: List[Tuple[float, MetabolicMode, str]] = []  # (timestamp, mode, reason)
        self.performance_history: Dict[MetabolicMode, deque] = defaultdict(lambda: deque(maxlen=100))
        self._lock = threading.Lock()
        self.load_state()

    def get_processor(self, mode: MetabolicMode = None) -> MetabolicProcessor:
        """Get processor for mode (current if None)."""
        mode = mode or self.current_mode
        return self.processors[mode]

    def process_attention(self, substrates: List[str], context: Dict = None) -> Dict:
        """Process attention through current metabolic mode."""
        context = context or {}

        # Determine best mode for this task BEFORE processing
        task_type = context.get("task_type", "routine")
        urgency = context.get("urgency", "normal")
        cpu_pressure = context.get("cpu_pressure", 0.0)
        target_mode = self._select_mode_for_context(task_type, urgency, cpu_pressure)

        # Switch if needed (before processing)
        if target_mode != self.current_mode:
            self._switch_mode(target_mode, f"pre-process: task={task_type}, urgency={urgency}, cpu={cpu_pressure:.1f}")

        processor = self.get_processor()

        # Add to substrate buffer
        processor.state.substrate_buffer.extend(substrates)

        # Process
        start = time.time()
        products = processor.process(substrates, context)
        elapsed = time.time() - start

        # Update state
        processor.state.product_buffer.extend(products)
        processor.state.cycle_count += 1

        # Record performance
        efficiency = len(products) / max(elapsed, 0.001)
        self.performance_history[self.current_mode].append({
            "timestamp": time.time(),
            "efficiency": efficiency,
            "energy": processor.state.total_energy,
            "waste": processor.state.waste_accumulated,
            "substrates": len(substrates),
            "products": len(products)
        })

        return {
            "mode": self.current_mode.value,
            "products": products,
            "efficiency": efficiency,
            "energy_used": processor.state.total_energy,
            "waste": processor.state.waste_accumulated,
            "cycle": processor.state.cycle_count,
            "elapsed_ms": elapsed * 1000
        }

    def _maybe_switch_mode(self, context: Dict):
        """Evaluate and potentially switch metabolic mode."""
        # Switch triggers:
        # 1. Task type change
        # 2. Resource pressure
        # 3. Efficiency drop
        # 4. Waste accumulation
        # 5. Explicit request

        task_type = context.get("task_type", "routine")
        urgency = context.get("urgency", "normal")
        cpu_pressure = context.get("cpu_pressure", 0.0)

        # Determine target mode
        target_mode = self._select_mode_for_context(task_type, urgency, cpu_pressure)

        if target_mode != self.current_mode:
            self._switch_mode(target_mode, f"context: task={task_type}, urgency={urgency}, cpu={cpu_pressure:.1f}")

    def _select_mode_for_context(self, task_type: str, urgency: str, cpu_pressure: float) -> MetabolicMode:
        """Select best metabolic mode for context."""
        # High urgency + high CPU = CETCH (burst)
        if urgency == "high" and cpu_pressure < 0.5:
            return MetabolicMode.CETCH

        # Deep reasoning = reductive TCA
        if task_type in ["reasoning", "planning", "analysis", "creative"]:
            return MetabolicMode.REDUCTIVE_TCA

        # Routine/maintenance = Wood-Ljungdahl (efficient)
        if task_type in ["routine", "maintenance", "recall", "monitoring"]:
            return MetabolicMode.WOOD_LJUNGDAHL

        # High CPU pressure = efficient mode
        if cpu_pressure > 0.7:
            return MetabolicMode.WOOD_LJUNGDAHL

        # Default = Calvin (steady building)
        return MetabolicMode.CALVIN

    def _switch_mode(self, new_mode: MetabolicMode, reason: str):
        """Switch to new metabolic mode."""
        old_mode = self.current_mode

        # Recovery period for old mode
        old_proc = self.processors[old_mode]
        time.sleep(old_proc.config.recovery_time / 1000)  # Scaled down

        # Initialize new mode with some cofactor carryover
        new_proc = self.processors[new_mode]
        new_proc.state.cofactors["ATP"] = old_proc.state.cofactors.get("ATP", 50.0) * 0.8

        with self._lock:
            self.current_mode = new_mode
            self.mode_history.append((time.time(), new_mode, reason))
            new_proc.state.last_switch = time.time()

        print(f"[Metabolic] Switch: {old_mode.value} -> {new_mode.value} ({reason})")

    def force_mode(self, mode: MetabolicMode, reason: str = "manual"):
        """Force switch to specific mode."""
        self._switch_mode(mode, reason)

    def get_status(self) -> Dict:
        """Get current metabolic status."""
        proc = self.get_processor()
        return {
            "current_mode": self.current_mode.value,
            "config": {
                "cpu_budget": proc.config.cpu_budget,
                "mem_budget": proc.config.mem_budget,
                "cycle_duration": proc.config.cycle_duration,
                "depth": proc.config.depth,
                "throughput": proc.config.throughput,
                "energy_cost": proc.config.energy_cost
            },
            "state": {
                "cycle_count": proc.state.cycle_count,
                "total_processed": proc.state.total_processed,
                "total_energy": proc.state.total_energy,
                "waste_accumulated": proc.state.waste_accumulated,
                "efficiency": proc.get_efficiency(),
                "cofactors": proc.state.cofactors,
                "last_switch": proc.state.last_switch
            },
            "mode_history": [
                {"timestamp": t, "mode": m.value, "reason": r}
                for t, m, r in self.mode_history[-20:]
            ],
            "performance": {
                mode.value: list(hist)[-10:] if hist else []
                for mode, hist in self.performance_history.items()
            }
        }

    def load_state(self):
        """Load state from disk."""
        if os.path.exists(self.state_path):
            try:
                with open(self.state_path) as f:
                    data = json.load(f)

                # Restore mode
                if "current_mode" in data:
                    self.current_mode = MetabolicMode(data["current_mode"])

                # Restore mode history
                self.mode_history = [
                    (h["timestamp"], MetabolicMode(h["mode"]), h["reason"])
                    for h in data.get("mode_history", [])
                ]

                # Restore processor states
                for mode_name, proc_data in data.get("processors", {}).items():
                    mode = MetabolicMode(mode_name)
                    if mode in self.processors:
                        proc = self.processors[mode]
                        state = proc_data.get("state", {})
                        proc.state.cycle_count = state.get("cycle_count", 0)
                        proc.state.total_processed = state.get("total_processed", 0)
                        proc.state.total_energy = state.get("total_energy", 0.0)
                        proc.state.waste_accumulated = state.get("waste_accumulated", 0.0)
                        proc.state.cofactors = state.get("cofactors", {})
                        proc.state.last_switch = state.get("last_switch", time.time())
            except Exception as e:
                print(f"Failed to load metabolic state: {e}", file=sys.stderr)

    def save_state(self):
        """Save state to disk (uncompressed JSON)."""
        try:
            data = {
                "current_mode": self.current_mode.value,
                "mode_history": [
                    {"timestamp": t, "mode": m.value, "reason": r}
                    for t, m, r in self.mode_history[-50:]
                ],
                "processors": {
                    mode.value: {
                        "state": {
                            "cycle_count": proc.state.cycle_count,
                            "total_processed": proc.state.total_processed,
                            "total_energy": proc.state.total_energy,
                            "waste_accumulated": proc.state.waste_accumulated,
                            "cofactors": proc.state.cofactors,
                            "last_switch": proc.state.last_switch
                        }
                    }
                    for mode, proc in self.processors.items()
                }
            }
            with open(self.state_path, "w") as f:
                json.dump(data, f, separators=(',', ':'))
        except Exception as e:
            print(f"Failed to save metabolic state: {e}", file=sys.stderr)

    def save_state_compressed(self, codec: 'HuffmanCodec' = None):
        """Save state as Huffman-compressed bytes + codec sidecar."""
        if not HUFFMAN_AVAILABLE:
            self.save_state()
            return

        try:
            data = {
                "current_mode": self.current_mode.value,
                "mode_history": [
                    {"timestamp": t, "mode": m.value, "reason": r}
                    for t, m, r in self.mode_history[-50:]
                ],
                "processors": {
                    mode.value: {
                        "state": {
                            "cycle_count": proc.state.cycle_count,
                            "total_processed": proc.state.total_processed,
                            "total_energy": proc.state.total_energy,
                            "waste_accumulated": proc.state.waste_accumulated,
                            "cofactors": proc.state.cofactors,
                            "last_switch": proc.state.last_switch
                        }
                    }
                    for mode, proc in self.processors.items()
                }
            }
            json_bytes = json.dumps(data, separators=(',', ':')).encode('utf-8')

            if codec is None:
                codec = HuffmanCodec.build_from_json_samples([data])

            compressed = codec.encode(json_bytes)

            # Write compressed state
            huf_path = self.state_path + ".huf"
            with open(huf_path, "wb") as f:
                f.write(struct.pack('>I', len(compressed)))
                f.write(compressed)

            # Write codec sidecar
            codec_path = self.state_path + ".huf.codec"
            codec.save(codec_path)

            # Remove old uncompressed
            if os.path.exists(self.state_path):
                os.remove(self.state_path)

        except Exception as e:
            print(f"Failed to save compressed metabolic state: {e}", file=sys.stderr)
            self.save_state()

    def load_state_compressed(self, codec: 'HuffmanCodec' = None):
        """Load state from Huffman-compressed files (fallback to uncompressed)."""
        if not HUFFMAN_AVAILABLE:
            self.load_state()
            return

        huf_path = self.state_path + ".huf"
        codec_path = self.state_path + ".huf.codec"

        if os.path.exists(huf_path) and os.path.exists(codec_path):
            try:
                if codec is None:
                    codec = HuffmanCodec.load(codec_path)

                with open(huf_path, "rb") as f:
                    compressed_len = struct.unpack('>I', f.read(4))[0]
                    compressed = f.read(compressed_len)

                json_bytes = codec.decode(compressed)
                data = json.loads(json_bytes.decode('utf-8'))

                # Restore mode
                if "current_mode" in data:
                    self.current_mode = MetabolicMode(data["current_mode"])

                # Restore mode history
                self.mode_history = [
                    (h["timestamp"], MetabolicMode(h["mode"]), h["reason"])
                    for h in data.get("mode_history", [])
                ]

                # Restore processor states
                for mode_name, proc_data in data.get("processors", {}).items():
                    mode = MetabolicMode(mode_name)
                    if mode in self.processors:
                        proc = self.processors[mode]
                        state = proc_data.get("state", {})
                        proc.state.cycle_count = state.get("cycle_count", 0)
                        proc.state.total_processed = state.get("total_processed", 0)
                        proc.state.total_energy = state.get("total_energy", 0.0)
                        proc.state.waste_accumulated = state.get("waste_accumulated", 0.0)
                        proc.state.cofactors = state.get("cofactors", {})
                        proc.state.last_switch = state.get("last_switch", time.time())
                return
            except Exception as e:
                print(f"Failed to load compressed metabolic state: {e}", file=sys.stderr)

        # Fallback to uncompressed
        self.load_state()

    @staticmethod
    def run_from_files(input_file: str, output_file: str):
        """Entry point called by xenobiological daemon."""
        ma = MetabolicAttention()
        # Read substrates and context from input file
        with open(input_file) as f:
            data = json.load(f)

        substrates = data.get('substrates', ['raw_sensory'])
        context = data.get('context', {'task_type': 'routine', 'urgency': 'normal'})

        result = ma.process_attention(substrates, context)

        output = {
            'mode': result['mode'],
            'products': result['products'],
            'efficiency': result['efficiency'],
            'energy_used': result['energy_used'],
            'waste': result['waste'],
            'timestamp': int(time.time())
        }

        with open(output_file, 'w') as f:
            json.dump(output, f, separators=(',', ':'))

        return output


def metabolic_attention_query(state_path: str, query: Dict) -> Dict:
    """Query function for shell integration."""
    ma = MetabolicAttention(state_path)

    query_type = query.get("type", "status")

    if query_type == "status":
        return ma.get_status()

    elif query_type == "process":
        substrates = query.get("substrates", [])
        context = query.get("context", {})
        result = ma.process_attention(substrates, context)
        ma.save_state_compressed()
        return result

    elif query_type == "switch":
        mode_str = query.get("mode")
        if mode_str:
            try:
                mode = MetabolicMode(mode_str)
                ma.force_mode(mode, query.get("reason", "manual"))
                ma.save_state_compressed()
                return {"switched": True, "mode": mode.value}
            except ValueError:
                return {"error": f"Invalid mode: {mode_str}"}
        return {"error": "No mode specified"}

    elif query_type == "demo":
        # Run demo sequence
        results = []
        test_cases = [
            (["raw_sensory", "pattern"], {"task_type": "perception", "urgency": "normal"}),
            (["complex_problem"], {"task_type": "reasoning", "urgency": "high"}),
            (["routine_task", "maintenance"], {"task_type": "maintenance", "urgency": "low"}),
            (["urgent", "stream"], {"task_type": "stream", "urgency": "high", "cpu_pressure": 0.3}),
            (["short_term", "recall"], {"task_type": "recall", "urgency": "normal"}),
        ]
        for substrates, context in test_cases:
            result = ma.process_attention(substrates, context)
            results.append({"substrates": substrates, "context": context, "result": result})
        ma.save_state_compressed()
        return {"demo_results": results}

    return {"error": f"Unknown query type: {query_type}"}


@staticmethod
def run_from_files(input_file: str, output_file: str):
    """Entry point called by xenobiological daemon."""
    ma = MetabolicAttention()
    # Read substrates and context from input file
    with open(input_file) as f:
        data = json.load(f)

    substrates = data.get('substrates', ['raw_sensory'])
    context = data.get('context', {'task_type': 'routine', 'urgency': 'normal'})

    result = ma.process_attention(substrates, context)

    output = {
        'mode': result['mode'],
        'products': result['products'],
        'efficiency': result['efficiency'],
        'energy_used': result['energy_used'],
        'waste': result['waste'],
        'timestamp': int(time.time())
    }

    with open(output_file, 'w') as f:
        json.dump(output, f, separators=(',', ':'))

    return output


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Metabolic Attention System")
    parser.add_argument("command", choices=["status", "process", "switch", "demo"])
    parser.add_argument("--mode", type=str, help="Mode to switch to")
    parser.add_argument("--substrates", nargs="+", help="Substrates to process")
    parser.add_argument("--task-type", type=str, default="routine")
    parser.add_argument("--urgency", type=str, default="normal")
    parser.add_argument("--cpu-pressure", type=float, default=0.0)
    parser.add_argument("--reason", type=str, default="manual")
    parser.add_argument("--output", type=str)
    args = parser.parse_args()

    ma = MetabolicAttention()

    if args.command == "status":
        result = ma.get_status()
        print(json.dumps(result, indent=2))
        if args.output:
            with open(args.output, "w") as f:
                json.dump(result, f)

    elif args.command == "process":
        substrates = args.substrates or ["raw_sensory"]
        context = {
            "task_type": args.task_type,
            "urgency": args.urgency,
            "cpu_pressure": args.cpu_pressure
        }
        result = ma.process_attention(substrates, context)
        print(json.dumps(result, indent=2))
        ma.save_state_compressed()

    elif args.command == "switch":
        if not args.mode:
            print("Specify --mode")
            sys.exit(1)
        try:
            mode = MetabolicMode(args.mode)
            ma.force_mode(mode, args.reason)
            ma.save_state_compressed()
            print(f"Switched to {mode.value}")
        except ValueError:
            print(f"Invalid mode: {args.mode}")
            print(f"Valid modes: {[m.value for m in MetabolicMode]}")
            sys.exit(1)

    elif args.command == "demo":
        print("=== Metabolic Attention Demo ===")
        print("\nAvailable modes:")
        for mode, config in METABOLIC_CONFIGS.items():
            print(f"  {mode.value}: CPU={config.cpu_budget}%, Mem={config.mem_budget}MB, "
                  f"Cycle={config.cycle_duration}s, Depth={config.depth}, "
                  f"Energy={config.energy_cost}x, Throughput={config.throughput}/cycle")

        print("\nRunning demo sequence...")
        test_cases = [
            (["raw_sensory", "pattern"], {"task_type": "perception", "urgency": "normal"}, "Perception"),
            (["complex_problem"], {"task_type": "reasoning", "urgency": "high"}, "Deep Reasoning"),
            (["routine_task", "maintenance"], {"task_type": "maintenance", "urgency": "low"}, "Maintenance"),
            (["urgent", "stream"], {"task_type": "stream", "urgency": "high", "cpu_pressure": 0.3}, "High-Volume Stream"),
            (["short_term", "recall"], {"task_type": "recall", "urgency": "normal"}, "Memory Recall"),
        ]

        for substrates, context, desc in test_cases:
            print(f"\n--- {desc} ---")
            print(f"  Substrates: {substrates}")
            print(f"  Context: {context}")
            result = ma.process_attention(substrates, context)
            print(f"  Mode: {result['mode']}")
            print(f"  Products: {result['products']}")
            print(f"  Efficiency: {result['efficiency']:.1f} products/sec")
            print(f"  Energy: {result['energy_used']:.1f}, Waste: {result['waste']:.2f}")

        print(f"\nFinal status: {ma.current_mode.value}")
        print(f"Mode switches: {len(ma.mode_history)}")
        for t, m, r in ma.mode_history:
            print(f"  {time.strftime('%H:%M:%S', time.localtime(t))}: {m.value} ({r})")

        ma.save_state_compressed()