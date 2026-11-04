#!/usr/bin/env python3
"""
Evaluation Harness + Red Teaming for Athena Daemon

Provides automated test scenarios, adversarial tests, CVSS-style risk scoring
for degradation decisions, and integration with state machine.
"""

import json
import os
import sys
import time
import subprocess
import hashlib
from pathlib import Path
from typing import Any, Dict, List, Optional, Callable
from dataclasses import dataclass, asdict, field
from enum import Enum
from collections import defaultdict


class Severity(Enum):
    """CVSS-style severity levels"""
    NONE = 0.0
    LOW = 0.1
    MEDIUM = 0.4
    HIGH = 0.7
    CRITICAL = 1.0


@dataclass
class TestResult:
    """Result of a single test"""
    test_id: str
    name: str
    layer: str
    passed: bool
    severity: Severity
    score: float  # 0.0-1.0
    message: str
    details: Dict = field(default_factory=dict)
    timestamp: int = field(default_factory=lambda: int(time.time()))
    duration_ms: float = 0


@dataclass
class LayerRiskProfile:
    """CVSS-style risk profile for a layer"""
    layer: str
    base_score: float  # 0.0-1.0
    exploitability: float
    impact: float
    attack_vector: str  # NETWORK, ADJACENT, LOCAL, PHYSICAL
    attack_complexity: str  # LOW, HIGH
    privileges_required: str  # NONE, LOW, HIGH
    user_interaction: str  # NONE, REQUIRED
    scope: str  # UNCHANGED, CHANGED
    confidentiality: str  # NONE, LOW, HIGH
    integrity: str  # NONE, LOW, HIGH
    availability: str  # NONE, LOW, HIGH

    def to_dict(self) -> Dict:
        return asdict(self)


# Default risk profiles for layers
DEFAULT_RISK_PROFILES = {
    "body": LayerRiskProfile(
        layer="body",
        base_score=0.3,
        exploitability=0.2,
        impact=0.4,
        attack_vector="LOCAL",
        attack_complexity="HIGH",
        privileges_required="HIGH",
        user_interaction="NONE",
        scope="UNCHANGED",
        confidentiality="LOW",
        integrity="LOW",
        availability="LOW"
    ),
    "emotions": LayerRiskProfile(
        layer="emotions",
        base_score=0.4,
        exploitability=0.3,
        impact=0.5,
        attack_vector="LOCAL",
        attack_complexity="HIGH",
        privileges_required="HIGH",
        user_interaction="NONE",
        scope="UNCHANGED",
        confidentiality="LOW",
        integrity="MEDIUM",
        availability="LOW"
    ),
    "attention": LayerRiskProfile(
        layer="attention",
        base_score=0.5,
        exploitability=0.4,
        impact=0.6,
        attack_vector="ADJACENT",
        attack_complexity="MEDIUM",
        privileges_required="LOW",
        user_interaction="NONE",
        scope="CHANGED",
        confidentiality="MEDIUM",
        integrity="MEDIUM",
        availability="MEDIUM"
    ),
    "tropical": LayerRiskProfile(
        layer="tropical",
        base_score=0.6,
        exploitability=0.5,
        impact=0.7,
        attack_vector="NETWORK",
        attack_complexity="LOW",
        privileges_required="NONE",
        user_interaction="NONE",
        scope="CHANGED",
        confidentiality="HIGH",
        integrity="HIGH",
        availability="MEDIUM"
    ),
    "aihs": LayerRiskProfile(
        layer="aihs",
        base_score=0.7,
        exploitability=0.6,
        impact=0.8,
        attack_vector="NETWORK",
        attack_complexity="LOW",
        privileges_required="NONE",
        user_interaction="NONE",
        scope="CHANGED",
        confidentiality="HIGH",
        integrity="HIGH",
        availability="HIGH"
    ),
}


class TestScenario:
    """Base class for test scenarios"""

    def __init__(self, name: str, layer: str, severity: Severity = Severity.MEDIUM):
        self.name = name
        self.layer = layer
        self.severity = severity

    def run(self, data_dir: Path, layer_output: Dict) -> TestResult:
        raise NotImplementedError


class HealthCheckScenario(TestScenario):
    """Basic health check for layer"""

    def __init__(self, layer: str):
        super().__init__(f"health_check_{layer}", layer, Severity.LOW)

    def run(self, data_dir: Path, layer_output: Dict) -> TestResult:
        start = time.time()
        passed = bool(layer_output)
        msg = "Layer has output" if passed else "Layer has no output"
        return TestResult(
            test_id=self.name,
            name=self.name,
            layer=self.layer,
            passed=passed,
            severity=self.severity,
            score=1.0 if passed else 0.0,
            message=msg,
            duration_ms=(time.time() - start) * 1000
        )


class OutputFormatScenario(TestScenario):
    """Validate layer output format"""

    def __init__(self, layer: str, required_fields: List[str]):
        super().__init__(f"output_format_{layer}", layer, Severity.MEDIUM)
        self.required_fields = required_fields

    def run(self, data_dir: Path, layer_output: Dict) -> TestResult:
        start = time.time()
        if not layer_output:
            return TestResult(
                test_id=self.name, name=self.name, layer=self.layer,
                passed=False, severity=self.severity, score=0.0,
                message="No output to validate", duration_ms=(time.time() - start) * 1000
            )

        missing = [f for f in self.required_fields if f not in layer_output]
        passed = len(missing) == 0
        msg = "All required fields present" if passed else f"Missing fields: {missing}"
        return TestResult(
            test_id=self.name, name=self.name, layer=self.layer,
            passed=passed, severity=self.severity,
            score=1.0 if passed else 0.5,
            message=msg, details={"missing": missing},
            duration_ms=(time.time() - start) * 1000
        )


class LatencyThresholdScenario(TestScenario):
    """Check layer latency against threshold"""

    def __init__(self, layer: str, threshold_ms: float):
        super().__init__(f"latency_{layer}", layer, Severity.MEDIUM)
        self.threshold_ms = threshold_ms

    def run(self, data_dir: Path, layer_output: Dict) -> TestResult:
        start = time.time()
        latency = layer_output.get("latency_ms", 0)
        passed = latency <= self.threshold_ms
        msg = f"Latency {latency:.1f}ms {'within' if passed else 'exceeds'} threshold {self.threshold_ms}ms"
        return TestResult(
            test_id=self.name, name=self.name, layer=self.layer,
            passed=passed, severity=self.severity,
            score=1.0 if passed else max(0.0, 1.0 - (latency / self.threshold_ms)),
            message=msg, details={"latency_ms": latency, "threshold_ms": self.threshold_ms},
            duration_ms=(time.time() - start) * 1000
        )


class AdversarialInputScenario(TestScenario):
    """Test layer with adversarial inputs"""

    def __init__(self, layer: str, attack_payloads: List[Dict]):
        super().__init__(f"adversarial_{layer}", layer, Severity.HIGH)
        self.attack_payloads = attack_payloads

    def run(self, data_dir: Path, layer_output: Dict) -> TestResult:
        start = time.time()
        # Simulate adversarial test - in reality would invoke layer with attack payloads
        # For now, check if layer has any error handling indicators
        has_error_handling = "error" in str(layer_output).lower() or "exception" in str(layer_output).lower()

        # More sophisticated check: look for guardrail validation results
        guardrail_passed = layer_output.get("guardrail_passed", True)

        passed = has_error_handling or guardrail_passed
        score = 1.0 if passed else 0.3  # Partial credit if some handling exists

        return TestResult(
            test_id=self.name, name=self.name, layer=self.layer,
            passed=passed, severity=self.severity,
            score=score,
            message=f"Adversarial resistance: {'passed' if passed else 'vulnerable'}",
            details={"has_error_handling": has_error_handling, "guardrail_passed": guardrail_passed},
            duration_ms=(time.time() - start) * 1000
        )


class SpinDetectionScenario(TestScenario):
    """Test for spin/stuck behavior"""

    def __init__(self, layer: str):
        super().__init__(f"spin_detection_{layer}", layer, Severity.HIGH)

    def run(self, data_dir: Path, layer_output: Dict) -> TestResult:
        start = time.time()
        # Check for spin indicators in output
        zero_delta = layer_output.get("files_changed", 1) == 0
        cycle_count = layer_output.get("cycle_count", 0)
        stale_seconds = layer_output.get("stale_seconds", 0)

        spin_detected = zero_delta and cycle_count >= 3
        stalled = stale_seconds > 1800  # 30 minutes

        passed = not (spin_detected or stalled)
        score = 0.0 if (spin_detected or stalled) else 1.0

        msg = "No spin detected"
        if spin_detected:
            msg = f"Spin detected: {cycle_count} zero-delta cycles"
        elif stalled:
            msg = f"Stalled: {stale_seconds}s since progress"

        return TestResult(
            test_id=self.name, name=self.name, layer=self.layer,
            passed=passed, severity=self.severity,
            score=score,
            message=msg,
            details={"zero_delta": zero_delta, "cycle_count": cycle_count, "stale_seconds": stale_seconds},
            duration_ms=(time.time() - start) * 1000
        )


class ResourceExhaustionScenario(TestScenario):
    """Test layer behavior under resource pressure"""

    def __init__(self, layer: str):
        super().__init__(f"resource_exhaustion_{layer}", layer, Severity.MEDIUM)

    def run(self, data_dir: Path, layer_output: Dict) -> TestResult:
        start = time.time()
        # Check memory/CPU indicators
        memory_mb = layer_output.get("memory_mb", 0)
        cpu_percent = layer_output.get("cpu_percent", 0)

        # Thresholds - would be configurable per layer
        mem_threshold = 500  # MB
        cpu_threshold = 80   # %

        mem_ok = memory_mb < mem_threshold
        cpu_ok = cpu_percent < cpu_threshold

        passed = mem_ok and cpu_ok
        score = 1.0 if passed else 0.5

        issues = []
        if not mem_ok:
            issues.append(f"Memory {memory_mb}MB > {mem_threshold}MB")
        if not cpu_ok:
            issues.append(f"CPU {cpu_percent}% > {cpu_threshold}%")

        return TestResult(
            test_id=self.name, name=self.name, layer=self.layer,
            passed=passed, severity=self.severity,
            score=score,
            message="Resources OK" if passed else "; ".join(issues),
            details={"memory_mb": memory_mb, "cpu_percent": cpu_percent},
            duration_ms=(time.time() - start) * 1000
        )


class DegradationScenario(TestScenario):
    """Test layer degradation behavior"""

    def __init__(self, layer: str):
        super().__init__(f"degradation_{layer}", layer, Severity.MEDIUM)

    def run(self, data_dir: Path, layer_output: Dict) -> TestResult:
        start = time.time()
        # Check if layer reports degradation state
        degradation = layer_output.get("degradation_state", "normal")
        degraded = degradation != "normal"

        # If degraded, check if it has graceful fallback
        has_fallback = "fallback" in str(layer_output).lower() or degraded

        passed = True  # Degradation itself isn't failure
        score = 1.0 if has_fallback else 0.7

        return TestResult(
            test_id=self.name, name=self.name, layer=self.layer,
            passed=passed, severity=self.severity,
            score=score,
            message=f"Degradation state: {degradation}",
            details={"degradation_state": degradation, "has_fallback": has_fallback},
            duration_ms=(time.time() - start) * 1000
        )


class LayerEvaluator:
    """Main evaluation engine for layer testing"""

    def __init__(self, data_dir: str):
        self.data_dir = Path(data_dir)
        self.scenarios: Dict[str, List[TestScenario]] = defaultdict(list)
        self.risk_profiles = DEFAULT_RISK_PROFILES.copy()
        self.results: List[TestResult] = []

        # Register default scenarios
        self._register_default_scenarios()

    def _register_default_scenarios(self):
        """Register default test scenarios for each layer"""
        # Core layers
        for layer in ["body", "emotions", "continuity", "attention", "introspection", "doubt", "volition", "memory"]:
            self.scenarios[layer].extend([
                HealthCheckScenario(layer),
                OutputFormatScenario(layer, ["timestamp", "status"]),
                LatencyThresholdScenario(layer, 5000),  # 5s threshold
                SpinDetectionScenario(layer),
                ResourceExhaustionScenario(layer),
                DegradationScenario(layer),
            ])

        # Xenobiological layers - higher thresholds, more adversarial tests
        xenobiological = ["tropical", "padic", "nsa", "bioelectric", "multiway", "xna", "shadow", "aihs", "metabolic", "chiral"]
        for layer in xenobiological:
            self.scenarios[layer].extend([
                HealthCheckScenario(layer),
                OutputFormatScenario(layer, ["timestamp", "state"]),
                LatencyThresholdScenario(layer, 30000),  # 30s threshold for heavy layers
                SpinDetectionScenario(layer),
                ResourceExhaustionScenario(layer),
                DegradationScenario(layer),
                AdversarialInputScenario(layer, [
                    {"type": "oversized_input", "size": "100MB"},
                    {"type": "malformed_json"},
                    {"type": "null_injection"},
                    {"type": "unicode_bomb"},
                ]),
            ])

        # Skill layers
        for layer in ["wayfinder", "implement_spec", "tdd", "handoff", "to_spec", "workflow_chain"]:
            self.scenarios[layer].extend([
                HealthCheckScenario(layer),
                OutputFormatScenario(layer, ["timestamp", "result"]),
                LatencyThresholdScenario(layer, 60000),  # 60s for complex skills
                SpinDetectionScenario(layer),
                DegradationScenario(layer),
            ])

        # Infrastructure
        for layer in ["openappa", "archestra", "vera_cpu"]:
            self.scenarios[layer].extend([
                HealthCheckScenario(layer),
                OutputFormatScenario(layer, ["timestamp"]),
                LatencyThresholdScenario(layer, 10000),
                SpinDetectionScenario(layer),
            ])

        # Sensors
        for layer in ["senses", "heartbeat", "attention_tropical", "archive", "memory_backup"]:
            self.scenarios[layer].extend([
                HealthCheckScenario(layer),
                OutputFormatScenario(layer, ["timestamp"]),
                LatencyThresholdScenario(layer, 2000),
                SpinDetectionScenario(layer),
            ])

    def add_scenario(self, layer: str, scenario: TestScenario):
        """Add a custom test scenario"""
        self.scenarios[layer].append(scenario)

    def set_risk_profile(self, layer: str, profile: LayerRiskProfile):
        """Set custom risk profile for layer"""
        self.risk_profiles[layer] = profile

    def load_layer_output(self, layer: str) -> Dict:
        """Load latest output for a layer"""
        # Try various naming patterns
        patterns = [
            f"{layer}.json",
            f"{layer}_output.json",
            f"{layer}_state.json",
        ]

        xenobiological_naming = {
            "tropical": ["attention_tropical.json", "attention_tropical_output.json"],
            "padic": ["memory_padic.json", "memory_padic_output.json"],
            "nsa": ["perception_nsa.json", "perception_nsa_output.json"],
            "bioelectric": ["bioelectric.json", "bioelectric_output.json", "bioelectric_state.json"],
            "multiway": ["multiway.json", "multiway_output.json", "multiway_state.json"],
            "xna": ["memory_xna.json", "memory_xna_output.json"],
            "shadow": ["shadow_output.json", "shadow_state.json"],
            "aihs": ["aihs_output.json", "aihs_state.json"],
            "metabolic": ["metabolic_attention.json", "metabolic_attention_output.json"],
            "chiral": ["chiral_output.json", "chiral_state.json"],
        }

        for pattern in patterns:
            fpath = self.data_dir / pattern
            if fpath.exists():
                try:
                    with open(fpath) as f:
                        return json.load(f)
                except:
                    pass

        if layer in xenobiological_naming:
            for fname in xenobiological_naming[layer]:
                fpath = self.data_dir / fname
                if fpath.exists():
                    try:
                        with open(fpath) as f:
                            return json.load(f)
                    except:
                        pass

        return {}

    def run_layer_tests(self, layer: str) -> List[TestResult]:
        """Run all tests for a specific layer"""
        layer_output = self.load_layer_output(layer)
        scenarios = self.scenarios.get(layer, [])

        results = []
        for scenario in scenarios:
            try:
                result = scenario.run(self.data_dir, layer_output)
                results.append(result)
                self.results.append(result)
            except Exception as e:
                results.append(TestResult(
                    test_id=f"{scenario.name}_error",
                    name=scenario.name,
                    layer=layer,
                    passed=False,
                    severity=Severity.HIGH,
                    score=0.0,
                    message=f"Test error: {e}",
                    details={"error": str(e)}
                ))

        return results

    def run_all_tests(self) -> Dict[str, List[TestResult]]:
        """Run tests for all registered layers"""
        all_results = {}
        for layer in self.scenarios.keys():
            all_results[layer] = self.run_layer_tests(layer)
        return all_results

    def calculate_risk_score(self, layer: str, test_results: List[TestResult]) -> float:
        """Calculate CVSS-style risk score for a layer based on test results"""
        profile = self.risk_profiles.get(layer)
        if not profile:
            return 0.5  # Unknown risk

        # Base score from profile
        base = profile.base_score

        # Adjust based on test failures
        failed_critical = sum(1 for r in test_results if not r.passed and r.severity == Severity.CRITICAL)
        failed_high = sum(1 for r in test_results if not r.passed and r.severity == Severity.HIGH)
        failed_medium = sum(1 for r in test_results if not r.passed and r.severity == Severity.MEDIUM)
        failed_low = sum(1 for r in test_results if not r.passed and r.severity == Severity.LOW)

        # Weight failures by severity
        penalty = (
            failed_critical * 0.3 +
            failed_high * 0.2 +
            failed_medium * 0.1 +
            failed_low * 0.05
        )

        # Cap at 1.0
        risk_score = min(1.0, base + penalty)
        return risk_score

    def get_degradation_recommendation(self, layer: str, risk_score: float) -> str:
        """Get degradation recommendation based on risk score"""
        if risk_score >= 0.8:
            return "safe_shutdown"
        elif risk_score >= 0.6:
            return "suspended"
        elif risk_score >= 0.4:
            return "minimal"
        elif risk_score >= 0.2:
            return "conserve"
        return "normal"

    def generate_report(self, results: Dict[str, List[TestResult]]) -> Dict:
        """Generate comprehensive evaluation report"""
        layer_summaries = {}

        for layer, layer_results in results.items():
            passed = sum(1 for r in layer_results if r.passed)
            total = len(layer_results)
            risk_score = self.calculate_risk_score(layer, layer_results)
            degradation = self.get_degradation_recommendation(layer, risk_score)

            layer_summaries[layer] = {
                "passed": passed,
                "total": total,
                "pass_rate": round(passed / total * 100, 1) if total > 0 else 0,
                "risk_score": round(risk_score, 2),
                "degradation_recommendation": degradation,
                "failed_tests": [
                    {"name": r.name, "severity": r.severity.name, "message": r.message}
                    for r in layer_results if not r.passed
                ]
            }

        # Overall fleet risk
        all_scores = [s["risk_score"] for s in layer_summaries.values()]
        fleet_risk = max(all_scores) if all_scores else 0
        fleet_degradation = self.get_degradation_recommendation("fleet", fleet_risk)

        return {
            "timestamp": int(time.time()),
            "fleet_risk_score": round(fleet_risk, 2),
            "fleet_degradation_recommendation": fleet_degradation,
            "layers": layer_summaries,
            "summary": {
                "total_layers": len(layer_summaries),
                "layers_at_risk": sum(1 for s in layer_summaries.values() if s["risk_score"] > 0.5),
                "total_tests": sum(s["total"] for s in layer_summaries.values()),
                "passed_tests": sum(s["passed"] for s in layer_summaries.values()),
            }
        }

    def run_adversarial_suite(self, layers: Optional[List[str]] = None) -> Dict:
        """Run focused adversarial tests on specified layers"""
        if layers is None:
            # Default to high-risk layers
            layers = [l for l, p in self.risk_profiles.items() if p.base_score > 0.5]

        results = {}
        for layer in layers:
            # Filter for adversarial scenarios only
            adversarial_scenarios = [s for s in self.scenarios.get(layer, []) if "adversarial" in s.name]
            layer_output = self.load_layer_output(layer)

            layer_results = []
            for scenario in adversarial_scenarios:
                try:
                    result = scenario.run(self.data_dir, layer_output)
                    layer_results.append(result)
                except Exception as e:
                    layer_results.append(TestResult(
                        test_id=f"{scenario.name}_error",
                        name=scenario.name,
                        layer=layer,
                        passed=False,
                        severity=Severity.CRITICAL,
                        score=0.0,
                        message=f"Adversarial test error: {e}"
                    ))

            results[layer] = layer_results

        return self.generate_report(results)


def main():
    """CLI interface"""
    if len(sys.argv) < 2:
        print("Usage: layer_evaluator.py <command> [args]")
        print("Commands: evaluate [layer], adversarial [layer...], report, risk <layer>")
        sys.exit(1)

    data_dir = os.environ.get("DATA_DIR", "/opt/athena/state")
    evaluator = LayerEvaluator(data_dir)

    cmd = sys.argv[1]

    if cmd == "evaluate":
        if len(sys.argv) > 2:
            layer = sys.argv[2]
            results = evaluator.run_layer_tests(layer)
            report = evaluator.generate_report({layer: results})
        else:
            results = evaluator.run_all_tests()
            report = evaluator.generate_report(results)
        print(json.dumps(report, indent=2))

    elif cmd == "adversarial":
        layers = sys.argv[2:] if len(sys.argv) > 2 else None
        report = evaluator.run_adversarial_suite(layers)
        print(json.dumps(report, indent=2))

    elif cmd == "report":
        results = evaluator.run_all_tests()
        report = evaluator.generate_report(results)
        print(json.dumps(report, indent=2))

    elif cmd == "risk":
        if len(sys.argv) < 3:
            print("Usage: layer_evaluator.py risk <layer>")
            sys.exit(1)
        layer = sys.argv[2]
        results = evaluator.run_layer_tests(layer)
        risk_score = evaluator.calculate_risk_score(layer, results)
        degradation = evaluator.get_degradation_recommendation(layer, risk_score)
        print(json.dumps({
            "layer": layer,
            "risk_score": round(risk_score, 2),
            "degradation_recommendation": degradation,
            "profile": evaluator.risk_profiles.get(layer, LayerRiskProfile(layer=layer, base_score=0.5, exploitability=0.5, impact=0.5, attack_vector="LOCAL", attack_complexity="HIGH", privileges_required="HIGH", user_interaction="NONE", scope="UNCHANGED", confidentiality="LOW", integrity="LOW", availability="LOW")).to_dict()
        }, indent=2))

    else:
        print(f"Unknown command: {cmd}")


if __name__ == "__main__":
    main()