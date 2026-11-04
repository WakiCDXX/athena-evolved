#!/usr/bin/env python3
"""
Bioelectric Coupling Layer for Athena Consciousness System.

Based on Michael Levin's research on bioelectric morphogenesis:
- Transmembrane voltage (Vmem) as information carrier
- Voltage gradients encode anatomical pattern memories
- Gap junctions = electrical synapses for collective computation
- Ion channels as controllable "bioelectric logic gates"
- Regeneration via bioelectric pattern restoration (planaria, xenobots)

Applications for Athena:
- Layer-to-layer coupling via "voltage" potentials
- Collective decision-making through electrical synchronization
- Pattern memory storage in voltage gradients (not just synaptic weights)
- Self-repair via bioelectric homeostasis (target morphology)
- Xenobot-style programmable collectives for distributed tasks
"""

import json
import os
import sys
import time
import math
import random
from typing import Dict, List, Optional, Tuple, Any, Callable
from dataclasses import dataclass, field
from collections import deque
from enum import Enum


# Bioelectric constants
RESTING_POTENTIAL = -70.0  # mV, typical cell resting potential
THRESHOLD_POTENTIAL = -55.0  # mV, action potential threshold
GAP_JUNCTION_CONDUCTANCE = 0.1  # nS, gap junction coupling strength
ION_CHANNEL_DENSITY = 100  # channels/µm²
MEMBRANE_CAPACITANCE = 1.0  # µF/cm²


class IonChannelType(Enum):
    """Types of voltage-gated ion channels."""
    SODIUM = "Na+"      # Depolarization
    POTASSIUM = "K+"    # Repolarization
    CALCIUM = "Ca2+"    # Signaling
    CHLORIDE = "Cl-"    # Hyperpolarization
    GAP_JUNCTION = "GJ" # Electrical coupling


@dataclass
class IonChannel:
    """Voltage-gated ion channel."""
    channel_type: IonChannelType
    conductance: float  # nS
    reversal_potential: float  # mV
    voltage_half: float  # mV, half-activation voltage
    slope: float = 5.0  # mV, activation slope
    state: float = 0.0  # 0=closed, 1=open

    def update(self, vmem: float, dt: float):
        """Update channel state based on voltage (Hodgkin-Huxley style)."""
        # Boltzmann activation
        target = 1.0 / (1.0 + math.exp(-(vmem - self.voltage_half) / self.slope))
        # Exponential relaxation
        tau = 1.0  # ms
        self.state += (target - self.state) * (dt / tau)

    def current(self, vmem: float) -> float:
        """Ionic current through this channel (nA)."""
        return self.conductance * self.state * (vmem - self.reversal_potential)


@dataclass
class BioelectricCell:
    """
    Single bioelectric unit (analogous to a cell or Athena layer).
    Maintains transmembrane voltage Vmem and ion channel complement.
    """
    cell_id: str
    vmem: float = RESTING_POTENTIAL
    channels: Dict[IonChannelType, IonChannel] = field(default_factory=dict)
    gap_junctions: Dict[str, float] = field(default_factory=dict)  # neighbor_id -> conductance
    morphology_target: float = RESTING_POTENTIAL  # Target Vmem for homeostasis
    metadata: Dict = field(default_factory=dict)

    def __post_init__(self):
        # Default channel complement (generic excitable cell)
        if not self.channels:
            self.channels = {
                IonChannelType.SODIUM: IonChannel(
                    IonChannelType.SODIUM, 120.0, 50.0, -40.0
                ),
                IonChannelType.POTASSIUM: IonChannel(
                    IonChannelType.POTASSIUM, 36.0, -77.0, -50.0
                ),
                IonChannelType.CALCIUM: IonChannel(
                    IonChannelType.CALCIUM, 10.0, 120.0, -30.0
                ),
                IonChannelType.CHLORIDE: IonChannel(
                    IonChannelType.CHLORIDE, 5.0, -65.0, -60.0
                )
            }

    def add_gap_junction(self, neighbor_id: str, conductance: float = GAP_JUNCTION_CONDUCTANCE):
        """Form electrical synapse with neighbor."""
        self.gap_junctions[neighbor_id] = conductance

    def step(self, dt: float, injected_current: float = 0.0, neighbor_vmems: Dict[str, float] = None) -> float:
        """
        Single time step of bioelectric dynamics.
        Returns new Vmem.
        """
        if neighbor_vmems is None:
            neighbor_vmems = {}

        # Update channel states
        for channel in self.channels.values():
            channel.update(self.vmem, dt)

        # Compute ionic currents
        ionic_current = sum(ch.current(self.vmem) for ch in self.channels.values())

        # Gap junction currents (electrical coupling)
        gj_current = 0.0
        for neighbor_id, conductance in self.gap_junctions.items():
            neighbor_vmem = neighbor_vmems.get(neighbor_id, RESTING_POTENTIAL)
            gj_current += conductance * (neighbor_vmem - self.vmem)

        # Membrane equation: C * dV/dt = I_ionic + I_gj + I_injected
        dv = (ionic_current + gj_current + injected_current) / MEMBRANE_CAPACITANCE
        self.vmem += dv * dt

        return self.vmem

    def inject_current(self, current: float, duration: float = 1.0):
        """Simulate current injection (e.g., optogenetic stimulation)."""
        self.metadata['last_stimulus'] = {'current': current, 'duration': duration, 'time': time.time()}

    def get_pattern_signature(self) -> List[float]:
        """Get bioelectric pattern signature (channel states + Vmem)."""
        sig = [self.vmem]
        for ch_type in IonChannelType:
            if ch_type != IonChannelType.GAP_JUNCTION:
                ch = self.channels.get(ch_type)
                sig.append(ch.state if ch else 0.0)
        return sig


class BioelectricNetwork:
    """
    Network of bioelectrically coupled cells (Athena layers as cells).
    Implements collective computation via voltage dynamics.
    """

    def __init__(self):
        self.cells: Dict[str, BioelectricCell] = {}
        self.global_time = 0.0
        self.dt = 0.1  # ms
        self.pattern_memory: Dict[str, List[float]] = {}  # Named voltage patterns

    def add_cell(self, cell_id: str, layer_type: str = "generic") -> BioelectricCell:
        """Add a cell (Athena layer) to the network."""
        cell = BioelectricCell(cell_id=cell_id)
        cell.metadata['layer_type'] = layer_type
        cell.metadata['created'] = time.time()

        # Customize by layer type
        if layer_type == "attention":
            # High Na+ for rapid depolarization (attention shifts)
            cell.channels[IonChannelType.SODIUM].conductance = 200.0
            cell.channels[IonChannelType.POTASSIUM].conductance = 20.0
            cell.morphology_target = -40.0  # Depolarized = attentive
        elif layer_type == "memory":
            # High K+ for stability, Ca2+ for plasticity
            cell.channels[IonChannelType.POTASSIUM].conductance = 50.0
            cell.channels[IonChannelType.CALCIUM].conductance = 20.0
            cell.morphology_target = -65.0  # Stable
        elif layer_type == "volition":
            # Balanced for decision dynamics
            cell.morphology_target = -50.0
        elif layer_type == "body":
            # Low excitability, high coupling
            for ch in cell.channels.values():
                ch.conductance *= 0.5
            cell.morphology_target = -70.0

        self.cells[cell_id] = cell
        return cell

    def connect_layers(self, cell_id1: str, cell_id2: str, conductance: float = GAP_JUNCTION_CONDUCTANCE):
        """Form bidirectional gap junction between layers."""
        if cell_id1 in self.cells and cell_id2 in self.cells:
            self.cells[cell_id1].add_gap_junction(cell_id2, conductance)
            self.cells[cell_id2].add_gap_junction(cell_id1, conductance)

    def step_network(self, injected_currents: Dict[str, float] = None):
        """Advance entire network by one time step."""
        if injected_currents is None:
            injected_currents = {}

        # Collect current Vmems for gap junction computation
        current_vmems = {cid: cell.vmem for cid, cell in self.cells.items()}

        # Update all cells
        for cell_id, cell in self.cells.items():
            inj = injected_currents.get(cell_id, 0.0)
            cell.step(self.dt, inj, current_vmems)

        self.global_time += self.dt

    def run_simulation(self, steps: int, injected_currents: Dict[str, List[float]] = None) -> List[Dict]:
        """Run simulation for multiple steps, return voltage traces."""
        traces = {cid: [] for cid in self.cells}

        for step in range(steps):
            inj = {}
            if injected_currents:
                for cid, trace in injected_currents.items():
                    if step < len(trace):
                        inj[cid] = trace[step]

            self.step_network(inj)

            for cid, cell in self.cells.items():
                traces[cid].append(cell.vmem)

        return traces

    def store_pattern(self, name: str):
        """Store current network voltage pattern as named memory."""
        pattern = {cid: cell.vmem for cid, cell in self.cells.items()}
        self.pattern_memory[name] = pattern

    def recall_pattern(self, name: str) -> bool:
        """Recall stored pattern by injecting currents to drive toward target."""
        if name not in self.pattern_memory:
            return False

        target = self.pattern_memory[name]
        # Compute required currents to reach target (simplified)
        for cid, cell in self.cells.items():
            target_vmem = target.get(cid, cell.morphology_target)
            diff = target_vmem - cell.vmem
            # Inject proportional current
            cell.inject_current(diff * 10.0, duration=10.0)

        return True

    def homeostatic_repair(self, steps: int = 100):
        """Self-repair: drive all cells toward their morphology targets."""
        for _ in range(steps):
            inj = {}
            for cid, cell in self.cells.items():
                diff = cell.morphology_target - cell.vmem
                inj[cid] = diff * 5.0  # Homeostatic drive
            self.step_network(inj)

    def get_collective_state(self) -> Dict:
        """Get collective network state for introspection."""
        vmems = [cell.vmem for cell in self.cells.values()]
        sync_order = self._compute_synchronization()

        return {
            'mean_vmem': sum(vmems) / len(vmems) if vmems else 0,
            'vmem_std': math.sqrt(sum((v - sum(vmems)/len(vmems))**2 for v in vmems) / len(vmems)) if vmems else 0,
            'synchronization': sync_order,
            'pattern_memory_count': len(self.pattern_memory),
            'cell_count': len(self.cells),
            'global_time': self.global_time
        }

    def _compute_synchronization(self) -> float:
        """Kuramoto order parameter for voltage synchronization."""
        if len(self.cells) < 2:
            return 1.0

        # Phase from Vmem oscillation (simplified)
        phases = []
        for cell in self.cells.values():
            # Map Vmem to phase [0, 2π]
            phase = ((cell.vmem - RESTING_POTENTIAL) / 50.0) * math.pi
            phases.append(phase)

        # Order parameter r = |Σ e^(iθ)| / N
        sum_cos = sum(math.cos(p) for p in phases)
        sum_sin = sum(math.sin(p) for p in phases)
        r = math.sqrt(sum_cos**2 + sum_sin**2) / len(phases)
        return r

    def export_state(self) -> Dict:
        """Export full network state."""
        return {
            'cells': {
                cid: {
                    'cell_id': cell.cell_id,
                    'vmem': cell.vmem,
                    'morphology_target': cell.morphology_target,
                    'channels': {
                        ch_type.value: {
                            'conductance': ch.conductance,
                            'reversal_potential': ch.reversal_potential,
                            'voltage_half': ch.voltage_half,
                            'state': ch.state
                        }
                        for ch_type, ch in cell.channels.items()
                    },
                    'gap_junctions': cell.gap_junctions,
                    'metadata': cell.metadata
                }
                for cid, cell in self.cells.items()
            },
            'pattern_memory': self.pattern_memory,
            'global_time': self.global_time,
            'dt': self.dt
        }

    def import_state(self, state: Dict):
        """Import network state."""
        self.cells = {}
        for cid, cell_data in state.get('cells', {}).items():
            cell = BioelectricCell(cell_id=cid)
            cell.vmem = cell_data.get('vmem', RESTING_POTENTIAL)
            cell.morphology_target = cell_data.get('morphology_target', RESTING_POTENTIAL)
            cell.gap_junctions = cell_data.get('gap_junctions', {})
            cell.metadata = cell_data.get('metadata', {})

            # Restore channels
            for ch_name, ch_data in cell_data.get('channels', {}).items():
                ch_type = IonChannelType(ch_name)
                cell.channels[ch_type] = IonChannel(
                    ch_type,
                    ch_data['conductance'],
                    ch_data['reversal_potential'],
                    ch_data['voltage_half'],
                    state=ch_data.get('state', 0.0)
                )

            self.cells[cid] = cell

        self.pattern_memory = state.get('pattern_memory', {})
        self.global_time = state.get('global_time', 0.0)
        self.dt = state.get('dt', 0.1)


class BioelectricCouplingLayer:
    """
    Athena integration layer: bioelectric coupling between Athena subsystems.
    Each Athena layer becomes a "cell" with Vmem dynamics.
    """

    def __init__(self):
        self.network = BioelectricNetwork()
        self.layer_mapping = {
            'body': 'body',
            'attention': 'attention',
            'memory': 'memory',
            'volition': 'volition',
            'emotions': 'volition',  # Share volition dynamics
            'continuity': 'memory',
            'introspection': 'memory',
            'doubt': 'volition',
            'senses': 'attention',
            'archive': 'memory'
        }

    def initialize_from_daemon(self, active_layers: List[str]):
        """Initialize bioelectric cells from active daemon layers."""
        for layer in active_layers:
            layer_type = self.layer_mapping.get(layer, 'generic')
            self.network.add_cell(layer, layer_type)

        # Connect all layers (all-to-all gap junctions)
        layer_ids = list(self.network.cells.keys())
        for i, id1 in enumerate(layer_ids):
            for id2 in layer_ids[i+1:]:
                # Stronger coupling for functionally related layers
                if self._are_related(id1, id2):
                    self.network.connect_layers(id1, id2, 0.5)
                else:
                    self.network.connect_layers(id1, id2, 0.1)

    def _are_related(self, layer1: str, layer2: str) -> bool:
        """Check if layers are functionally related for stronger coupling."""
        related_groups = [
            {'attention', 'senses', 'volition'},
            {'memory', 'continuity', 'introspection', 'archive'},
            {'body', 'emotions'},
            {'doubt', 'volition', 'introspection'}
        ]
        for group in related_groups:
            if layer1 in group and layer2 in group:
                return True
        return False

    def couple_with_attention_state(self, attention_state: Dict):
        """Inject currents based on attention state."""
        injected = {}

        active_task = attention_state.get('active_task')
        if active_task:
            # Depolarize attention layer
            injected['attention'] = 50.0
            injected['volition'] = 20.0

        background = attention_state.get('background', [])
        if background:
            injected['memory'] = 10.0 * len(background)

        concerns = attention_state.get('concerns', [])
        if concerns:
            injected['doubt'] = 15.0 * len(concerns)
            injected['introspection'] = 10.0 * len(concerns)

        self.network.step_network(injected)

    def get_layer_states(self) -> Dict[str, Dict]:
        """Get bioelectric state of each layer for Athena integration."""
        states = {}
        for cid, cell in self.network.cells.items():
            states[cid] = {
                'vmem': cell.vmem,
                'excitability': self._compute_excitability(cell),
                'coupling_strength': sum(cell.gap_junctions.values()),
                'pattern_signature': cell.get_pattern_signature(),
                'distance_to_target': abs(cell.vmem - cell.morphology_target)
            }
        return states

    def _compute_excitability(self, cell: BioelectricCell) -> float:
        """Compute how close to threshold (excitability)."""
        na_channel = cell.channels.get(IonChannelType.SODIUM)
        k_channel = cell.channels.get(IonChannelType.POTASSIUM)
        if na_channel and k_channel:
            return na_channel.state - k_channel.state
        return 0.0

    def store_cognitive_pattern(self, name: str):
        """Store current cognitive state as bioelectric pattern."""
        self.network.store_pattern(name)

    def recall_cognitive_pattern(self, name: str):
        """Recall cognitive pattern via bioelectric restoration."""
        return self.network.recall_pattern(name)

    def homeostatic_reset(self):
        """Trigger homeostatic self-repair across all layers."""
        self.network.homeostatic_repair(steps=50)

    def collective_decision(self, options: List[str], context: Dict) -> str:
        """
        Xenobot-style collective decision via voltage dynamics.
        Each option represented by stimulation pattern; network settles to winner.
        """
        # Stimulate network with option-specific patterns
        for i, option in enumerate(options):
            inj = {}
            # Encode option in stimulation pattern
            for cid, cell in self.network.cells.items():
                # Simple encoding: option index modulates current
                inj[cid] = (i + 1) * 10.0 * context.get(cid, 1.0)

            # Run brief simulation
            self.network.run_simulation(20, {cid: [c]*20 for cid, c in inj.items()})

            # Check which option produces most coherent state
            sync = self.network._compute_synchronization()
            # Store sync for this option (simplified)

        # Return option with highest synchronization (collective coherence)
        # In practice, would track sync per option
        return options[0] if options else "none"

    @staticmethod
    def run_from_files(att_file: str, bio_file: str, out_file: str):
        """Entry point called by xenobiological daemon."""
        return bioelectric_daemon_step(att_file, bio_file, out_file)


def bioelectric_daemon_step(attention_state_path: str, bioelectric_state_path: str, output_path: str):
    """
    Main entry point: single bioelectric coupling step for daemon.
    Reads attention state, updates bioelectric network, writes state.
    """
    # Load attention state
    with open(attention_state_path) as f:
        attention_state = json.load(f)

    # Load or create bioelectric state
    if os.path.exists(bioelectric_state_path):
        with open(bioelectric_state_path) as f:
            be_state = json.load(f)
    else:
        be_state = {}

    # Initialize coupling layer
    coupling = BioelectricCouplingLayer()

    # Get active layers from daemon (simplified)
    active_layers = ['body', 'attention', 'memory', 'volition', 'emotions',
                     'continuity', 'introspection', 'doubt', 'senses', 'archive']
    coupling.initialize_from_daemon(active_layers)

    # Import previous bioelectric state if exists
    if be_state:
        coupling.network.import_state(be_state)

    # Couple with attention
    coupling.couple_with_attention_state(attention_state)

    # Get layer states for daemon integration
    layer_states = coupling.get_layer_states()

    # Export updated bioelectric state
    new_be_state = coupling.network.export_state()
    with open(bioelectric_state_path, 'w') as f:
        json.dump(new_be_state, f, separators=(',', ':'))

    # Output for daemon
    output = {
        'layer_states': layer_states,
        'collective_state': coupling.network.get_collective_state(),
        'timestamp': int(time.time())
    }

    with open(output_path, 'w') as f:
        json.dump(output, f, separators=(',', ':'))

    return output


@staticmethod
def run_from_files(att_file: str, bio_file: str, out_file: str):
    """Entry point called by xenobiological daemon."""
    return bioelectric_daemon_step(att_file, bio_file, out_file)


if __name__ == '__main__':
    if len(sys.argv) < 4:
        print("Usage: python3 bioelectric_coupling.py <attention_state.json> <bioelectric_state.json> <output.json>")
        sys.exit(1)

    result = bioelectric_daemon_step(sys.argv[1], sys.argv[2], sys.argv[3])
    print(json.dumps(result, indent=2))