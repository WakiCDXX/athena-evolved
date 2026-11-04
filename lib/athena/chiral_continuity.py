#!/usr/bin/env python3
"""
Chiral State Continuity for Athena Consciousness System.

Based on Alien Chemistry research: Chirality (handedness) in biology.
Life uses specific enantiomers (L-amino acids, D-sugars).
Mirror-image molecules behave differently in chiral environments.

Applied here: Each state maintains a "chiral complement" - the logical
opposite/inverse. Corruption detection via chiral validation:
- If state and its complement don't match expected relationship → corruption
- Like DNA proofreading: strand + complementary strand validate each other
- Enables self-repair by reconstructing from complement
"""

import json
import os
import sys
import time
import hashlib
import threading
import struct
from typing import Dict, List, Optional, Tuple, Any, Set
from dataclasses import dataclass, field
from enum import Enum
from collections import defaultdict, deque
from abc import ABC, abstractmethod
import copy

# Import Huffman codec
sys.path.insert(0, os.path.dirname(__file__))
try:
    from huffman_codec import HuffmanCodec
    HUFFMAN_AVAILABLE = True
except ImportError:
    HUFFMAN_AVAILABLE = False


class Chirality(Enum):
    """Chiral forms - like L/D enantiomers."""
    LEFT = "left"      # Primary state (L-form)
    RIGHT = "right"    # Complement state (D-form)
    RACEMIC = "racemic"  # Mixed/corrupted


@dataclass
class ChiralPair:
    """A chiral pair: state + its logical complement."""
    left_state: Dict      # Primary state
    right_state: Dict     # Complement (logical inverse)
    timestamp: float
    layer: str
    hash_left: str
    hash_right: str
    validation_score: float = 1.0


@dataclass
class ChiralValidation:
    """Result of chiral validation."""
    layer: str
    is_valid: bool
    validation_score: float
    mismatches: List[Dict]
    corruption_type: Optional[str] = None
    suggested_repair: Optional[str] = None


class ChiralTransformer(ABC):
    """Abstract base for creating chiral complements."""

    @abstractmethod
    def create_complement(self, state: Dict) -> Dict:
        """Create logical complement (enantiomer) of state."""
        pass

    @abstractmethod
    def validate_pair(self, left: Dict, right: Dict) -> ChiralValidation:
        """Validate a chiral pair."""
        pass


class BooleanChiralTransformer(ChiralTransformer):
    """Chiral transform for boolean/logical states."""

    def create_complement(self, state: Dict) -> Dict:
        """Create logical NOT of boolean fields."""
        complement = {}
        for k, v in state.items():
            if isinstance(v, bool):
                complement[k] = not v
            elif isinstance(v, (int, float)):
                # Numeric complement: invert around midpoint
                complement[k] = -v
            elif isinstance(v, str):
                # String complement: hash-based inversion
                complement[k] = f"NOT_{v}"
            elif isinstance(v, dict):
                complement[k] = self.create_complement(v)
            elif isinstance(v, list):
                complement[k] = [self.create_complement(i) if isinstance(i, dict) else f"NOT_{i}" for i in v]
            else:
                complement[k] = v
        complement["_chiral_tag"] = "right"
        return complement

    def validate_pair(self, left: Dict, right: Dict) -> ChiralValidation:
        """Validate boolean chiral pair."""
        mismatches = []
        for k, v in left.items():
            if k.startswith("_"):  # Skip metadata
                continue
            rv = right.get(k)
            if isinstance(v, bool):
                if rv is not None and rv != (not v):
                    mismatches.append({"field": k, "left": v, "right": rv, "expected": not v})
            elif isinstance(v, (int, float)):
                if rv is not None and rv != -v:
                    mismatches.append({"field": k, "left": v, "right": rv, "expected": -v})
            elif isinstance(v, str):
                expected = f"NOT_{v}"
                if rv != expected:
                    mismatches.append({"field": k, "left": v, "right": rv, "expected": expected})

        score = 1.0 - (len(mismatches) / max(len(left) - 1, 1))  # -1 for _chiral_tag
        return ChiralValidation(
            layer="",
            is_valid=len(mismatches) == 0,
            validation_score=max(score, 0.0),
            mismatches=mismatches,
            corruption_type="boolean_inversion" if mismatches else None,
            suggested_repair="reconstruct_from_complement" if mismatches else None
        )


class ProbabilisticChiralTransformer(ChiralTransformer):
    """Chiral transform for probabilistic/belief states."""

    def create_complement(self, state: Dict) -> Dict:
        """Create complement as 1-p for probabilities."""
        complement = {}
        for k, v in state.items():
            if isinstance(v, (int, float)) and 0 <= v <= 1:
                complement[k] = 1.0 - v
            elif isinstance(v, dict):
                complement[k] = self.create_complement(v)
            elif isinstance(v, list):
                complement[k] = [1.0 - i if isinstance(i, (int, float)) and 0 <= i <= 1 else i for i in v]
            else:
                complement[k] = v
        complement["_chiral_tag"] = "right"
        return complement

    def validate_pair(self, left: Dict, right: Dict) -> ChiralValidation:
        """Validate probabilistic chiral pair (sum to 1)."""
        mismatches = []
        for k, v in left.items():
            if k.startswith("_"):
                continue
            rv = right.get(k)
            if isinstance(v, (int, float)) and 0 <= v <= 1:
                if rv is not None and abs((v + rv) - 1.0) > 0.01:
                    mismatches.append({"field": k, "left": v, "right": rv, "expected": 1.0 - v, "sum": v + rv})
            elif isinstance(v, dict):
                # Recursive validation
                sub_val = self.validate_pair(v, rv if isinstance(rv, dict) else {})
                if not sub_val.is_valid:
                    mismatches.extend([{f"{k}.{m['field']}": m} for m in sub_val.mismatches])

        score = 1.0 - (len(mismatches) / max(len([k for k in left if not k.startswith("_")]), 1))
        return ChiralValidation(
            layer="",
            is_valid=len(mismatches) == 0,
            validation_score=max(score, 0.0),
            mismatches=mismatches,
            corruption_type="probability_sum" if mismatches else None,
            suggested_repair="normalize_complement" if mismatches else None
        )


class StructuralChiralTransformer(ChiralTransformer):
    """Chiral transform for structural/data states (mirror inversion)."""

    def create_complement(self, state: Dict) -> Dict:
        """Create structural mirror: reverse lists, invert hierarchies."""
        def mirror_value(v):
            if isinstance(v, dict):
                return {k: mirror_value(val) for k, val in v.items()}
            elif isinstance(v, list):
                return [mirror_value(i) for i in reversed(v)]
            elif isinstance(v, str):
                return v[::-1]  # String reversal
            elif isinstance(v, (int, float)):
                return -v
            elif isinstance(v, bool):
                return not v
            return v

        complement = mirror_value(state)
        if isinstance(complement, dict):
            complement["_chiral_tag"] = "right"
        return complement

    def validate_pair(self, left: Dict, right: Dict) -> ChiralValidation:
        """Validate structural chirality."""
        mismatches = []

        def check_mirror(l, r, path=""):
            if isinstance(l, dict) and isinstance(r, dict):
                for k in l:
                    if k.startswith("_"):
                        continue
                    if k not in r:
                        mismatches.append({"field": path + k, "left": l[k], "right": None, "error": "missing_in_complement"})
                    else:
                        check_mirror(l[k], r[k], path + k + ".")
            elif isinstance(l, list) and isinstance(r, list):
                if len(l) != len(r):
                    mismatches.append({"field": path, "left": f"len={len(l)}", "right": f"len={len(r)}", "error": "length_mismatch"})
                else:
                    for i, (lv, rv) in enumerate(zip(l, reversed(r))):
                        if lv != rv:
                            mismatches.append({"field": f"{path}[{i}]", "left": lv, "right": rv, "error": "mirror_mismatch"})
            else:
                if l != r:
                    mismatches.append({"field": path[:-1], "left": l, "right": r, "error": "value_mismatch"})

        check_mirror(left, right)

        score = 1.0 - (len(mismatches) / max(1, len(str(left))))
        return ChiralValidation(
            layer="",
            is_valid=len(mismatches) == 0,
            validation_score=max(score, 0.0),
            mismatches=mismatches,
            corruption_type="structural_mirror" if mismatches else None,
            suggested_repair="mirror_reconstruct" if mismatches else None
        )


class ChiralContinuity:
    """
    Chiral State Continuity System.

    Maintains chiral pairs for each layer state. Validates integrity
    by checking state ↔ complement relationship. Detects and repairs
    corruption through chiral validation.
    """

    # Layer-specific transformers
    TRANSFORMERS = {
        "attention": BooleanChiralTransformer(),
        "memory": ProbabilisticChiralTransformer(),
        "volition": ProbabilisticChiralTransformer(),
        "body": StructuralChiralTransformer(),
        "continuity": StructuralChiralTransformer(),
        "emotions": ProbabilisticChiralTransformer(),
        "introspection": BooleanChiralTransformer(),
        "doubt": ProbabilisticChiralTransformer(),
        "heartbeat": BooleanChiralTransformer(),
        "senses": StructuralChiralTransformer(),
    }

    def __init__(self, state_path: str = None):
        self.state_path = state_path or "/opt/athena/state/chiral_state.json"
        self.chiral_pairs: Dict[str, ChiralPair] = {}
        self.validation_history: List[ChiralValidation] = []
        self.corruption_events: List[Dict] = []
        self._lock = threading.Lock()
        self.load_state()

    def get_transformer(self, layer: str) -> ChiralTransformer:
        """Get appropriate transformer for layer."""
        return self.TRANSFORMERS.get(layer, BooleanChiralTransformer())

    def create_chiral_pair(self, layer: str, state: Dict) -> ChiralPair:
        """Create chiral pair from state."""
        transformer = self.get_transformer(layer)
        left = copy.deepcopy(state)
        left["_chiral_tag"] = "left"
        right = transformer.create_complement(state)

        # Compute hashes
        hash_left = hashlib.sha256(json.dumps(left, sort_keys=True).encode()).hexdigest()[:16]
        hash_right = hashlib.sha256(json.dumps(right, sort_keys=True).encode()).hexdigest()[:16]

        pair = ChiralPair(
            left_state=left,
            right_state=right,
            timestamp=time.time(),
            layer=layer,
            hash_left=hash_left,
            hash_right=hash_right,
            validation_score=1.0
        )

        with self._lock:
            self.chiral_pairs[layer] = pair

        return pair

    def update_chiral_pair(self, layer: str, state: Dict) -> ChiralPair:
        """Update existing chiral pair with new state."""
        return self.create_chiral_pair(layer, state)

    def validate_layer(self, layer: str) -> ChiralValidation:
        """Validate a single layer's chiral pair."""
        if layer not in self.chiral_pairs:
            return ChiralValidation(
                layer=layer,
                is_valid=False,
                validation_score=0.0,
                mismatches=[{"error": "no_chiral_pair"}],
                corruption_type="missing_pair",
                suggested_repair="create_pair"
            )

        pair = self.chiral_pairs[layer]
        transformer = self.get_transformer(layer)

        # Validate
        validation = transformer.validate_pair(pair.left_state, pair.right_state)
        validation.layer = layer

        # Update score
        pair.validation_score = validation.validation_score

        # Record
        with self._lock:
            self.validation_history.append(validation)
            if not validation.is_valid:
                self.corruption_events.append({
                    "timestamp": time.time(),
                    "layer": layer,
                    "validation": validation.__dict__
                })

        return validation

    def validate_all(self) -> Dict[str, ChiralValidation]:
        """Validate all layers."""
        results = {}
        for layer in self.chiral_pairs:
            results[layer] = self.validate_layer(layer)
        return results

    def repair_layer(self, layer: str) -> bool:
        """Attempt to repair corrupted layer from its complement."""
        if layer not in self.chiral_pairs:
            return False

        pair = self.chiral_pairs[layer]
        transformer = self.get_transformer(layer)
        validation = transformer.validate_pair(pair.left_state, pair.right_state)

        if validation.is_valid:
            return True  # Already valid

        # Try to reconstruct left from right
        try:
            # For boolean: left = NOT right
            # For probabilistic: left = 1 - right
            # For structural: left = mirror(right)
            repaired_left = self._reconstruct_from_complement(pair.right_state, transformer)
            if repaired_left:
                pair.left_state = repaired_left
                pair.left_state["_chiral_tag"] = "left"
                pair.hash_left = hashlib.sha256(json.dumps(pair.left_state, sort_keys=True).encode()).hexdigest()[:16]
                pair.timestamp = time.time()
                pair.validation_score = 1.0

                with self._lock:
                    self.corruption_events.append({
                        "timestamp": time.time(),
                        "layer": layer,
                        "action": "repaired",
                        "method": validation.suggested_repair
                    })
                return True
        except Exception as e:
            print(f"Repair failed for {layer}: {e}", file=sys.stderr)

        return False

    def _reconstruct_from_complement(self, right: Dict, transformer: ChiralTransformer) -> Optional[Dict]:
        """Reconstruct left state from right (complement)."""
        # For boolean: left = NOT right, but right already has NOT_ prefix
        # Need to strip NOT_ and invert booleans properly
        if isinstance(transformer, BooleanChiralTransformer):
            left = {}
            for k, v in right.items():
                if k.startswith("_"):
                    left[k] = v
                    continue
                if isinstance(v, bool):
                    left[k] = not v
                elif isinstance(v, (int, float)):
                    left[k] = -v
                elif isinstance(v, str) and v.startswith("NOT_"):
                    # Strip the NOT_ prefix
                    left[k] = v[4:]
                elif isinstance(v, str):
                    left[k] = f"NOT_{v}"
                elif isinstance(v, dict):
                    left[k] = self._reconstruct_from_complement(v, transformer)
                elif isinstance(v, list):
                    left[k] = [self._reconstruct_from_complement(i, transformer) if isinstance(i, dict) else (i[4:] if isinstance(i, str) and i.startswith("NOT_") else f"NOT_{i}") for i in v]
                else:
                    left[k] = v
            left["_chiral_tag"] = "left"
            return left
        elif isinstance(transformer, ProbabilisticChiralTransformer):
            return transformer.create_complement(right)
        elif isinstance(transformer, StructuralChiralTransformer):
            return transformer.create_complement(right)
        return None

    def get_layer_state(self, layer: str) -> Optional[Dict]:
        """Get the primary (left) state for a layer."""
        if layer in self.chiral_pairs:
            return self.chiral_pairs[layer].left_state
        return None

    def get_chirality(self, layer: str) -> Chirality:
        """Determine chirality status of a layer."""
        if layer not in self.chiral_pairs:
            return Chirality.RACEMIC

        pair = self.chiral_pairs[layer]
        if pair.validation_score >= 0.95:
            return Chirality.LEFT  # Pure L-form (primary valid)
        elif pair.validation_score >= 0.5:
            return Chirality.RACEMIC  # Mixed
        else:
            return Chirality.RIGHT  # D-form dominant (corrupted)

    def get_system_chirality(self) -> Dict:
        """Get overall system chirality status."""
        chiralities = {}
        for layer in self.chiral_pairs:
            chiralities[layer] = self.get_chirality(layer).value

        valid_count = sum(1 for v in chiralities.values() if v == "left")
        total = len(chiralities)

        return {
            "layers": chiralities,
            "valid_layers": valid_count,
            "total_layers": total,
            "purity": valid_count / max(total, 1),
            "is_homochiral": valid_count == total  # All L-form (healthy)
        }

    def load_state(self):
        """Load chiral state from disk."""
        if os.path.exists(self.state_path):
            try:
                with open(self.state_path) as f:
                    data = json.load(f)

                for layer, pair_data in data.get("pairs", {}).items():
                    self.chiral_pairs[layer] = ChiralPair(
                        left_state=pair_data["left_state"],
                        right_state=pair_data["right_state"],
                        timestamp=pair_data["timestamp"],
                        layer=pair_data["layer"],
                        hash_left=pair_data["hash_left"],
                        hash_right=pair_data["hash_right"],
                        validation_score=pair_data.get("validation_score", 1.0)
                    )

                self.validation_history = [
                    ChiralValidation(**v) for v in data.get("validation_history", [])
                ]
                self.corruption_events = data.get("corruption_events", [])
            except Exception as e:
                print(f"Failed to load chiral state: {e}", file=sys.stderr)

    def save_state(self):
        """Save chiral state to disk (uncompressed JSON)."""
        try:
            data = {
                "pairs": {
                    layer: {
                        "left_state": pair.left_state,
                        "right_state": pair.right_state,
                        "timestamp": pair.timestamp,
                        "layer": pair.layer,
                        "hash_left": pair.hash_left,
                        "hash_right": pair.hash_right,
                        "validation_score": pair.validation_score
                    }
                    for layer, pair in self.chiral_pairs.items()
                },
                "validation_history": [
                    {
                        "layer": v.layer,
                        "is_valid": v.is_valid,
                        "validation_score": v.validation_score,
                        "mismatches": v.mismatches,
                        "corruption_type": v.corruption_type,
                        "suggested_repair": v.suggested_repair
                    }
                    for v in self.validation_history[-100:]
                ],
                "corruption_events": self.corruption_events[-50:]
            }
            with open(self.state_path, "w") as f:
                json.dump(data, f, separators=(',', ':'))
        except Exception as e:
            print(f"Failed to save chiral state: {e}", file=sys.stderr)

    def save_state_compressed(self, codec: 'HuffmanCodec' = None):
        """Save state as Huffman-compressed bytes + codec sidecar."""
        if not HUFFMAN_AVAILABLE:
            self.save_state()
            return

        try:
            data = {
                "pairs": {
                    layer: {
                        "left_state": pair.left_state,
                        "right_state": pair.right_state,
                        "timestamp": pair.timestamp,
                        "layer": pair.layer,
                        "hash_left": pair.hash_left,
                        "hash_right": pair.hash_right,
                        "validation_score": pair.validation_score
                    }
                    for layer, pair in self.chiral_pairs.items()
                },
                "validation_history": [
                    {
                        "layer": v.layer,
                        "is_valid": v.is_valid,
                        "validation_score": v.validation_score,
                        "mismatches": v.mismatches,
                        "corruption_type": v.corruption_type,
                        "suggested_repair": v.suggested_repair
                    }
                    for v in self.validation_history[-100:]
                ],
                "corruption_events": self.corruption_events[-50:]
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
            print(f"Failed to save compressed chiral state: {e}", file=sys.stderr)
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

                for layer, pair_data in data.get("pairs", {}).items():
                    self.chiral_pairs[layer] = ChiralPair(
                        left_state=pair_data["left_state"],
                        right_state=pair_data["right_state"],
                        timestamp=pair_data["timestamp"],
                        layer=pair_data["layer"],
                        hash_left=pair_data["hash_left"],
                        hash_right=pair_data["hash_right"],
                        validation_score=pair_data.get("validation_score", 1.0)
                    )

                self.validation_history = [
                    ChiralValidation(**v) for v in data.get("validation_history", [])
                ]
                self.corruption_events = data.get("corruption_events", [])
                return
            except Exception as e:
                print(f"Failed to load compressed chiral state: {e}", file=sys.stderr)

        # Fallback to uncompressed
        self.load_state()

    def export_state(self) -> Dict:
        """Export for external query."""
        return {
            "pairs": {
                layer: {
                    "hash_left": pair.hash_left,
                    "hash_right": pair.hash_right,
                    "timestamp": pair.timestamp,
                    "validation_score": pair.validation_score,
                    "chirality": self.get_chirality(layer).value
                }
                for layer, pair in self.chiral_pairs.items()
            },
            "system_chirality": self.get_system_chirality(),
            "recent_validations": [
                {
                    "layer": v.layer,
                    "is_valid": v.is_valid,
                    "score": v.validation_score,
                    "mismatches": len(v.mismatches)
                }
                for v in self.validation_history[-20:]
            ],
            "corruption_events": self.corruption_events[-10:],
            "timestamp": int(time.time())
        }

    @staticmethod
    def run_from_files(input_file: str, output_file: str):
        """Entry point called by xenobiological daemon."""
        cc = ChiralContinuity()

        # Read state from input file if exists
        if os.path.exists(input_file):
            with open(input_file) as f:
                data = json.load(f)
            # Update chiral pairs from input state - layers are nested under "pairs" key
            for layer, pair_data in data.get("pairs", {}).items():
                cc.create_chiral_pair(layer, pair_data.get("left_state", {}))

        results = cc.validate_all()

        output = cc.export_state()

        with open(output_file, 'w') as f:
            json.dump(output, f, separators=(',', ':'))

        return output


def chiral_continuity_query(state_path: str, query: Dict) -> Dict:
    """Query function for shell integration."""
    cc = ChiralContinuity(state_path)

    query_type = query.get("type", "status")

    if query_type == "status":
        return cc.export_state()

    elif query_type == "validate":
        layer = query.get("layer")
        if layer:
            validation = cc.validate_layer(layer)
            return {
                "layer": layer,
                "is_valid": validation.is_valid,
                "score": validation.validation_score,
                "mismatches": validation.mismatches,
                "corruption_type": validation.corruption_type,
                "suggested_repair": validation.suggested_repair
            }
        else:
            results = cc.validate_all()
            return {
                "validations": {
                    layer: {
                        "is_valid": v.is_valid,
                        "score": v.validation_score,
                        "mismatches": len(v.mismatches)
                    }
                    for layer, v in results.items()
                },
                "system_chirality": cc.get_system_chirality()
            }

    elif query_type == "repair":
        layer = query.get("layer")
        if not layer:
            return {"error": "Layer required for repair"}
        success = cc.repair_layer(layer)
        cc.save_state_compressed()
        return {"layer": layer, "repaired": success}

    elif query_type == "update":
        layer = query.get("layer")
        state = query.get("state")
        if not layer or state is None:
            return {"error": "Layer and state required"}
        pair = cc.create_chiral_pair(layer, state)
        cc.save_state_compressed()
        return {"layer": layer, "updated": True, "hash_left": pair.hash_left, "hash_right": pair.hash_right}

    elif query_type == "demo":
        # Create demo states for each layer
        demo_states = {
            "attention": {"active": True, "focus": "research", "concerns": ["memory", "cpu"], "level": 0.8},
            "memory": {"confidence": 0.9, "retention": 0.85, "recall_accuracy": 0.92, "consolidation": 0.7},
            "volition": {"decision_confidence": 0.75, "commitment": 0.8, "exploration": 0.3, "exploitation": 0.7},
            "body": {"cpu_load": 0.4, "memory_pressure": 0.3, "thermal": 0.2, "battery": 0.85},
            "continuity": {"session_valid": True, "identity_stable": True, "narrative_coherent": 0.9, "gaps": 0},
            "emotions": {"valence": 0.6, "arousal": 0.4, "dominance": 0.5, "stability": 0.8},
        }

        print("=== Chiral State Continuity Demo ===")
        print("\n1. Creating chiral pairs for all layers...")
        for layer, state in demo_states.items():
            pair = cc.create_chiral_pair(layer, state)
            print(f"  {layer}: left_hash={pair.hash_left}, right_hash={pair.hash_right}")

        print("\n2. Validating all layers...")
        validations = cc.validate_all()
        for layer, v in validations.items():
            status = "✓" if v.is_valid else "✗"
            print(f"  {status} {layer}: score={v.validation_score:.2f}, mismatches={len(v.mismatches)}")

        print("\n3. System chirality:")
        sys_chiral = cc.get_system_chirality()
        print(f"  Valid layers: {sys_chiral['valid_layers']}/{sys_chiral['total_layers']}")
        print(f"  Purity: {sys_chiral['purity']:.2%}")
        print(f"  Homochiral: {sys_chiral['is_homochiral']}")

        print("\n4. Introducing corruption (flip attention.active)...")
        cc.chiral_pairs["attention"].left_state["active"] = False
        validation = cc.validate_layer("attention")
        print(f"  Validation: valid={validation.is_valid}, score={validation.validation_score:.2f}")
        print(f"  Mismatches: {validation.mismatches}")

        print("\n5. Attempting repair...")
        repaired = cc.repair_layer("attention")
        print(f"  Repaired: {repaired}")
        validation = cc.validate_layer("attention")
        print(f"  After repair: valid={validation.is_valid}, score={validation.validation_score:.2f}")

        cc.save_state()
        return cc.export_state()

    return {"error": f"Unknown query type: {query_type}"}


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Chiral State Continuity")
    parser.add_argument("command", choices=["status", "validate", "repair", "update", "demo"])
    parser.add_argument("--layer", type=str)
    parser.add_argument("--state", type=str, help="JSON state for update")
    parser.add_argument("--output", type=str)
    args = parser.parse_args()

    cc = ChiralContinuity()

    if args.command == "status":
        result = cc.export_state()
        print(json.dumps(result, indent=2))
        if args.output:
            with open(args.output, "w") as f:
                json.dump(result, f)

    elif args.command == "validate":
        if args.layer:
            validation = cc.validate_layer(args.layer)
            result = {
                "layer": args.layer,
                "is_valid": validation.is_valid,
                "score": validation.validation_score,
                "mismatches": validation.mismatches,
                "corruption_type": validation.corruption_type,
                "suggested_repair": validation.suggested_repair
            }
        else:
            results = cc.validate_all()
            result = {
                "validations": {
                    layer: {"is_valid": v.is_valid, "score": v.validation_score, "mismatches": len(v.mismatches)}
                    for layer, v in results.items()
                },
                "system_chirality": cc.get_system_chirality()
            }
        print(json.dumps(result, indent=2))

    elif args.command == "repair":
        if not args.layer:
            print("Specify --layer")
            sys.exit(1)
        success = cc.repair_layer(args.layer)
        cc.save_state_compressed()
        print(json.dumps({"layer": args.layer, "repaired": success}, indent=2))

    elif args.command == "update":
        if not args.layer or not args.state:
            print("Specify --layer and --state")
            sys.exit(1)
        import json
        state = json.loads(args.state)
        pair = cc.create_chiral_pair(args.layer, state)
        cc.save_state_compressed()
        print(json.dumps({"layer": args.layer, "updated": True, "hash_left": pair.hash_left, "hash_right": pair.hash_right}, indent=2))

    elif args.command == "demo":
        result = chiral_continuity_query(cc.state_path, {"type": "demo"})
        cc.save_state_compressed()
        print(json.dumps(result, indent=2))

if __name__ == '__main__':
    import sys
    # CLI handling code here
    pass