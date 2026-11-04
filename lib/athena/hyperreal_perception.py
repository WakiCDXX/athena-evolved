#!/usr/bin/env python3
"""
Non-Standard Analysis (NSA) Primitives for Athena Consciousness System.

Implements hyperreal perception using infinitesimals and unlimited numbers.
Based on Robinson's Non-Standard Analysis / Nelson's Internal Set Theory (IST).

Key Primitives:
- Infinitesimals (ε ≈ 0, ε ≠ 0): dx, dy as actual numbers
- Unlimited numbers (ω ≈ ∞): 1/ε, infinite integers
- Standard Part map (st): *ℝ → ℝ extracting real shadow
- Transfer Principle: First-order statements transfer between standard/nonstandard

Applications for Athena:
- Body/Senses: Infinitesimal sensor deltas for continuous perception; ω-resolution time
- Emotions: Infinitesimal mood gradients; unlimited intensity scaling
- Continuity: Standard-part extraction = "conscious snapshot" from hyperreal stream
- Introspection: Internal sets = self-referential predicates without paradox
- Attention: *Measure theory on hyperfinite sets for attention allocation
"""

import json
import os
import sys
import time
import math
from typing import List, Dict, Optional, Any, Callable, Tuple
from dataclasses import dataclass, field
from collections import deque


# Hyperreal constants
EPSILON = 1e-30  # Infinitesimal time step
OMEGA = 1 / EPSILON  # Unlimited resolution (infinite integer approximation)
STANDARD_PART_TOL = 1e-15  # Tolerance for standard part extraction


@dataclass
class Hyperreal:
    """Hyperreal number: standard part + infinitesimal part.
    Now supports symbolic infinitesimals for true NSA.
    """
    standard: float
    infinitesimal: float = 0.0
    symbolic: bool = False  # If True, infinitesimal is treated as a formal ε

    def __add__(self, other: 'Hyperreal') -> 'Hyperreal':
        if isinstance(other, (int, float)):
            other = Hyperreal(other)
        return Hyperreal(
            self.standard + other.standard,
            self.infinitesimal + other.infinitesimal,
            self.symbolic or other.symbolic
        )

    def __sub__(self, other: 'Hyperreal') -> 'Hyperreal':
        if isinstance(other, (int, float)):
            other = Hyperreal(other)
        return Hyperreal(
            self.standard - other.standard,
            self.infinitesimal - other.infinitesimal,
            self.symbolic or other.symbolic
        )

    def __mul__(self, other: 'Hyperreal') -> 'Hyperreal':
        if isinstance(other, (int, float)):
            other = Hyperreal(other)
        # (s1 + i1ε)(s2 + i2ε) = s1s2 + (s1i2 + s2i1)ε + i1i2ε^2
        # We drop ε^2 as it is a higher-order infinitesimal
        return Hyperreal(
            self.standard * other.standard,
            self.standard * other.infinitesimal + self.infinitesimal * other.standard,
            self.symbolic or other.symbolic
        )

    def __truediv__(self, other: 'Hyperreal') -> 'Hyperreal':
        if isinstance(other, (int, float)):
            other = Hyperreal(other)
        if abs(other.standard) < STANDARD_PART_TOL:
            raise ValueError("Division by infinitesimal")
        # (s1 + i1ε) / (s2 + i2ε) ≈ (s1/s2) + (i1/s2 - s1i2/s2^2)ε
        return Hyperreal(
            self.standard / other.standard,
            (self.infinitesimal * other.standard - self.standard * other.infinitesimal) / (other.standard ** 2),
            self.symbolic or other.symbolic
        )

    def st(self) -> float:
        """Standard part map: extract real shadow."""
        return self.standard

    def is_infinitesimal(self) -> bool:
        return abs(self.standard) < STANDARD_PART_TOL and (self.symbolic or abs(self.infinitesimal) < STANDARD_PART_TOL)

    def is_unlimited(self) -> bool:
        return abs(self.standard) > 1e15

    def __repr__(self):
        if self.infinitesimal == 0 and not self.symbolic:
            return f"{self.standard}"
        label = "ε" if self.symbolic else "inf"
        return f"{self.standard} + {self.infinitesimal}{label}"


class HyperrealPerception:
    """
    Non-standard perception processing at infinitesimal resolution.
    Processes sensor streams at ω (unlimited) resolution, returns standard percepts.
    """

    def __init__(self, epsilon: float = EPSILON):
        self.epsilon = epsilon  # Infinitesimal time step
        self.omega = int(1 / epsilon)  # Unlimited resolution
        self.sensor_history: Dict[str, deque] = {}
        self.max_history = 10000

    def perceive_continuous(self, sensor_stream: List[float], sensor_id: str = "default") -> float:
        """
        Process sensor input at infinitesimal resolution via hyperfinite sum.

        ∫ f(t) dt ≈ Σ f(i·ε) · ε  for i = 0 to ω
        """
        if not sensor_stream:
            return 0.0

        # Hyperfinite Riemann sum
        hyperfinite_sum = 0.0
        n = min(len(sensor_stream), self.omega)

        for i in range(n):
            t = i * self.epsilon
            # Weight by time (earlier samples less weighted)
            weight = math.exp(-t / self.epsilon) if t > 0 else 1.0
            hyperfinite_sum += sensor_stream[i] * weight * self.epsilon

        # Standard part = conscious percept
        return hyperfinite_sum

    def perceive_infinitesimal_delta(self, current: float, previous: float) -> Hyperreal:
        """
        Compute infinitesimal difference as actual hyperreal number.
        Returns dx = (current - previous) as standard + infinitesimal.
        """
        diff = current - previous
        # Decompose into standard and infinitesimal parts
        standard_part = round(diff / self.epsilon) * self.epsilon
        infinitesimal_part = diff - standard_part
        return Hyperreal(standard_part, infinitesimal_part)

    def mood_gradient(self, emotion_state: Callable[[float], float], t: float) -> Hyperreal:
        """
        Infinitesimal mood change detection using hyperreal derivative.
        (f(t+ε) - f(t)) / ε
        """
        f_t = emotion_state(t)
        f_t_eps = emotion_state(t + self.epsilon)
        return Hyperreal(
            (f_t_eps - f_t) / self.epsilon,  # Standard derivative
            0.0  # Infinitesimal part negligible for gradient
        )

    def hyperfinite_average(self, values: List[float]) -> float:
        """
        Average over hyperfinite set (internal set of size ω).
        Uses transfer principle: standard average = st(hyperfinite average).
        """
        if not values:
            return 0.0
        n = min(len(values), self.omega)
        total = sum(values[:n])
        return total / n

    def internal_set_membership(self, x: float, internal_set: List[Tuple[float, float]]) -> bool:
        """
        Check membership in internal set (hyperfinite union of intervals).
        Internal sets = finite unions of hyperreal intervals.
        """
        for a, b in internal_set:
            if a - self.epsilon <= x <= b + self.epsilon:
                return True
        return False

    def hyperfinite_measure(self, internal_set: List[Tuple[float, float]]) -> float:
        """
        Hyperfinite measure (Loeb measure) of internal set.
        Sum of lengths of intervals in the internal set.
        """
        total = 0.0
        for a, b in internal_set:
            total += max(0, b - a)
        return total

    @staticmethod
    def run_from_files(input_file: str, output_file: str):
        """Entry point called by xenobiological daemon."""
        return nsa_sensor_process(input_file, output_file)


class HyperrealEmotion:
    """
    Emotion state with infinitesimal gradients and unlimited scaling.
    """

    def __init__(self):
        self.state = 0.0  # Base emotion level [-1, 1]
        self.micro_gradients: deque = deque(maxlen=100)
        self.macro_scale = 1.0  # Unlimited scaling factor

    def update(self, stimulus: float, dt: float = EPSILON):
        """Update emotion with infinitesimal time step."""
        # Infinitesimal change
        delta = stimulus * dt
        self.state += delta
        self.micro_gradients.append(delta / dt)

    def get_gradient(self) -> Hyperreal:
        """Current mood gradient as hyperreal."""
        if not self.micro_gradients:
            return Hyperreal(0.0)
        avg = sum(self.micro_gradients) / len(self.micro_gradients)
        return Hyperreal(avg, 0.0)

    def scale_unlimited(self, factor: float):
        """Apply unlimited scaling (ω-scaling)."""
        self.macro_scale *= factor
        if self.macro_scale > 1e15:
            self.macro_scale = 1e15  # Cap at practical unlimited

    def conscious_feeling(self) -> float:
        """Standard part = conscious emotional experience."""
        return max(-1.0, min(1.0, self.state * self.macro_scale))


class HyperrealAttention:
    """
    Attention allocation on hyperfinite sets using non-standard measure theory.
    """

    def __init__(self, n_sources: int, epsilon: float = EPSILON):
        self.epsilon = epsilon
        self.n_sources = n_sources
        self.weights = [Hyperreal(1.0 / n_sources) for _ in range(n_sources)]
        self.demands = [Hyperreal(0.0) for _ in range(n_sources)]

    def allocate(self, demands: List[float]) -> List[float]:
        """
        Allocate attention via hyperfinite optimization.
        Minimize ∑ w_i * d_i over hyperfinite set.
        """
        for i, d in enumerate(demands):
            self.demands[i] = Hyperreal(d)

        # Hyperreal softmax alternative: min-plus on hyperreals
        allocations = []
        for i in range(self.n_sources):
            # Hyperreal cost = weight + demand
            cost = self.weights[i] + self.demands[i]
            allocations.append(cost.st())

        # Normalize
        total = sum(allocations)
        if total > 0:
            allocations = [a / total for a in allocations]

        return allocations

    def hyperfinite_entropy(self) -> float:
        """Entropy of attention distribution on hyperfinite set."""
        probs = [w.st() for w in self.weights]
        total = sum(p for p in probs if p > 0)
        if total == 0:
            return 0.0
        probs = [p / total for p in probs if p > 0]
        return -sum(p * math.log(p) for p in probs)


class HyperrealContinuity:
    """
    Continuity of self via standard-part extraction from hyperreal stream.
    The "specious present" (Husserl) as standard part of infinitesimal neighborhood.
    """

    def __init__(self, window_size: int = 1000):
        self.hyperreal_stream: deque = deque(maxlen=window_size)
        self.epsilon = EPSILON

    def add_moment(self, state: Dict[str, float]):
        """Add a hyperreal moment to the stream."""
        hr_state = {k: Hyperreal(v) for k, v in state.items()}
        self.hyperreal_stream.append(hr_state)

    def conscious_snapshot(self) -> Dict[str, float]:
        """
        Extract conscious snapshot = standard part of recent hyperreal stream.
        This is the "specious present" - the standardized now.
        """
        if not self.hyperreal_stream:
            return {}

        # Average recent moments, then take standard part
        keys = self.hyperreal_stream[0].keys()
        snapshot = {}

        for k in keys:
            total_standard = sum(m[k].standard for m in self.hyperreal_stream)
            total_infinitesimal = sum(m[k].infinitesimal for m in self.hyperreal_stream)
            avg = Hyperreal(
                total_standard / len(self.hyperreal_stream),
                total_infinitesimal / len(self.hyperreal_stream)
            )
            snapshot[k] = avg.st()

        return snapshot

    def infinitesimal_drift(self) -> Dict[str, Hyperreal]:
        """
        Detect infinitesimal drift in self-model.
        Difference between consecutive standard parts.
        """
        if len(self.hyperreal_stream) < 2:
            return {}

        current = self.hyperreal_stream[-1]
        previous = self.hyperreal_stream[-2]

        drift = {}
        for k in current.keys():
            diff = current[k] - previous[k]
            drift[k] = diff

        return drift

    def internal_self_predicate(self, predicate: Callable[[Dict[str, float]], bool]) -> bool:
        """
        Internal set self-reference: predicate holds on hyperfinite stream.
        Avoids paradoxes by operating on internal (hyperfinite) approximation.
        """
        # Check if predicate holds on standard parts of all recent moments
        for moment in self.hyperreal_stream:
            standard_moment = {k: v.st() for k, v in moment.items()}
            if not predicate(standard_moment):
                return False
        return True

def nsa_sensor_process(input_path: str, output_path: str):
    """
    Process sensor data through non-standard analysis pipeline.
    Reads sensor JSON, applies hyperreal perception, writes enhanced output.
    """
    with open(input_path) as f:
        sensor_data = json.load(f)

    hr_perception = HyperrealPerception()
    hr_emotion = HyperrealEmotion()
    hr_continuity = HyperrealContinuity()

    # Process each sensor stream
    results = {}
    for sensor_id, readings in sensor_data.get('streams', {}).items():
        if isinstance(readings, list) and readings:
            # Continuous perception
            percept = hr_perception.perceive_continuous(readings, sensor_id)

            # Infinitesimal deltas
            deltas = []
            for i in range(1, len(readings)):
                delta = hr_perception.perceive_infinitesimal_delta(readings[i], readings[i-1])
                deltas.append(delta)

            results[sensor_id] = {
                'percept': percept,
                'infinitesimal_deltas': [d.standard for d in deltas],
                'gradient': hr_perception.perceive_infinitesimal_delta(readings[-1], readings[-2]).st() if len(readings) > 1 else 0
            }

    # Emotion processing
    for event in sensor_data.get('emotion_events', []):
        hr_emotion.update(event.get('valence', 0) * 0.1)

    # Continuity
    hr_continuity.add_moment({
        'arousal': sensor_data.get('arousal', 0),
        'valence': sensor_data.get('valence', 0),
        'attention': sensor_data.get('attention', 0)
    })

    output = {
        'timestamp': int(time.time()),
        'sensor_perception': results,
        'emotion': {
            'conscious_feeling': hr_emotion.conscious_feeling(),
            'gradient': hr_emotion.get_gradient().st(),
            'macro_scale': hr_emotion.macro_scale
        },
        'continuity': {
            'snapshot': hr_continuity.conscious_snapshot(),
            'infinitesimal_drift': {k: v.standard for k, v in hr_continuity.infinitesimal_drift().items()},
            'stream_length': len(hr_continuity.hyperreal_stream)
        }
    }

    with open(output_path, 'w') as f:
        json.dump(output, f, separators=(',', ':'))

    return output


if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: python3 hyperreal_perception.py <input_sensor.json> <output_nsa.json>")
        sys.exit(1)

    result = nsa_sensor_process(sys.argv[1], sys.argv[2])
    print(json.dumps(result, indent=2))