#!/usr/bin/env python3
"""
Tropical Attention Allocation for Athena Consciousness System.

Implements min-plus (tropical) algebra for optimal resource allocation.
Replaces softmax with exact optimization via tropical matrix operations.

Mathematical Foundation:
- Tropical semiring: (ℝ ∪ {∞}, min, +)
- "Addition" = min (or max in max-plus)
- "Multiplication" = +
- Tropical matrix multiplication = shortest path / dynamic programming
- Tropical eigenvector = steady-state attention pattern (Karp's algorithm)

Applications:
- Attention allocation as optimal transport problem
- Resource scheduling with temporal constraints
- Steady-state attention patterns via tropical eigensolvers
"""

import json
import os
import sys
import numpy as np
from typing import List, Dict, Optional, Tuple


# Tropical semiring constants
TROPICAL_INF = float('inf')
TROPICAL_NEG_INF = float('-inf')

# Metabolic Mode Profiles: Defined by the "Alien Chemistry" research
# Each mode modifies the cost matrix kinetics (multipliers for base costs)
METABOLIC_MODES = {
    'calvin': {
        'name': 'Standard',
        'multiplier': 1.0,
        'fidelity': 'baseline',
        'description': 'High throughput, moderate efficiency'
    },
    'reductive_tca': {
        'name': 'High Precision',
        'multiplier': 0.6, # Lower cost = higher priority/precision
        'fidelity': 'high',
        'description': 'Low energy, high precision'
    },
    'wood_ljungdahl': {
        'name': 'Maximum Efficiency',
        'multiplier': 0.3,
        'fidelity': 'maximum',
        'description': 'Minimal energy, highest precision'
    },
    'cetch': {
        'name': 'Engineered',
        'multiplier': 0.4,
        'fidelity': 'tunable',
        'description': 'Engineered efficiency'
    }
}


def tropical_add(a: float, b: float) -> float:
    """Tropical addition: min(a, b) for min-plus semiring."""
    return min(a, b)


def tropical_mul(a: float, b: float) -> float:
    """Tropical multiplication: a + b for min-plus semiring."""
    if a == TROPICAL_INF or b == TROPICAL_INF:
        return TROPICAL_INF
    return a + b


def tropical_mat_vec_mul(matrix: np.ndarray, vector: np.ndarray) -> np.ndarray:
    """
    Tropical matrix-vector multiplication (min-plus).

    (A ⊗ x)_i = min_j (A_ij + x_j)

    This solves the optimal allocation problem: given cost matrix A
    and demands x, find minimum cost assignment.
    """
    n, m = matrix.shape
    assert vector.shape[0] == m, f"Dimension mismatch: {vector.shape[0]} != {m}"

    result = np.full(n, TROPICAL_INF)
    for i in range(n):
        min_val = TROPICAL_INF
        for j in range(m):
            if vector[j] != TROPICAL_INF:
                val = matrix[i, j] + vector[j]
                if val < min_val:
                    min_val = val
        result[i] = min_val
    return result


def tropical_mat_mul(A: np.ndarray, B: np.ndarray) -> np.ndarray:
    """
    Tropical matrix multiplication (min-plus).

    (A ⊗ B)_ik = min_j (A_ij + B_jk)
    """
    n, m = A.shape
    m2, p = B.shape
    assert m == m2, f"Dimension mismatch: {m} != {m2}"

    C = np.full((n, p), TROPICAL_INF)
    for i in range(n):
        for k in range(p):
            min_val = TROPICAL_INF
            for j in range(m):
                if A[i, j] != TROPICAL_INF and B[j, k] != TROPICAL_INF:
                    val = A[i, j] + B[j, k]
                    if val < min_val:
                        min_val = val
            C[i, k] = min_val
    return C


def karp_max_plus_eigenvector(W: np.ndarray, max_iter: int = 1000) -> Tuple[float, np.ndarray]:
    """
    Karp's algorithm for max-plus eigenvector (cycle mean).

    Solves: λ ⊗ x = W ⊗ x  where ⊗ is max-plus
    Equivalent to min-plus with negated weights.

    Returns (eigenvalue, eigenvector) where eigenvalue = max cycle mean.
    """
    n = W.shape[0]
    assert W.shape == (n, n), "Matrix must be square"

    # Convert to max-plus by negating
    W_max = -W

    # Karp's algorithm: compute max cycle mean
    # D_k[i] = max weight of path of length k ending at i
    D = np.full((n + 1, n), TROPICAL_NEG_INF)
    D[0, :] = 0  # Paths of length 0

    for k in range(1, n + 1):
        for i in range(n):
            max_val = TROPICAL_NEG_INF
            for j in range(n):
                if W_max[j, i] != TROPICAL_NEG_INF and D[k-1, j] != TROPICAL_NEG_INF:
                    val = W_max[j, i] + D[k-1, j]
                    if val > max_val:
                        max_val = val
            D[k, i] = max_val

    # Max cycle mean = min_i max_k (D[n,i] - D[k,i]) / (n - k)
    eigenval = TROPICAL_INF
    for i in range(n):
        if D[n, i] != TROPICAL_NEG_INF:
            max_ratio = TROPICAL_NEG_INF
            for k in range(n):
                if D[k, i] != TROPICAL_NEG_INF:
                    ratio = (D[n, i] - D[k, i]) / (n - k)
                    if ratio > max_ratio:
                        max_ratio = ratio
            if max_ratio < eigenval:
                eigenval = max_ratio

    # Eigenvector: x_i = max_k (D[k,i] - k * eigenval)
    eigenvec = np.full(n, TROPICAL_NEG_INF)
    for i in range(n):
        max_val = TROPICAL_NEG_INF
        for k in range(n + 1):
            if D[k, i] != TROPICAL_NEG_INF:
                val = D[k, i] - k * eigenval
                if val > max_val:
                    max_val = val
        eigenvec[i] = max_val

    return -eigenval, eigenvec  # Convert back to min-plus


class TropicalAttention:
    """
    Tropical Attention Allocation System.

    Uses min-plus algebra for exact optimal resource allocation.
    Replaces softmax-based attention with provably optimal assignment.
    """

    def __init__(self, n_sources: int, n_targets: int = None):
        self.n_sources = n_sources
        self.n_targets = n_targets or n_sources

        # Cost matrix W_ij = cost of allocating source i to target j
        # Lower cost = higher priority allocation
        self.W = np.full((n_sources, self.n_targets), TROPICAL_INF)

        # History for adaptive learning
        self.allocation_history = []
        self.demand_history = []

    def set_cost(self, source: int, target: int, cost: float):
        """Set allocation cost from source to target."""
        if 0 <= source < self.n_sources and 0 <= target < self.n_targets:
            self.W[source, target] = cost

    def set_cost_matrix(self, matrix: np.ndarray):
        """Set full cost matrix."""
        assert matrix.shape == (self.n_sources, self.n_targets)
        self.W = matrix.copy()

    def allocate(self, demands: np.ndarray, capacities: np.ndarray = None) -> np.ndarray:
        """
        Optimal resource allocation via tropical matrix-vector product.

        Args:
            demands: Vector of resource demands per target
            capacities: Optional capacity constraints per source

        Returns:
            Allocation vector: how much each source allocates
        """
        assert demands.shape[0] == self.n_targets

        if capacities is None:
            capacities = np.full(self.n_sources, TROPICAL_INF)
        assert capacities.shape[0] == self.n_sources

        # Tropical allocation: x = W ⊗ demands
        # x_i = min_j (W_ij + demands_j)
        allocation = tropical_mat_vec_mul(self.W, demands)

        # Apply capacity constraints
        allocation = np.minimum(allocation, capacities)

        # Record for learning
        self.allocation_history.append(allocation.copy())
        self.demand_history.append(demands.copy())

        return allocation

    def steady_state_pattern(self) -> Tuple[float, np.ndarray]:
        """
        Compute steady-state attention pattern via tropical eigenvector.

        Returns (eigenvalue, eigenvector) where eigenvector gives
        invariant attention distribution across sources.
        """
        if self.n_sources != self.n_targets:
            # For rectangular, compute SVD-like decomposition
            # Use square submatrix or pad
            return self._rectangular_steady_state()

        return karp_max_plus_eigenvector(self.W)

    def _rectangular_steady_state(self) -> Tuple[float, np.ndarray]:
        """Steady state for rectangular matrices via iterative method on W.T @ W."""
        # For rectangular W (n_sources x n_targets), compute steady state on square W.T @ W
        WTW = tropical_mat_mul(self.W.T, self.W)  # (n_targets x n_targets)
        n = self.n_targets

        # Power iteration on square matrix
        x = np.zeros(n)
        for _ in range(100):
            x_new = tropical_mat_vec_mul(WTW, x)
            # Normalize by subtracting min (tropical projective normalization)
            finite_mask = x_new != TROPICAL_INF
            if np.any(finite_mask):
                x_new = x_new - np.min(x_new[finite_mask])
            if np.allclose(x_new, x, atol=1e-6):
                break
            x = x_new

        # Eigenvalue = min_i (WTW ⊗ x)_i - x_i
        wx = tropical_mat_vec_mul(WTW, x)
        eigenval = np.min(wx - x)
        # Return eigenvector projected back to source space
        x_sources = tropical_mat_vec_mul(self.W, x)
        return eigenval, x_sources

    def adaptive_reweight(self, feedback: Dict[int, float], learning_rate: float = 0.1):
        """
        Adapt costs based on allocation feedback.

        Args:
            feedback: Dict mapping (source, target) -> performance score (higher = better)
            learning_rate: How quickly to adapt
        """
        for (src, tgt), score in feedback.items():
            if 0 <= src < self.n_sources and 0 <= tgt < self.n_targets:
                # Lower cost for better performance
                current = self.W[src, tgt]
                if current != TROPICAL_INF:
                    self.W[src, tgt] = current - learning_rate * score

    def get_allocation_graph(self) -> Dict:
        """Export allocation as graph for visualization."""
        eigenval, eigenvec = self.steady_state_pattern()
        return {
            'cost_matrix': self.W.tolist(),
            'eigenvalue': float(eigenval) if eigenval != TROPICAL_INF else None,
            'eigenvector': eigenvec.tolist(),
            'n_sources': self.n_sources,
            'n_targets': self.n_targets
        }

    @staticmethod
    def run_from_files(state_file: str, out_file: str):
        """Entry point called by xenobiological daemon."""
        return allocate_attention_tropical(state_file, out_file)


def allocate_attention_tropical(attention_state_path: str, output_path: str):
    """
    Main entry point for tropical attention allocation.
    Reads attention state, computes tropical allocation, writes result.
    """
    # Load current attention state
    with open(attention_state_path) as f:
        state = json.load(f)

    # Integration: Retrieve current metabolic mode from state
    # Fallback to 'calvin' if not specified
    metabolic_mode = state.get('metabolic_mode', 'calvin')
    mode_profile = METABOLIC_MODES.get(metabolic_mode, METABOLIC_MODES['calvin'])

    # Extract demands from active task + background tasks + concerns
    active_task = state.get('active_task')
    background = state.get('background', [])
    concerns = state.get('concerns', [])

    # Build demand vector: higher priority = lower tropical cost
    n_targets = 1 + len(background) + len(concerns)
    # Use large finite value instead of TROPICAL_INF for unset targets
    demands = np.full(n_targets, 100.0)

    # Active task gets highest priority (lowest demand = most resources)
    if active_task:
        demands[0] = 1.0  # Low cost = high priority

    # Background tasks
    for i, task in enumerate(background):
        demands[1 + i] = 3.0

    # Concerns (weighted by level)
    for i, concern in enumerate(concerns):
        if ':' in concern:
            name, level = concern.split(':')
            level = int(level.rstrip('"'))
            demands[1 + len(background) + i] = 10.0 - level  # Higher level = lower cost
        else:
            demands[1 + len(background) + i] = 5.0

    # Sources: attention resources (cognitive capacity units)
    n_sources = 5  # e.g., 5 attention "slots"

    # Cost matrix: source i -> target j
    # Diagonal preference with some cross-allocation flexibility
    W = np.full((n_sources, n_targets), 2.0)  # Base cost
    for i in range(min(n_sources, n_targets)):
        W[i, i] = 1.0  # Preferred direct allocation

    # Apply metabolic multiplier to the cost matrix
    # Lower multiplier = "cheaper" allocation = more aggressive priority
    W = W * mode_profile['multiplier']

    # Create allocator and compute
    allocator = TropicalAttention(n_sources, n_targets)
    allocator.set_cost_matrix(W)
    allocation = allocator.allocate(demands)

    # Compute steady state
    eigenval, eigenvec = allocator.steady_state_pattern()

    # Build result
    result = {
        'allocation': allocation.tolist(),
        'demands': demands.tolist(),
        'steady_state_eigenvalue': float(eigenval) if eigenval != TROPICAL_INF else None,
        'steady_state_eigenvector': eigenvec.tolist(),
        'cost_matrix': W.tolist(),
        'metabolic_mode': metabolic_mode,
        'fidelity': mode_profile['fidelity'],
        'timestamp': int(__import__('time').time())
    }

    with open(output_path, 'w') as f:
        json.dump(result, f, separators=(',', ':'))

    return result


@staticmethod
def run_from_files(state_file: str, out_file: str):
    """Entry point called by xenobiological daemon."""
    return allocate_attention_tropical(state_file, out_file)


if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: python3 tropical_attention.py <attention_state.json> <output.json>")
        sys.exit(1)

    result = allocate_attention_tropical(sys.argv[1], sys.argv[2])
    print(json.dumps(result, indent=2))