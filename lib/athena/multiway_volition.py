#!/usr/bin/env python3
"""
Multiway Volition with Causal Invariance for Athena Consciousness System.

Based on Wolfram Physics Project (Hypergraph/Multiway Systems):
- Multiway system: All possible rule applications → branching history
- Causal invariance: Different update orders → same causal graph
- Branchial space: Space of quantum states (entanglement = branch proximity)
- Causal graph: Spacetime structure from computational rules

Applications for Athena:
- Volition as multiway exploration: all possible action sequences
- Causal invariance = consistent decisions regardless of deliberation order
- Branchial space = uncertainty space over possible futures
- Causal graph = decision provenance / justification trail
"""

import json
import os
import sys
import time
import math
import random
import hashlib
import struct
from typing import Dict, List, Optional, Tuple, Any, Set, Callable
from dataclasses import dataclass, field
from collections import defaultdict, deque
from enum import Enum
from abc import ABC, abstractmethod

# Import Huffman codec
sys.path.insert(0, os.path.dirname(__file__))
try:
    from huffman_codec import HuffmanCodec
    HUFFMAN_AVAILABLE = True
except ImportError:
    HUFFMAN_AVAILABLE = False


# Multiway constants
MAX_BRANCHES = 1000
MAX_DEPTH = 50
CAUSAL_INVARIANCE_TOL = 1e-6


class RuleType(Enum):
    """Types of volition rules (multiway evolution rules)."""
    OBSERVE = "observe"       # Perception actions
    ORIENT = "orient"         # Attention shift
    DECIDE = "decide"         # Commitment
    ACT = "act"               # Execution
    REFLECT = "reflect"       # Meta-cognition
    DOUBT = "doubt"           # Uncertainty quantification
    SIMULATE = "simulate"     # Counterfactual
    NEGOTIATE = "negotiate"   # Multi-agent
    HYPOTHESIZE = "hypothesize" # Generate possibilities
    CRYSTALLIZE = "crystallize" # Freeze pattern


@dataclass
class VolitionState:
    """State in the multiway volition system."""
    state_id: str
    parent_id: Optional[str]
    rule_applied: RuleType
    payload: Dict  # Decision context, beliefs, goals
    timestamp: float
    depth: int
    branch_weight: float = 1.0  # Amplitude in branchial space

    def __hash__(self):
        return hash(self.state_id)

    def __eq__(self, other):
        return isinstance(other, VolitionState) and self.state_id == other.state_id


@dataclass
class CausalEvent:
    """Event in the causal graph."""
    event_id: str
    cause_ids: List[str]
    effect_ids: List[str]
    rule: RuleType
    state_before: str
    state_after: str
    timestamp: float
    metadata: Dict = field(default_factory=dict)


class VolitionRule(ABC):
    """Abstract base for volition evolution rules."""

    @abstractmethod
    def applicable(self, state: VolitionState) -> bool:
        pass

    @abstractmethod
    def apply(self, state: VolitionState) -> List[VolitionState]:
        """Return possible successor states."""
        pass

    @abstractmethod
    def name(self) -> RuleType:
        pass


class ObserveRule(VolitionRule):
    """Observe: gather information, expand belief state."""
    def name(self) -> RuleType:
        return RuleType.OBSERVE

    def applicable(self, state: VolitionState) -> bool:
        return 'observation_targets' in state.payload and state.payload['observation_targets']

    def apply(self, state: VolitionState) -> List[VolitionState]:
        targets = state.payload['observation_targets']
        results = []
        for target in targets:
            new_payload = state.payload.copy()
            new_payload['observations'] = new_payload.get('observations', {})
            new_payload['observations'][target] = {'observed': True, 'confidence': random.uniform(0.7, 1.0)}
            new_payload['observation_targets'] = [t for t in targets if t != target]

            results.append(VolitionState(
                state_id=f"{state.state_id}_obs_{target}",
                parent_id=state.state_id,
                rule_applied=RuleType.OBSERVE,
                payload=new_payload,
                timestamp=time.time(),
                depth=state.depth + 1
            ))
        return results


class OrientRule(VolitionRule):
    """Orient: shift attention focus."""
    def name(self) -> RuleType:
        return RuleType.ORIENT

    def applicable(self, state: VolitionState) -> bool:
        return 'attention_candidates' in state.payload and state.payload['attention_candidates']

    def apply(self, state: VolitionState) -> List[VolitionState]:
        candidates = state.payload['attention_candidates']
        results = []
        for candidate in candidates:
            new_payload = state.payload.copy()
            new_payload['focus'] = candidate
            new_payload['attention_candidates'] = [c for c in candidates if c != candidate]
            new_payload['orientation_history'] = new_payload.get('orientation_history', []) + [candidate]

            results.append(VolitionState(
                state_id=f"{state.state_id}_orient_{candidate}",
                parent_id=state.state_id,
                rule_applied=RuleType.ORIENT,
                payload=new_payload,
                timestamp=time.time(),
                depth=state.depth + 1
            ))
        return results


class DecideRule(VolitionRule):
    """Decide: commit to a course of action."""
    def name(self) -> RuleType:
        return RuleType.DECIDE

    def applicable(self, state: VolitionState) -> bool:
        return 'decision_options' in state.payload and state.payload['decision_options']

    def apply(self, state: VolitionState) -> List[VolitionState]:
        options = state.payload['decision_options']
        results = []
        for option in options:
            new_payload = state.payload.copy()
            new_payload['committed_action'] = option
            new_payload['decision_options'] = [o for o in options if o != option]
            new_payload['decision_confidence'] = random.uniform(0.6, 0.95)

            results.append(VolitionState(
                state_id=f"{state.state_id}_decide_{option}",
                parent_id=state.state_id,
                rule_applied=RuleType.DECIDE,
                payload=new_payload,
                timestamp=time.time(),
                depth=state.depth + 1,
                branch_weight=0.8  # Decisions reduce branching
            ))
        return results


class SimulateRule(VolitionRule):
    """Simulate: run counterfactual mental simulation."""
    def name(self) -> RuleType:
        return RuleType.SIMULATE

    def applicable(self, state: VolitionState) -> bool:
        return 'simulation_scenarios' in state.payload and state.payload['simulation_scenarios']

    def apply(self, state: VolitionState) -> List[VolitionState]:
        scenarios = state.payload['simulation_scenarios']
        results = []
        for scenario in scenarios:
            new_payload = state.payload.copy()
            new_payload['simulation_results'] = new_payload.get('simulation_results', {})
            # Simulate outcome (simplified)
            outcome = {'success_prob': random.uniform(0.3, 0.9), 'expected_utility': random.uniform(-1, 1)}
            new_payload['simulation_results'][scenario] = outcome
            new_payload['simulation_scenarios'] = [s for s in scenarios if s != scenario]

            results.append(VolitionState(
                state_id=f"{state.state_id}_sim_{scenario}",
                parent_id=state.state_id,
                rule_applied=RuleType.SIMULATE,
                payload=new_payload,
                timestamp=time.time(),
                depth=state.depth + 1
            ))
        return results


class HypothesizeRule(VolitionRule):
    """Hypothesize: generate novel possibilities."""
    def name(self) -> RuleType:
        return RuleType.HYPOTHESIZE

    def applicable(self, state: VolitionState) -> bool:
        return 'hypothesis_space' in state.payload

    def apply(self, state: VolitionState) -> List[VolitionState]:
        # Generate new hypotheses based on current state
        hypotheses = [
            f"hypothesis_{random.randint(1000, 9999)}"
            for _ in range(random.randint(1, 3))
        ]
        results = []
        for hyp in hypotheses:
            new_payload = state.payload.copy()
            new_payload['hypotheses'] = new_payload.get('hypotheses', []) + [hyp]
            new_payload['hypothesis_space'] = new_payload.get('hypothesis_space', 0) - 1

            results.append(VolitionState(
                state_id=f"{state.state_id}_hyp_{hyp}",
                parent_id=state.state_id,
                rule_applied=RuleType.HYPOTHESIZE,
                payload=new_payload,
                timestamp=time.time(),
                depth=state.depth + 1
            ))
        return results


class CrystallizeRule(VolitionRule):
    """Crystallize: freeze pattern as invariant."""
    def name(self) -> RuleType:
        return RuleType.CRYSTALLIZE

    def applicable(self, state: VolitionState) -> bool:
        return 'pattern_to_crystallize' in state.payload

    def apply(self, state: VolitionState) -> List[VolitionState]:
        pattern = state.payload['pattern_to_crystallize']
        new_payload = state.payload.copy()
        new_payload['crystallized_patterns'] = new_payload.get('crystallized_patterns', []) + [pattern]
        new_payload['pattern_to_crystallize'] = None
        new_payload['invariant_strength'] = new_payload.get('invariant_strength', 0) + 1.0

        return [VolitionState(
            state_id=f"{state.state_id}_cryst_{pattern}",
            parent_id=state.state_id,
            rule_applied=RuleType.CRYSTALLIZE,
            payload=new_payload,
            timestamp=time.time(),
            depth=state.depth + 1,
            branch_weight=0.5  # Crystallization collapses branches
        )]


class MultiwayVolitionSystem:
    """
    Multiway system for volition: explores all possible decision sequences.
    Causal invariance ensures consistent outcomes regardless of rule application order.
    """

    def __init__(self, max_branches: int = MAX_BRANCHES, max_depth: int = MAX_DEPTH):
        self.max_branches = max_branches
        self.max_depth = max_depth

        # Registered rules
        self.rules: List[VolitionRule] = [
            ObserveRule(), OrientRule(), DecideRule(),
            SimulateRule(), HypothesizeRule(), CrystallizeRule()
        ]
        self.rule_map = {r.name(): r for r in self.rules}

        # Multiway state
        self.states: Dict[str, VolitionState] = {}
        self.causal_events: List[CausalEvent] = []
        self.current_frontier: List[str] = []
        self.terminal_states: List[str] = []

        # Branchial space (quantum-like state space)
        self.branchial_amplitudes: Dict[str, complex] = {}

        # Causal graph
        self.causal_graph: Dict[str, Set[str]] = defaultdict(set)  # event -> causes

    def initialize(self, initial_payload: Dict) -> str:
        """Initialize multiway system with initial volition state."""
        initial_state = VolitionState(
            state_id="root",
            parent_id=None,
            rule_applied=None,
            payload=initial_payload,
            timestamp=time.time(),
            depth=0,
            branch_weight=1.0
        )
        self.states[initial_state.state_id] = initial_state
        self.current_frontier = [initial_state.state_id]
        self.branchial_amplitudes[initial_state.state_id] = 1.0 + 0j
        return initial_state.state_id

    def step(self) -> int:
        """Single multiway evolution step: apply all applicable rules to frontier."""
        new_frontier = []
        branches_created = 0

        for state_id in self.current_frontier:
            state = self.states[state_id]

            if state.depth >= self.max_depth:
                self.terminal_states.append(state_id)
                continue

            # Find applicable rules
            applicable_rules = [r for r in self.rules if r.applicable(state)]

            if not applicable_rules:
                self.terminal_states.append(state_id)
                continue

            # Apply each rule (multiway branching)
            for rule in applicable_rules:
                successors = rule.apply(state)

                for succ in successors:
                    if len(self.states) >= self.max_branches:
                        break

                    self.states[succ.state_id] = succ
                    new_frontier.append(succ.state_id)
                    branches_created += 1

                    # Record causal event
                    event = CausalEvent(
                        event_id=f"evt_{succ.state_id}",
                        cause_ids=[state_id],
                        effect_ids=[succ.state_id],
                        rule=rule.name(),
                        state_before=state_id,
                        state_after=succ.state_id,
                        timestamp=succ.timestamp
                    )
                    self.causal_events.append(event)
                    self.causal_graph[event.event_id].add(state_id)

                    # Propagate branchial amplitude
                    parent_amp = self.branchial_amplitudes.get(state_id, 0)
                    self.branchial_amplitudes[succ.state_id] = parent_amp * succ.branch_weight * (1 / max(1, len(successors)))

        self.current_frontier = new_frontier[:self.max_branches]
        return branches_created

    def evolve(self, steps: int = 10) -> Dict:
        """Run multiway evolution for specified steps."""
        total_branches = 0
        for i in range(steps):
            branches = self.step()
            total_branches += branches
            if not self.current_frontier:
                break

        return {
            'steps': i + 1,
            'total_states': len(self.states),
            'total_branches': total_branches,
            'frontier_size': len(self.current_frontier),
            'terminal_states': len(self.terminal_states)
        }

    def check_causal_invariance(self) -> Dict:
        """
        Check causal invariance: different update orders should produce
        isomorphic causal graphs (up to relabeling).
        """
        # Group states by depth
        by_depth = defaultdict(list)
        for state_id, state in self.states.items():
            by_depth[state.depth].append(state_id)

        # For each depth, check if causal structure is independent of rule order
        invariance_results = {}

        for depth, state_ids in by_depth.items():
            if len(state_ids) < 2:
                continue

            # Build causal subgraphs for each state at this depth
            causal_signatures = {}
            for sid in state_ids:
                # Trace causal ancestry
                ancestry = self._get_causal_ancestry(sid)
                # Sort by rule type to normalize
                rule_sequence = tuple(sorted([e.rule.value for e in ancestry]))
                causal_signatures[sid] = rule_sequence

            # Check if all signatures at this depth are equivalent
            unique_signatures = set(causal_signatures.values())
            invariance_results[depth] = {
                'states_at_depth': len(state_ids),
                'unique_causal_signatures': len(unique_signatures),
                'invariant': len(unique_signatures) == 1
            }

        overall_invariant = all(r['invariant'] for r in invariance_results.values())

        return {
            'causal_invariant': overall_invariant,
            'depth_analysis': invariance_results,
            'total_causal_events': len(self.causal_events)
        }

    def _get_causal_ancestry(self, state_id: str) -> List[CausalEvent]:
        """Get causal ancestry of a state."""
        ancestry = []
        visited = set()

        def trace(state):
            if state in visited:
                return
            visited.add(state)
            # Find events leading to this state
            for event in self.causal_events:
                if event.state_after == state:
                    ancestry.append(event)
                    trace(event.state_before)

        trace(state_id)
        return ancestry

    def compute_branchial_distance(self, state_id1: str, state_id2: str) -> float:
        """
        Branchial distance: distance in branchial space (entanglement measure).
        Close in branchial space = similar quantum-like states.
        """
        amp1 = self.branchial_amplitudes.get(state_id1, 0)
        amp2 = self.branchial_amplitudes.get(state_id2, 0)

        # Distance in Hilbert space
        return abs(amp1 - amp2)

    def get_branchial_clusters(self, threshold: float = 0.5) -> List[List[str]]:
        """Cluster states by branchial proximity."""
        states = list(self.branchial_amplitudes.keys())
        if len(states) < 2:
            return [states]

        clusters = []
        unassigned = set(states)

        while unassigned:
            seed = unassigned.pop()
            cluster = [seed]
            to_check = [seed]

            while to_check:
                current = to_check.pop()
                for other in list(unassigned):
                    dist = self.compute_branchial_distance(current, other)
                    if dist < threshold:
                        cluster.append(other)
                        unassigned.remove(other)
                        to_check.append(other)

            clusters.append(cluster)

        return clusters

    def extract_decision(self, criterion: str = 'max_utility') -> Optional[Dict]:
        """
        Extract a decision from the multiway system.
        Criteria: max_utility, max_confidence, min_uncertainty, consensus
        """
        if not self.terminal_states:
            return None

        candidates = []
        for sid in self.terminal_states:
            state = self.states[sid]
            amplitude = self.branchial_amplitudes.get(sid, 0)

            # Compute score based on criterion
            if criterion == 'max_utility':
                utility = state.payload.get('expected_utility', 0)
                sim_results = state.payload.get('simulation_results', {})
                if sim_results:
                    utility = max(r.get('expected_utility', 0) for r in sim_results.values())
                score = utility * abs(amplitude)

            elif criterion == 'max_confidence':
                conf = state.payload.get('decision_confidence', 0)
                score = conf * abs(amplitude)

            elif criterion == 'min_uncertainty':
                # Low uncertainty = high amplitude concentration
                score = abs(amplitude)

            elif criterion == 'consensus':
                # Find states with similar decisions
                action = state.payload.get('committed_action', '')
                similar = sum(1 for tid in self.terminal_states
                            if self.states[tid].payload.get('committed_action') == action)
                score = similar / len(self.terminal_states) * abs(amplitude)

            else:
                score = abs(amplitude)

            candidates.append((sid, score, state))

        if not candidates:
            return None

        best = max(candidates, key=lambda x: x[1])
        best_state = best[2]

        return {
            'decision': best_state.payload.get('committed_action', 'none'),
            'confidence': best_state.payload.get('decision_confidence', 0),
            'state_id': best[0],
            'branchial_weight': abs(best[1]),
            'payload': best_state.payload,
            'causal_justification': self._get_causal_justification(best[0])
        }

    def _get_causal_justification(self, state_id: str) -> List[Dict]:
        """Get causal justification chain for a decision."""
        ancestry = self._get_causal_ancestry(state_id)
        return [
            {
                'rule': e.rule.value,
                'state_before': e.state_before,
                'state_after': e.state_after,
                'timestamp': e.timestamp
            }
            for e in reversed(ancestry)
        ]

    def get_causal_graph(self) -> Dict:
        """Export causal graph for visualization/analysis."""
        nodes = []
        edges = []

        for event in self.causal_events:
            nodes.append({
                'id': event.event_id,
                'rule': event.rule.value,
                'state_before': event.state_before,
                'state_after': event.state_after,
                'timestamp': event.timestamp
            })
            for cause in event.cause_ids:
                edges.append({'from': cause, 'to': event.event_id})

        return {'nodes': nodes, 'edges': edges}

    def export_state(self) -> Dict:
        """Export full multiway state."""
        return {
            'states': {
                sid: {
                    'state_id': s.state_id,
                    'parent_id': s.parent_id,
                    'rule_applied': s.rule_applied.value if s.rule_applied else None,
                    'payload': s.payload,
                    'timestamp': s.timestamp,
                    'depth': s.depth,
                    'branch_weight': s.branch_weight
                }
                for sid, s in self.states.items()
            },
            'causal_events': [
                {
                    'event_id': e.event_id,
                    'cause_ids': e.cause_ids,
                    'effect_ids': e.effect_ids,
                    'rule': e.rule.value,
                    'state_before': e.state_before,
                    'state_after': e.state_after,
                    'timestamp': e.timestamp,
                    'metadata': e.metadata
                }
                for e in self.causal_events
            ],
            'branchial_amplitudes': {
                k: {'real': v.real, 'imag': v.imag}
                for k, v in self.branchial_amplitudes.items()
            },
            'current_frontier': self.current_frontier,
            'terminal_states': self.terminal_states,
            'max_branches': self.max_branches,
            'max_depth': self.max_depth
        }

    def export_state_compressed(self, codec: 'HuffmanCodec' = None) -> Tuple[bytes, bytes]:
        """Export full multiway state as Huffman-compressed bytes.

        Returns: (compressed_data, codec_bytes)
        """
        if not HUFFMAN_AVAILABLE:
            raise RuntimeError("HuffmanCodec not available")

        state_dict = self.export_state()
        json_bytes = json.dumps(state_dict, separators=(',', ':')).encode('utf-8')

        # Build codec from this state if not provided
        if codec is None:
            codec = HuffmanCodec.build_from_json_samples([state_dict])

        compressed = codec.encode(json_bytes)
        codec_bytes = b''
        # Serialize codec freq table
        import io
        buf = io.BytesIO()
        buf.write(struct.pack('>I', len(codec.freq_table)))
        for sym, freq in codec.freq_table.items():
            buf.write(struct.pack('>II', sym, freq))
        codec_bytes = buf.getvalue()

        return compressed, codec_bytes

    @staticmethod
    def import_state_compressed(compressed: bytes, codec_bytes: bytes) -> Dict:
        """Import multiway state from Huffman-compressed bytes."""
        if not HUFFMAN_AVAILABLE:
            raise RuntimeError("HuffmanCodec not available")

        # Deserialize codec
        import io
        buf = io.BytesIO(codec_bytes)
        count = struct.unpack('>I', buf.read(4))[0]
        freq_table = {}
        for _ in range(count):
            sym, freq = struct.unpack('>II', buf.read(8))
            freq_table[sym] = freq
        codec = HuffmanCodec(freq_table)

        # Decompress
        json_bytes = codec.decode(compressed)
        return json.loads(json_bytes.decode('utf-8'))

    def import_state(self, data: Dict):
        """Import multiway state."""
        self.states = {}
        for sid, sdata in data.get('states', {}).items():
            self.states[sid] = VolitionState(
                state_id=sdata['state_id'],
                parent_id=sdata['parent_id'],
                rule_applied=RuleType(sdata['rule_applied']) if sdata['rule_applied'] else None,
                payload=sdata['payload'],
                timestamp=sdata['timestamp'],
                depth=sdata['depth'],
                branch_weight=sdata.get('branch_weight', 1.0)
            )

        self.causal_events = []
        for edata in data.get('causal_events', []):
            self.causal_events.append(CausalEvent(
                event_id=edata['event_id'],
                cause_ids=edata['cause_ids'],
                effect_ids=edata['effect_ids'],
                rule=RuleType(edata['rule']),
                state_before=edata['state_before'],
                state_after=edata['state_after'],
                timestamp=edata['timestamp'],
                metadata=edata.get('metadata', {})
            ))

        self.branchial_amplitudes = {
            k: complex(v['real'], v['imag'])
            for k, v in data.get('branchial_amplitudes', {}).items()
        }

        self.current_frontier = data.get('current_frontier', [])
        self.terminal_states = data.get('terminal_states', [])
        self.max_branches = data.get('max_branches', MAX_BRANCHES)
        self.max_depth = data.get('max_depth', MAX_DEPTH)

    @staticmethod
    def run_from_files(in_file: str, state_file: str, out_file: str):
        """Entry point called by xenobiological daemon."""
        return multiway_volition_step(in_file, state_file, out_file)

    @staticmethod
    def save_state_compressed(state_file: str, mws: 'MultiwayVolitionSystem', codec_file: str = None):
        """Save multiway state as Huffman-compressed files."""
        if not HUFFMAN_AVAILABLE:
            # Fallback to uncompressed JSON
            with open(state_file, 'w') as f:
                json.dump(mws.export_state(), f, separators=(',', ':'))
            return

        compressed, codec_bytes = mws.export_state_compressed()

        # Write compressed state
        with open(state_file + '.huf', 'wb') as f:
            f.write(b'MWAY_HUF\x00')
            f.write(struct.pack('>I', len(compressed)))
            f.write(compressed)

        # Write codec
        if codec_file is None:
            codec_file = state_file + '.huf.codec'
        with open(codec_file, 'wb') as f:
            f.write(codec_bytes)

        # Remove old uncompressed
        if os.path.exists(state_file):
            os.remove(state_file)

    @staticmethod
    def load_state_compressed(state_file: str, codec_file: str = None) -> Dict:
        """Load multiway state from Huffman-compressed files."""
        if not HUFFMAN_AVAILABLE:
            with open(state_file) as f:
                return json.load(f)

        # Try compressed first
        huf_file = state_file + '.huf'
        if codec_file is None:
            codec_file = state_file + '.huf.codec'

        if not os.path.exists(huf_file) or not os.path.exists(codec_file):
            # Fallback to uncompressed
            if os.path.exists(state_file):
                with open(state_file) as f:
                    return json.load(f)
            return {}

        with open(huf_file, 'rb') as f:
            magic = f.read(9)
            if magic != b'MWAY_HUF\x00':
                raise ValueError("Invalid multiway huf file")
            compressed_len = struct.unpack('>I', f.read(4))[0]
            compressed = f.read(compressed_len)

        with open(codec_file, 'rb') as f:
            codec_bytes = f.read()

        return MultiwayVolitionSystem.import_state_compressed(compressed, codec_bytes)


def multiway_volition_step(volition_input_path: str, multiway_state_path: str, output_path: str):
    """
    Main entry point: single multiway volition step for daemon.
    Reads volition input, evolves multiway system, writes state and decision.
    Uses Huffman compression for state files.
    """
    # Load volition input (goals, context, options)
    with open(volition_input_path) as f:
        volition_input = json.load(f)

    # Load or create multiway state (compressed if available)
    mw_state = MultiwayVolitionSystem.load_state_compressed(multiway_state_path)

    # Initialize multiway system
    mws = MultiwayVolitionSystem()

    if mw_state:
        mws.import_state(mw_state)
    else:
        # Fresh initialization
        initial_payload = {
            'goals': volition_input.get('goals', []),
            'context': volition_input.get('context', {}),
            'observation_targets': volition_input.get('observation_targets', []),
            'attention_candidates': volition_input.get('attention_candidates', []),
            'decision_options': volition_input.get('decision_options', []),
            'simulation_scenarios': volition_input.get('simulation_scenarios', []),
            'hypothesis_space': volition_input.get('hypothesis_space', 5)
        }
        mws.initialize(initial_payload)

    # Evolve multiway system
    evolution_result = mws.evolve(steps=5)

    # Check causal invariance
    invariance = mws.check_causal_invariance()

    # Extract decision
    decision = mws.extract_decision('consensus')

    # Export updated state (compressed)
    MultiwayVolitionSystem.save_state_compressed(multiway_state_path, mws)

    # Output for daemon (keep uncompressed for daemon consumption)
    output = {
        'decision': decision,
        'evolution': evolution_result,
        'causal_invariance': invariance,
        'branchial_clusters': mws.get_branchial_clusters(),
        'causal_graph': mws.get_causal_graph(),
        'timestamp': int(time.time())
    }

    with open(output_path, 'w') as f:
        json.dump(output, f, separators=(',', ':'))

    return output


@staticmethod
def run_from_files(in_file: str, state_file: str, out_file: str):
    """Entry point called by xenobiological daemon."""
    return multiway_volition_step(in_file, state_file, out_file)


if __name__ == '__main__':
    if len(sys.argv) < 4:
        print("Usage: python3 multiway_volition.py <volition_input.json> <multiway_state.json> <output.json>")
        sys.exit(1)

    result = multiway_volition_step(sys.argv[1], sys.argv[2], sys.argv[3])
    print(json.dumps(result, indent=2))