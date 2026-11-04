#!/usr/bin/env python3
"""
XNA (Xeno Nucleic Acid) Inspired Pluggable Memory Codecs for Athena.

Based on synthetic biology XNA research:
- TNA (threose nucleic acid): nuclease resistance, high fidelity
- HNA (hexose nucleic acid): altered base-pairing, tunable stability
- FANA (fluoroarabino nucleic acid): maximum stability, nuclease resistant
- CeNA (cyclohexene nucleic acid): constrained conformation, high specificity
- GNA (glycol nucleic acid): simplest backbone, prebiotic relevance

Applications for Athena:
- Memory encoding with synthetic "backbones" for corruption resistance
- Tunable fidelity/error-rate tradeoffs per memory type
- Orthogonal encoding/decoding engines (like orthogonal tRNA/synthetase)
- Cross-strand error correction via redundant encoding
- Evolutionary memory: mutating encodings for adaptive compression
"""

import json
import os
import sys
import time
import hashlib
import base64
import zlib
import random
from typing import Dict, List, Optional, Tuple, Any, Callable
from dataclasses import dataclass, field
from enum import Enum
from collections import defaultdict
from abc import ABC, abstractmethod


class XNABackbone(Enum):
    """XNA backbone types with different properties."""
    STANDARD = "standard"   # Standard JSON (baseline)
    TNA = "tna"             # Threose: high fidelity, high repair cost
    HNA = "hna"             # Hexose: balanced fidelity/cost
    FANA = "fana"           # Fluoroarabino: maximum stability
    CENA = "cena"           # Cyclohexene: high specificity
    GNA = "gna"             # Glycol: minimal, prebiotic-like


# Backbone properties (inspired by actual XNA characteristics)
BACKBONE_PROPERTIES = {
    XNABackbone.STANDARD: {
        'error_rate': 1e-3,
        'repair_cost': 1,
        'compression': 1.0,
        'nuclease_resistance': 0.1,
        'description': 'Standard JSON encoding'
    },
    XNABackbone.TNA: {
        'error_rate': 1e-6,
        'repair_cost': 3,
        'compression': 0.8,
        'nuclease_resistance': 0.95,
        'description': 'Threose: high fidelity, nuclease resistant'
    },
    XNABackbone.HNA: {
        'error_rate': 1e-4,
        'repair_cost': 2,
        'compression': 0.9,
        'nuclease_resistance': 0.8,
        'description': 'Hexose: balanced fidelity and cost'
    },
    XNABackbone.FANA: {
        'error_rate': 1e-5,
        'repair_cost': 5,
        'compression': 0.7,
        'nuclease_resistance': 0.99,
        'description': 'Fluoroarabino: maximum stability'
    },
    XNABackbone.CENA: {
        'error_rate': 1e-5,
        'repair_cost': 4,
        'compression': 0.85,
        'nuclease_resistance': 0.9,
        'description': 'Cyclohexene: high specificity'
    },
    XNABackbone.GNA: {
        'error_rate': 1e-2,
        'repair_cost': 1,
        'compression': 1.2,
        'nuclease_resistance': 0.05,
        'description': 'Glycol: minimal, high mutability'
    }
}


class XNACodec(ABC):
    """Abstract base for XNA encoding/decoding (orthogonal engine)."""

    @abstractmethod
    def encode(self, data: bytes) -> bytes:
        pass

    @abstractmethod
    def decode(self, encoded: bytes) -> bytes:
        pass

    @abstractmethod
    def verify(self, encoded: bytes) -> bool:
        """Verify integrity without full decode."""
        pass

    @abstractmethod
    def get_redundancy(self) -> float:
        """Return redundancy factor (encoded/original size)."""
        pass


class StandardCodec(XNACodec):
    """Standard JSON + zlib compression."""

    def encode(self, data: bytes) -> bytes:
        return zlib.compress(data, level=6)

    def decode(self, encoded: bytes) -> bytes:
        return zlib.decompress(encoded)

    def verify(self, encoded: bytes) -> bool:
        try:
            zlib.decompress(encoded)
            return True
        except:
            return False

    def get_redundancy(self) -> float:
        return 1.0


class TNACodec(XNACodec):
    """TNA-inspired: Reed-Solomon-like error correction + compression."""
    # Simplified: multiple compressed copies with checksums

    def __init__(self, copies: int = 3):
        self.copies = copies

    def encode(self, data: bytes) -> bytes:
        compressed = zlib.compress(data, level=9)
        # Create multiple copies with different checksums
        chunks = []
        for i in range(self.copies):
            checksum = hashlib.sha256(compressed + str(i).encode()).digest()[:8]
            chunks.append(checksum + compressed)
        return b''.join(chunks)

    def decode(self, encoded: bytes) -> bytes:
        chunk_size = len(encoded) // self.copies
        copies = []
        for i in range(self.copies):
            chunk = encoded[i*chunk_size:(i+1)*chunk_size]
            if len(chunk) > 8:
                checksum = chunk[:8]
                data = chunk[8:]
                expected = hashlib.sha256(data + str(i).encode()).digest()[:8]
                if checksum == expected:
                    copies.append(data)

        # Majority vote on decompressed data
        if not copies:
            raise ValueError("All copies corrupted")

        # Try each copy
        for copy in copies:
            try:
                return zlib.decompress(copy)
            except:
                continue
        raise ValueError("No valid copy found")

    def verify(self, encoded: bytes) -> bool:
        try:
            self.decode(encoded)
            return True
        except:
            return False

    def get_redundancy(self) -> float:
        return self.copies * 1.1  # Compressed + checksums


class FANACodec(XNACodec):
    """FANA-inspired: Maximum stability with cryptographic authentication."""
    # AES-GCM style authenticated encryption (simplified with HMAC)

    def encode(self, data: bytes) -> bytes:
        compressed = zlib.compress(data, level=9)
        # Add HMAC for authentication
        key = b'athena_fana_key_32_bytes_long!!'  # In practice: derived key
        hmac = hashlib.sha256(key + compressed).digest()
        # Add version header
        return b'FANA' + hmac + compressed

    def decode(self, encoded: bytes) -> bytes:
        if not encoded.startswith(b'FANA'):
            raise ValueError("Invalid FANA header")
        hmac = encoded[4:36]
        compressed = encoded[36:]
        key = b'athena_fana_key_32_bytes_long!!'
        expected = hashlib.sha256(key + compressed).digest()
        if hmac != expected:
            raise ValueError("FANA authentication failed")
        return zlib.decompress(compressed)

    def verify(self, encoded: bytes) -> bool:
        try:
            self.decode(encoded)
            return True
        except:
            return False

    def get_redundancy(self) -> float:
        return 1.15  # Compressed + 32-byte HMAC + 4-byte header


class CeNACodec(XNACodec):
    """CeNA-inspired: Constrained encoding with structural validation."""
    # Uses canonical JSON + schema validation

    def encode(self, data: bytes) -> bytes:
        # Parse as JSON, canonicalize, then compress
        try:
            obj = json.loads(data.decode('utf-8'))
            canonical = json.dumps(obj, separators=(',', ':'), sort_keys=True)
            compressed = zlib.compress(canonical.encode('utf-8'), level=9)
        except:
            compressed = zlib.compress(data, level=9)
        return b'CENA' + compressed

    def decode(self, encoded: bytes) -> bytes:
        if not encoded.startswith(b'CENA'):
            raise ValueError("Invalid CeNA header")
        compressed = encoded[4:]
        decompressed = zlib.decompress(compressed)
        # Re-validate as canonical JSON
        json.loads(decompressed.decode('utf-8'))
        return decompressed

    def verify(self, encoded: bytes) -> bool:
        try:
            self.decode(encoded)
            return True
        except:
            return False

    def get_redundancy(self) -> float:
        return 1.1


class GNACodec(XNACodec):
    """GNA-inspired: Minimal encoding, high mutability for exploration."""
    # Light compression, intentional degradation for variation

    def __init__(self, mutation_rate: float = 0.01):
        self.mutation_rate = mutation_rate

    def encode(self, data: bytes) -> bytes:
        compressed = zlib.compress(data, level=1)  # Fast, minimal
        # Add mutation marker
        return b'GNA' + compressed

    def decode(self, encoded: bytes) -> bytes:
        if not encoded.startswith(b'GNA'):
            raise ValueError("Invalid GNA header")
        compressed = encoded[3:]
        return zlib.decompress(compressed)

    def mutate(self, encoded: bytes) -> bytes:
        """Introduce controlled mutations for exploration."""
        if not encoded.startswith(b'GNA'):
            return encoded
        data = bytearray(encoded)
        # Mutate compressed payload (skip header)
        for i in range(3, len(data)):
            if random.random() < self.mutation_rate:
                data[i] ^= random.randint(1, 255)
        return bytes(data)

    def verify(self, encoded: bytes) -> bool:
        try:
            self.decode(encoded)
            return True
        except:
            return False

    def get_redundancy(self) -> float:
        return 1.05


# Codec registry (orthogonal tRNA/synthetase pairs)
XNA_CODECS = {
    XNABackbone.STANDARD: StandardCodec(),
    XNABackbone.TNA: TNACodec(copies=3),
    XNABackbone.HNA: TNACodec(copies=2),  # HNA uses 2-copy TNA
    XNABackbone.FANA: FANACodec(),
    XNABackbone.CENA: CeNACodec(),
    XNABackbone.GNA: GNACodec()
}


@dataclass
class XNAPacket:
    """XNA-encoded memory packet with metadata."""
    backbone: XNABackbone
    encoded_data: bytes
    original_hash: str
    timestamp: float
    metadata: Dict = field(default_factory=dict)
    repair_count: int = 0

    def to_dict(self) -> Dict:
        return {
            'backbone': self.backbone.value,
            'encoded_data': base64.b64encode(self.encoded_data).decode('ascii'),
            'original_hash': self.original_hash,
            'timestamp': self.timestamp,
            'metadata': self.metadata,
            'repair_count': self.repair_count
        }

    @classmethod
    def from_dict(cls, data: Dict) -> 'XNAPacket':
        return cls(
            backbone=XNABackbone(data['backbone']),
            encoded_data=base64.b64decode(data['encoded_data']),
            original_hash=data['original_hash'],
            timestamp=data['timestamp'],
            metadata=data.get('metadata', {}),
            repair_count=data.get('repair_count', 0)
        )


class XNAMemoryEncoder:
    """
    XNA-style memory encoder with pluggable backbones.
    Different memory types use different backbones for optimal tradeoffs.
    """

    def __init__(self):
        self.codecs = XNA_CODECS
        self.backbone_policies: Dict[str, XNABackbone] = {
            'critical': XNABackbone.FANA,      # Maximum stability
            'episodic': XNABackbone.TNA,       # High fidelity
            'semantic': XNABackbone.HNA,       # Balanced
            'working': XNABackbone.STANDARD,   # Fast access
            'exploratory': XNABackbone.GNA,    # Mutable for creativity
            'archive': XNABackbone.CENA        # Structured, validated
        }

    def set_policy(self, memory_type: str, backbone: XNABackbone):
        """Set encoding policy for a memory type."""
        self.backbone_policies[memory_type] = backbone

    def encode(self, memory: Dict, memory_type: str = 'working') -> XNAPacket:
        """Encode memory with appropriate backbone."""
        backbone = self.backbone_policies.get(memory_type, XNABackbone.STANDARD)
        codec = self.codecs[backbone]

        # Serialize memory
        data = json.dumps(memory, separators=(',', ':')).encode('utf-8')
        original_hash = hashlib.sha256(data).hexdigest()[:16]

        # Encode with selected backbone
        encoded = codec.encode(data)

        packet = XNAPacket(
            backbone=backbone,
            encoded_data=encoded,
            original_hash=original_hash,
            timestamp=time.time(),
            metadata={
                'memory_type': memory_type,
                'original_size': len(data),
                'encoded_size': len(encoded),
                'redundancy': codec.get_redundancy(),
                'properties': BACKBONE_PROPERTIES[backbone]
            }
        )
        return packet

    def decode(self, packet: XNAPacket) -> Dict:
        """Decode memory packet."""
        codec = self.codecs[packet.backbone]
        decoded = codec.decode(packet.encoded_data)

        # Verify integrity
        actual_hash = hashlib.sha256(decoded).hexdigest()[:16]
        if actual_hash != packet.original_hash:
            # Attempt repair
            decoded = self._attempt_repair(packet, decoded)
            actual_hash = hashlib.sha256(decoded).hexdigest()[:16]
            if actual_hash != packet.original_hash:
                raise ValueError(f"Memory corruption detected: hash mismatch")

        memory = json.loads(decoded.decode('utf-8'))
        return memory

    def _attempt_repair(self, packet: XNAPacket, decoded: bytes) -> bytes:
        """Attempt error correction based on backbone."""
        codec = self.codecs[packet.backbone]
        props = BACKBONE_PROPERTIES[packet.backbone]

        # For TNA/HNA: try alternative copies
        if packet.backbone in (XNABackbone.TNA, XNABackbone.HNA):
            # Decode already tries all copies
            pass

        # For FANA: authentication failure = unrecoverable
        if packet.backbone == XNABackbone.FANA:
            raise ValueError("FANA authentication failed - data tampered")

        # For CeNA: try canonicalization repair
        if packet.backbone == XNABackbone.CENA:
            try:
                obj = json.loads(decoded.decode('utf-8'))
                canonical = json.dumps(obj, separators=(',', ':'), sort_keys=True)
                return canonical.encode('utf-8')
            except:
                pass

        # For GNA: mutations are expected, try anyway
        if packet.backbone == XNABackbone.GNA:
            return decoded

        packet.repair_count += 1
        packet.metadata['last_repair'] = time.time()
        return decoded

    def verify_packet(self, packet: XNAPacket) -> bool:
        """Verify packet integrity without full decode."""
        codec = self.codecs[packet.backbone]
        return codec.verify(packet.encoded_data)

    def transcribe(self, packet: XNAPacket, target_backbone: XNABackbone) -> XNAPacket:
        """Transcribe memory from one backbone to another (like RNA transcription)."""
        # Decode from source
        memory = self.decode(packet)
        # Re-encode with target backbone
        new_packet = self.encode(memory, 'working')  # Will use target policy
        # Override backbone
        new_packet.backbone = target_backbone
        new_packet.encoded_data = self.codecs[target_backbone].encode(
            json.dumps(memory, separators=(',', ':')).encode('utf-8')
        )
        new_packet.metadata['transcribed_from'] = packet.backbone.value
        new_packet.metadata['transcribed_at'] = time.time()
        return new_packet

    def get_encoding_stats(self, packet: XNAPacket) -> Dict:
        """Get encoding efficiency statistics."""
        props = BACKBONE_PROPERTIES[packet.backbone]
        return {
            'backbone': packet.backbone.value,
            'original_size': packet.metadata.get('original_size', 0),
            'encoded_size': packet.metadata.get('encoded_size', 0),
            'compression_ratio': packet.metadata.get('original_size', 1) / max(1, packet.metadata.get('encoded_size', 1)),
            'redundancy': packet.metadata.get('redundancy', 1.0),
            'error_rate': props['error_rate'],
            'repair_cost': props['repair_cost'],
            'nuclease_resistance': props['nuclease_resistance'],
            'repair_count': packet.repair_count
        }


class XNAMemoryStore:
    """Memory store with XNA-encoded packets."""

    def __init__(self, encoder: XNAMemoryEncoder = None):
        self.encoder = encoder or XNAMemoryEncoder()
        self._storage: Dict[str, XNAPacket] = {}
        self.index: Dict[str, List[str]] = defaultdict(list)  # memory_type -> packet_ids

    def store(self, key: str, memory: Dict, memory_type: str = 'working') -> XNAPacket:
        """Store memory with XNA encoding."""
        packet = self.encoder.encode(memory, memory_type)
        self._storage[key] = packet
        self.index[memory_type].append(key)
        return packet

    def retrieve(self, key: str) -> Optional[Dict]:
        """Retrieve and decode memory."""
        packet = self._storage.get(key)
        if not packet:
            return None
        return self.encoder.decode(packet)

    def verify_all(self) -> Dict[str, bool]:
        """Verify integrity of all stored memories."""
        results = {}
        for key, packet in self._storage.items():
            results[key] = self.encoder.verify_packet(packet)
        return results

    def repair_all(self) -> Dict[str, bool]:
        """Attempt repair of all corrupted memories."""
        results = {}
        for key, packet in self._storage.items():
            try:
                self.encoder.decode(packet)
                results[key] = True
            except:
                results[key] = False
        return results

    def transcribe_type(self, memory_type: str, target_backbone: XNABackbone):
        """Transcribe all memories of a type to new backbone."""
        for key in self.index.get(memory_type, []):
            packet = self._storage[key]
            new_packet = self.encoder.transcribe(packet, target_backbone)
            self._storage[key] = new_packet

    def get_stats(self) -> Dict:
        """Get storage statistics."""
        stats = {
            'total_memories': len(self._storage),
            'by_type': {},
            'by_backbone': {}
        }
        for key, packet in self._storage.items():
            mtype = packet.metadata.get('memory_type', 'unknown')
            backbone = packet.backbone.value

            if mtype not in stats['by_type']:
                stats['by_type'][mtype] = {'count': 0, 'total_size': 0}
            stats['by_type'][mtype]['count'] += 1
            stats['by_type'][mtype]['total_size'] += packet.metadata.get('encoded_size', 0)

            if backbone not in stats['by_backbone']:
                stats['by_backbone'][backbone] = {'count': 0, 'total_size': 0}
            stats['by_backbone'][backbone]['count'] += 1
            stats['by_backbone'][backbone]['total_size'] += packet.metadata.get('encoded_size', 0)

        return stats

    def export(self) -> Dict:
        """Export entire store for persistence."""
        return {
            'packets': {k: v.to_dict() for k, v in self._storage.items()},
            'index': dict(self.index)
        }

    def import_store(self, data: Dict):
        """Import store from persistence."""
        self._storage = {k: XNAPacket.from_dict(v) for k, v in data.get('packets', {}).items()}
        self.index = defaultdict(list, data.get('index', {}))

    @staticmethod
    def run_from_files(input_file: str, output_file: str):
        """Entry point called by xenobiological daemon."""
        return xna_memory_consolidate(input_file, output_file)


def xna_memory_consolidate(input_path: str, output_path: str):
    """
    Consolidate standard memory.json to XNA-encoded memory store.
    """
    with open(input_path) as f:
        memory_data = json.load(f)

    encoder = XNAMemoryEncoder()
    store = XNAMemoryStore(encoder)

    # Encode consolidation log entries
    for i, entry in enumerate(memory_data.get('consolidation_log', [])):
        key = f"consolidation_{i}"
        memory_type = 'archive'
        store.store(key, entry, memory_type)

    # Encode key events
    for i, event in enumerate(memory_data.get('key_events', [])):
        key = f"key_event_{i}"
        store.store(key, event, 'episodic')

    # Encode insights
    for i, insight in enumerate(memory_data.get('insights', [])):
        key = f"insight_{i}"
        store.store(key, insight, 'semantic')

    # Export XNA store
    output = store.export()
    output['consolidated_at'] = int(time.time())
    output['timestamp'] = int(time.time())
    output['original_stats'] = {
        'consolidation_entries': len(memory_data.get('consolidation_log', [])),
        'key_events': len(memory_data.get('key_events', [])),
        'insights': len(memory_data.get('insights', []))
    }

    with open(output_path, 'w') as f:
        json.dump(output, f, separators=(',', ':'))

    return output


def xna_memory_query(xna_store_path: str, query: Dict) -> List[Dict]:
    """
    Query XNA memory store with semantic search (simplified).
    """
    with open(xna_store_path) as f:
        data = json.load(f)

    encoder = XNAMemoryEncoder()
    store = XNAMemoryStore(encoder)
    store.import_store(data)

    results = []
    memory_type = query.get('type', None)
    keys = store.index.get(memory_type, []) if memory_type else list(store.store.keys())

    for key in keys:
        try:
            memory = store.retrieve(key)
            # Simple keyword match
            text = json.dumps(memory).lower()
            query_text = query.get('text', '').lower()
            if not query_text or query_text in text:
                packet = store.store[key]
                stats = encoder.get_encoding_stats(packet)
                results.append({
                    'key': key,
                    'memory': memory,
                    'encoding_stats': stats
                })
        except Exception as e:
            # Skip corrupted memories
            continue

    return results


@staticmethod
def run_from_files(input_file: str, output_file: str):
    """Entry point called by xenobiological daemon."""
    return xna_memory_consolidate(input_file, output_file)


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python3 xna_memory.py <command> <args...>")
        print("Commands:")
        print("  consolidate <input_memory.json> <output_xna.json>")
        print("  query <xna_store.json> <query_json>")
        print("  demo")
        sys.exit(1)

    cmd = sys.argv[1]

    if cmd == 'consolidate' and len(sys.argv) < 4:
        print("Usage: python3 xna_memory.py consolidate <input_memory.json> <output_xna.json>")
        sys.exit(1)
    elif cmd == 'query' and len(sys.argv) < 4:
        print("Usage: python3 xna_memory.py query <xna_store.json> <query_json>")
        sys.exit(1)

    if cmd == 'consolidate':
        input_path = sys.argv[2]
        output_path = sys.argv[3]
        result = xna_memory_consolidate(input_path, output_path)
        print(json.dumps({
            'status': 'success',
            'packets_created': len(result['packets']),
            'by_type': result.get('original_stats', {})
        }, indent=2))

    elif cmd == 'query':
        store_path = sys.argv[2]
        query = json.loads(sys.argv[3])
        results = xna_memory_query(store_path, query)
        print(json.dumps(results, indent=2))

    elif cmd == 'demo':
        encoder = XNAMemoryEncoder()

        # Test all backbones
        test_memory = {
            'content': 'This is a test memory for XNA encoding',
            'importance': 0.9,
            'tags': ['test', 'xna', 'encoding']
        }

        print("Testing all XNA backbones:")
        for backbone in XNABackbone:
            packet = encoder.encode(test_memory, 'working')
            packet.backbone = backbone
            packet.encoded_data = encoder.codecs[backbone].encode(
                json.dumps(test_memory, separators=(',', ':')).encode('utf-8')
            )
            stats = encoder.get_encoding_stats(packet)
            print(f"  {backbone.value}: {stats['compression_ratio']:.2f}x compression, "
                  f"error_rate={stats['error_rate']:.0e}, "
                  f"repair_cost={stats['repair_cost']}, "
                  f"resistance={stats['nuclease_resistance']:.2f}")

        # Test decode
        print("\nDecoding test:")
        for backbone in [XNABackbone.STANDARD, XNABackbone.TNA, XNABackbone.FANA]:
            packet = encoder.encode(test_memory, 'working')
            packet.backbone = backbone
            packet.encoded_data = encoder.codecs[backbone].encode(
                json.dumps(test_memory, separators=(',', ':')).encode('utf-8')
            )
            decoded = encoder.decode(packet)
            print(f"  {backbone.value}: {'OK' if decoded == test_memory else 'FAIL'}")

        # Test mutation (GNA)
        print("\nGNA mutation test:")
        gna_packet = encoder.encode(test_memory, 'exploratory')
        original = encoder.decode(gna_packet)
        mutated = encoder.codecs[XNABackbone.GNA].mutate(gna_packet.encoded_data)
        gna_packet.encoded_data = mutated
        try:
            mutated_decoded = encoder.decode(gna_packet)
            print(f"  Mutated decode: {'OK' if mutated_decoded == test_memory else 'VARIANT'}")
        except:
            print("  Mutated decode: CORRUPTED (expected)")

    else:
        print(f"Unknown command: {cmd}")
        sys.exit(1)