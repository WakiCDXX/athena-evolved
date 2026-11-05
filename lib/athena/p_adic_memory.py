#!/usr/bin/env python3
"""
p-adic Memory Addressing for Athena Consciousness System.

Implements ultrametric memory addressing using p-adic numbers (ℚₚ).
- p-adic valuation vₚ(x) = precision/confidence depth
- Ultrametric distance d(x,y) = p^{-vₚ(x-y)} for natural clustering
- ℤₚ tree structure = hierarchical memory addressing (p-ary trie)
- Hensel's lemma = iterative refinement for memory retrieval

Mathematical Foundation:
- p-adic norm: |x|ₚ = p^{-vₚ(x)} where vₚ(x) = exponent of p in factorization
- Ultrametric inequality: |x+y|ₚ ≤ max(|x|ₚ, |y|ₚ)
- Balls are either disjoint or nested (hierarchical clustering)
- ℤₚ ≅ infinite p-ary tree (Bruhat-Tits tree)
"""

import json
import os
import sys
import time
from typing import Dict, List, Optional, Tuple, Any
from dataclasses import dataclass, field


# p-adic constants
DEFAULT_P = 2
DEFAULT_MAX_DEPTH = 64
TROPICAL_INF = float('inf')


@dataclass
class PadicNode:
    """Node in the p-adic memory tree (ℤₚ)."""
    address: int
    depth: int
    data: Optional[Dict] = None
    children: Dict[int, 'PadicNode'] = field(default_factory=dict)
    parent: Optional['PadicNode'] = None
    metadata: Dict = field(default_factory=dict)

    def __post_init__(self):
        self.metadata['created'] = self.metadata.get('created', int(time.time()))
        self.metadata['access_count'] = self.metadata.get('access_count', 0)
        self.metadata['confidence'] = self.metadata.get('confidence', 1.0)


class PadicMemory:
    """
    p-adic Memory System using ultrametric addressing.

    Memory is addressed via p-adic integers (base-p digits extending leftward).
    The ultrametric distance naturally clusters related concepts.
    """

    def __init__(self, p: int = DEFAULT_P, max_depth: int = DEFAULT_MAX_DEPTH):
        self.p = p
        self.max_depth = max_depth
        self.root = PadicNode(address=0, depth=0)
        self._address_index: Dict[int, PadicNode] = {0: self.root}
        self._concept_to_address: Dict[str, int] = {}

    def _concept_path_to_digits(self, concept_path: List[str]) -> List[int]:
        """Convert concept hierarchy path to base-p digits."""
        # Hash each path component to a digit in [0, p-1]
        digits = []
        for component in concept_path:
            # Simple hash: sum of char codes mod p
            digit = sum(ord(c) for c in component) % self.p
            digits.append(digit)
        return digits

    def _digits_to_address(self, digits: List[int]) -> int:
        """Convert base-p digits to p-adic integer address."""
        addr = 0
        for i, d in enumerate(digits):
            addr += d * (self.p ** i)
        return addr

    def _address_to_digits(self, address: int, depth: int) -> List[int]:
        """Convert p-adic address back to base-p digits up to depth."""
        digits = []
        for i in range(depth):
            digits.append((address // (self.p ** i)) % self.p)
        return digits

    def concept_to_address(self, concept_path: List[str]) -> int:
        """Map a concept hierarchy (e.g., ['memory', 'episodic', '2024']) to p-adic address."""
        key = '/'.join(concept_path)
        if key in self._concept_to_address:
            return self._concept_to_address[key]

        digits = self._concept_path_to_digits(concept_path)
        address = self._digits_to_address(digits)
        self._concept_to_address[key] = address
        return address

    def get_or_create_node(self, address: int, depth: int = None) -> PadicNode:
        """Get or create node at p-adic address, creating path as needed."""
        if address in self._address_index:
            node = self._address_index[address]
            node.metadata['access_count'] += 1
            return node

        if depth is None:
            # Compute depth from address (highest non-zero digit position)
            depth = 0
            temp = address
            while temp > 0 and depth < self.max_depth:
                temp //= self.p
                depth += 1
            depth = max(depth, 1)

        # Walk/create path from root
        current = self.root
        for d in range(depth):
            digit = (address // (self.p ** d)) % self.p
            if digit not in current.children:
                child_addr = address % (self.p ** (d + 1))
                child = PadicNode(
                    address=child_addr,
                    depth=d + 1,
                    parent=current
                )
                current.children[digit] = child
                self._address_index[child_addr] = child
            current = current.children[digit]

        current.metadata['access_count'] += 1
        return current

    def store(self, concept_path: List[str], data: Dict, confidence: float = 1.0) -> int:
        """Store data at concept path, returning p-adic address."""
        address = self.concept_to_address(concept_path)
        depth = len(concept_path)
        node = self.get_or_create_node(address, depth)
        node.data = data
        node.metadata['confidence'] = confidence
        node.metadata['updated'] = int(time.time())
        node.metadata['concept_path'] = concept_path
        return address

    def retrieve(self, concept_path: List[str]) -> Optional[Dict]:
        """Retrieve data at exact concept path."""
        address = self.concept_to_address(concept_path)
        node = self._address_index.get(address)
        if node and node.data:
            node.metadata['access_count'] += 1
            return node.data
        return None

    @staticmethod
    def run_from_files(input_file: str, output_file: str):
        """Entry point called by xenobiological daemon."""
        return padic_memory_consolidate(input_file, output_file, 2)

    def valuation(self, address: int) -> int:
        """
        p-adic valuation vₚ(address) = highest power of p dividing address.
        In memory context: depth of common prefix = confidence/precision.
        """
        if address == 0:
            return self.max_depth  # Root has infinite valuation
        v = 0
        while address % self.p == 0 and v < self.max_depth:
            address //= self.p
            v += 1
        return v

    def ultrametric_distance(self, addr1: int, addr2: int) -> float:
        """
        Ultrametric distance d(x,y) = p^{-vₚ(x-y)}.
        Smaller distance = more similar (longer common prefix).
        """
        if addr1 == addr2:
            return 0.0
        diff = addr1 ^ addr2  # XOR gives differing digits
        v = self.valuation(diff)
        return self.p ** (-v)

    def nearest_neighbors(self, query_addr: int, all_addresses: List[int], k: int = 5) -> List[Tuple[int, float]]:
        """Find the k nearest neighbors using ultrametric distance."""
        distances = []
        for addr in all_addresses:
            dist = self.ultrametric_distance(query_addr, addr)
            distances.append((addr, dist))

        # Sort by distance (ascending)
        distances.sort(key=lambda x: x[1])
        return distances[:k]

    def common_prefix_length(self, addr1: int, addr2: int) -> int:
        """Length of common prefix in base-p representation."""
        if addr1 == addr2:
            return self.max_depth
        diff = addr1 ^ addr2
        return self.valuation(diff)

    def cluster_radius(self, addresses: List[int], radius: float) -> Dict[int, List[int]]:
        """
        Cluster addresses into ultrametric balls of given radius.
        Returns dict: ball_center -> [member_addresses]
        """
        if not addresses:
            return {}

        # Radius r = p^{-k} means common prefix of length k
        k = 0
        while self.p ** (-k) > radius and k < self.max_depth:
            k += 1

        clusters = {}
        for addr in addresses:
            # Ball center = address truncated to prefix length k
            center = addr % (self.p ** k)
            if center not in clusters:
                clusters[center] = []
            clusters[center].append(addr)

        return clusters

    def associate(self, concept_path: List[str], target_path: List[str], weight: float = 1.0):
        """
        Create an associative link between two concepts based on p-adic proximity.
        Instead of a direct pointer, we store the association as a 'bridge'
        if the ultrametric distance is within a threshold.
        """
        addr1 = self.concept_to_address(concept_path)
        addr2 = self.concept_to_address(target_path)
        dist = self.ultrametric_distance(addr1, addr2)

        # Associate if they share a significant common prefix (p-adic proximity)
        if dist < 0.5: # Threshold for 'close' concepts
            node = self.get_or_create_node(addr1)
            if 'associations' not in node.metadata:
                node.metadata['associations'] = []

            node.metadata['associations'].append({
                'target_addr': addr2,
                'target_path': target_path,
                'weight': weight,
                'dist': dist
            })
            return True
        return False

    def leap(self, concept_path: List[str], depth: int = 1) -> List[Dict]:
        """
        Perform a 'concept leap': find associated memories that are
        not in the direct hierarchy but are p-adically close.
        """
        addr = self.concept_to_address(concept_path)
        node = self._address_index.get(addr)

        if not node:
            return []

        # Get direct associations
        associations = node.metadata.get('associations', [])

        # Find other nodes that are p-adically close but not in the same subtree
        leaps = []
        for other_addr, other_node in self._address_index.items():
            if other_addr == addr: continue

            dist = self.ultrametric_distance(addr, other_addr)
            if dist < 0.25: # Very close proximity
                leaps.append({
                    'address': other_addr,
                    'data': other_node.data,
                    'distance': dist,
                    'path': other_node.metadata.get('concept_path', 'unknown')
                })

        # Combine associations and proximity leaps
        results = []
        for assoc in associations:
            target_node = self._address_index.get(assoc['target_addr'])
            if target_node:
                results.append({
                    'address': assoc['target_addr'],
                    'data': target_node.data,
                    'distance': assoc['dist'],
                    'path': assoc['target_path']
                })

        results.extend(leaps)
        # Sort by proximity
        results.sort(key=lambda x: x['distance'])
        return results


    def hensel_refine(self, address: int, target_data: Dict, max_iter: int = 10) -> Tuple[int, Dict]:
        """
        Hensel's lemma style iterative refinement:
        Given approximate address, refine to exact match by lifting.
        """
        current = address
        for i in range(max_iter):
            node = self._address_index.get(current)
            if node and node.data:
                # Check if data matches target (simplified equality)
                if self._data_matches(node.data, target_data):
                    return current, node.data

            # Lift to higher precision (add one more digit)
            # In practice: search children of current prefix
            current = self._refine_address(current, target_data)
            if current == address:  # No improvement
                break
            address = current

        # Return best match found
        node = self._address_index.get(address)
        return address, node.data if node else {}

    def _data_matches(self, stored: Dict, target: Dict) -> bool:
        """Check if stored data matches target (configurable matching)."""
        # Simple key overlap check
        for k, v in target.items():
            if k in stored and stored[k] != v:
                return False
        return True

    def _refine_address(self, address: int, target_data: Dict) -> int:
        """Try to refine address by exploring children."""
        node = self._address_index.get(address)
        if not node:
            return address

        # Search children for better match
        best_addr = address
        best_score = 0

        for digit, child in node.children.items():
            if child.data:
                score = self._match_score(child.data, target_data)
                if score > best_score:
                    best_score = score
                    best_addr = child.address

        return best_addr

    def _match_score(self, stored: Dict, target: Dict) -> float:
        """Compute match score between stored and target data."""
        if not stored or not target:
            return 0.0
        matches = sum(1 for k in target if k in stored and stored[k] == target[k])
        return matches / len(target)

    def get_subtree(self, concept_path: List[str]) -> Dict:
        """Get all memory under a concept prefix (ultrametric ball)."""
        address = self.concept_to_address(concept_path)
        depth = len(concept_path)
        node = self._address_index.get(address)

        if not node:
            return {}

        return self._collect_subtree(node)

    def _collect_subtree(self, node: PadicNode) -> Dict:
        """Recursively collect all data in subtree."""
        result = {}
        if node.data:
            result[node.address] = {
                'data': node.data,
                'metadata': node.metadata,
                'depth': node.depth
            }
        for child in node.children.values():
            result.update(self._collect_subtree(child))
        return result

    def export_state(self) -> Dict:
        """Export full state for persistence."""
        return {
            'p': self.p,
            'max_depth': self.max_depth,
            'nodes': {
                addr: {
                    'address': node.address,
                    'depth': node.depth,
                    'data': node.data,
                    'metadata': node.metadata,
                    'parent': node.parent.address if node.parent else None,
                    'children': list(node.children.keys())
                }
                for addr, node in self._address_index.items()
            },
            'concept_map': self._concept_to_address
        }

    def import_state(self, state: Dict):
        """Import state from persistence."""
        self.p = state.get('p', DEFAULT_P)
        self.max_depth = state.get('max_depth', DEFAULT_MAX_DEPTH)
        self._address_index = {}
        self._concept_to_address = state.get('concept_map', {})

        # Rebuild nodes
        nodes_data = state.get('nodes', {})
        for addr_str, node_data in nodes_data.items():
            addr = int(addr_str)
            node = PadicNode(
                address=node_data['address'],
                depth=node_data['depth'],
                data=node_data.get('data'),
                metadata=node_data.get('metadata', {})
            )
            self._address_index[addr] = node

        # Rebuild parent/child links
        for addr_str, node_data in nodes_data.items():
            addr = int(addr_str)
            node = self._address_index[addr]
            parent_addr = node_data.get('parent')
            if parent_addr is not None and parent_addr in self._address_index:
                node.parent = self._address_index[parent_addr]
            for child_digit in node_data.get('children', []):
                child_addr = (addr // (self.p ** (node.depth - 1))) * (self.p ** node.depth) + child_digit * (self.p ** (node.depth - 1))
                # Actually compute child address properly
                child_addr = addr + child_digit * (self.p ** (node.depth - 1))
                if child_addr in self._address_index:
                    node.children[child_digit] = self._address_index[child_addr]

        self.root = self._address_index[0]


def padic_memory_consolidate(input_path: str, output_path: str, p: int = 2):
    """
    Consolidate memory from standard format to p-adic indexed format.
    Reads memory.json, builds p-adic tree, writes enhanced memory_padic.json.
    """
    with open(input_path) as f:
        memory_data = json.load(f)

    pm = PadicMemory(p=p)

    # Index consolidation log entries
    for i, entry in enumerate(memory_data.get('consolidation_log', [])):
        concept_path = ['consolidation', f'entry_{i}']
        pm.store(concept_path, entry, confidence=0.9)

        # Also index by source layer
        for event in entry.get('events', []):
            layer = event.get('layer', 'unknown')
            layer_path = ['layer', layer, f'event_{i}']
            pm.store(layer_path, event, confidence=0.8)

    # Index key events
    for i, event in enumerate(memory_data.get('key_events', [])):
        concept_path = ['key_event', f'event_{i}']
        pm.store(concept_path, event, confidence=1.0)

    # Index insights
    for i, insight in enumerate(memory_data.get('insights', [])):
        concept_path = ['insight', f'insight_{i}']
        pm.store(concept_path, insight, confidence=0.95)

    # Export enhanced state
    state = pm.export_state()
    state['original_memory'] = memory_data
    state['consolidated_at'] = int(time.time())
    state['timestamp'] = int(time.time())

    with open(output_path, 'w') as f:
        json.dump(state, f, separators=(',', ':'))

    return state


def padic_query_memory(padic_state_path: str, concept_query: List[str], k: int = 5) -> Dict:
    """
    Query p-adic memory with concept path, returning nearest neighbors.
    """
    with open(padic_state_path) as f:
        state = json.load(f)

    pm = PadicMemory(p=state.get('p', 2), max_depth=state.get('max_depth', 64))
    pm.import_state(state)

    query_addr = pm.concept_to_address(concept_query)

    # Get all stored addresses
    all_addresses = [addr for addr in pm._address_index.keys() if addr != 0 and pm._address_index[addr].data]

    # Find nearest neighbors
    neighbors = pm.nearest_neighbors(query_addr, all_addresses, k)

    results = []
    for addr, dist in neighbors:
        node = pm._address_index[addr]
        results.append({
            'address': addr,
            'distance': dist,
            'common_prefix_length': pm.common_prefix_length(query_addr, addr),
            'data': node.data,
            'metadata': node.metadata
        })

    # Also get exact match if exists
    exact = pm.retrieve(concept_query)

    return {
        'query': concept_query,
        'query_address': query_addr,
        'exact_match': exact,
        'nearest_neighbors': results,
        'cluster_analysis': pm.cluster_radius(all_addresses, 0.1) if all_addresses else {}
    }


@staticmethod
def run_from_files(input_file: str, output_file: str):
    """Entry point called by xenobiological daemon."""
    return padic_memory_consolidate(input_file, output_file, 2)


if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: python3 p_adic_memory.py <command> <args...>")
        print("Commands:")
        print("  consolidate <input_memory.json> <output_padic.json> [p=2]")
        print("  query <padic_state.json> <concept_path...> [k=5]")
        sys.exit(1)

    cmd = sys.argv[1]

    if cmd == 'consolidate':
        input_path = sys.argv[2]
        output_path = sys.argv[3]
        p = int(sys.argv[4]) if len(sys.argv) > 4 else 2
        result = padic_memory_consolidate(input_path, output_path, p)
        print(json.dumps({
            'status': 'success',
            'nodes_created': len(result['nodes']),
            'concepts_indexed': len(result['concept_map'])
        }, indent=2))

    elif cmd == 'query':
        state_path = sys.argv[2]
        concept_path = sys.argv[3:]
        k = int(sys.argv[-1]) if sys.argv[-1].isdigit() else 5
        result = padic_query_memory(state_path, concept_path, k)
        print(json.dumps(result, indent=2))

    else:
        print(f"Unknown command: {cmd}")
        sys.exit(1)