#!/usr/bin/env python3
"""
Health-First Observability Dashboard for Athena Daemon

Provides real-time layer status, latency percentiles, cost tracking,
guardrail violation rates, spin detection alerts, and state machine progress.
"""

import json
import os
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional
from dataclasses import dataclass
from collections import defaultdict
import statistics


@dataclass
class LayerStatus:
    """Health status for a single layer"""
    name: str
    status: str  # green, yellow, red, unknown
    last_update: int
    latency_ms: float = 0
    error_count: int = 0
    success_count: int = 0
    guardrail_violations: int = 0
    spin_alert: bool = False


@dataclass
class CostMetrics:
    """Cost tracking per layer and model"""
    total_usd: float = 0
    by_layer: Dict[str, float] = None
    by_model: Dict[str, float] = None
    by_phase: Dict[str, float] = None

    def __post_init__(self):
        self.by_layer = self.by_layer or {}
        self.by_model = self.by_model or {}
        self.by_phase = self.by_phase or {}


class ObservabilityEngine:
    """Aggregates data from daemon ledgers and layer outputs for dashboard"""

    def __init__(self, data_dir: str):
        self.data_dir = Path(data_dir)
        self.layer_groups = {
            "Core": ["body", "emotions", "continuity", "attention", "introspection", "doubt", "volition", "memory"],
            "Xenobiological": ["tropical", "padic", "nsa", "bioelectric", "multiway", "xna", "shadow", "aihs", "metabolic", "chiral"],
            "Skills": ["wayfinder", "implement_spec", "tdd", "handoff", "to_spec", "workflow_chain"],
            "Infrastructure": ["openappa", "archestra", "vera_cpu"],
            "Sensors": ["senses", "heartbeat", "attention_tropical", "archive", "memory_backup"],
        }

    def read_json(self, path: Path) -> Dict:
        if not path.exists():
            return {}
        try:
            with open(path) as f:
                return json.load(f)
        except:
            return {}

    def read_jsonl(self, path: Path, limit: int = 100) -> List[Dict]:
        if not path.exists():
            return []
        try:
            with open(path) as f:
                lines = f.readlines()
            return [json.loads(line) for line in lines[-limit:]]
        except:
            return []

    def get_layer_status(self, layer: str) -> LayerStatus:
        """Get health status for a single layer"""
        now = int(time.time())

        # Check layer output file - handle various naming patterns
        layer_file = self.data_dir / f"{layer}.json"
        layer_output = self.data_dir / f"{layer}_output.json"
        layer_state = self.data_dir / f"{layer}_state.json"

        # Xenobiological layers have special naming conventions
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

        # Try standard names first, then xenobiological naming
        data = self.read_json(layer_file) or self.read_json(layer_output) or self.read_json(layer_state)

        if not data and layer in xenobiological_naming:
            for fname in xenobiological_naming[layer]:
                fpath = self.data_dir / fname
                if fpath.exists():
                    data = self.read_json(fpath)
                    if data:
                        layer_file = fpath
                        break

        # Determine last update from all possible files
        last_update = 0
        for f in [layer_file, layer_output, layer_state]:
            if f.exists():
                last_update = max(last_update, int(f.stat().st_mtime))

        # Also check xenobiological naming files
        if layer in xenobiological_naming:
            for fname in xenobiological_naming[layer]:
                fpath = self.data_dir / fname
                if fpath.exists():
                    last_update = max(last_update, int(fpath.stat().st_mtime))

        # Check PID file for running status
        pid_file = self.data_dir / f".{layer}.pid.lock"
        pid_wrapper = self.data_dir / f"{layer}.pid.wrapper"
        is_running = pid_file.exists() or pid_wrapper.exists()

        # Special handling for xenobiological layers - check if parent daemon is running
        xenobiological_layers = list(xenobiological_naming.keys())
        if layer in xenobiological_layers:
            xenopid = self.data_dir / "xenobiological_daemon.pid"
            if xenopid.exists():
                # Check if layer has recent output (within last 10 minutes)
                if last_update > 0 and (now - last_update) < 600:
                    is_running = True

        # Calculate latency from daemon_latency.json
        latency_data = self.read_json(self.data_dir / "daemon_latency.json")
        latency_ms = latency_data.get(layer, {}).get("avg_ms", 0)

        # Get error/success counts from feedback
        feedback = self.read_json(self.data_dir / "daemon_feedback.json")
        layer_feedback = feedback.get(layer, {})
        error_count = layer_feedback.get("error_count", 0)
        success_count = layer_feedback.get("success_count", 0)

        # Check guardrail violations from checkpoint context
        guardrail_violations = self._count_guardrail_violations(layer)

        # Check spin detection
        spin_alert = self._check_spin_alert(layer)

        # Determine status
        if not is_running:
            status = "red"
        elif spin_alert:
            status = "yellow"
        elif error_count > 5 and success_count == 0:
            status = "red"
        elif error_count > 0 or guardrail_violations > 0:
            status = "yellow"
        else:
            status = "green"

        return LayerStatus(
            name=layer,
            status=status,
            last_update=last_update,
            latency_ms=latency_ms,
            error_count=error_count,
            success_count=success_count,
            guardrail_violations=guardrail_violations,
            spin_alert=spin_alert
        )

    def _count_guardrail_violations(self, layer: str) -> int:
        """Count guardrail violations for a layer from cycle context"""
        context_file = self.data_dir / "daemon_cycle_context.json"
        context = self.read_json(context_file)
        violations = context.get("guardrail_violations", {})
        return violations.get(layer, 0)

    def _check_spin_alert(self, layer: str) -> bool:
        """Check for spin detection alert"""
        checkpoints_file = self.data_dir / "daemon_checkpoints.jsonl"
        if not checkpoints_file.exists():
            return False

        checkpoints = self.read_jsonl(checkpoints_file, 20)
        zero_delta = 0
        last_progress = None

        for cp in reversed(checkpoints):
            lr = cp.get("layer_results", {}).get(layer, {})
            if lr.get("files_changed", 0) == 0:
                zero_delta += 1
            else:
                if last_progress is None:
                    last_progress = cp.get("timestamp")
                break

        if zero_delta >= 3:
            return True

        if last_progress:
            if int(time.time()) - last_progress > 1800:
                return True

        return False

    def get_all_layer_status(self) -> Dict[str, LayerStatus]:
        """Get status for all known layers"""
        all_layers = []
        for group_layers in self.layer_groups.values():
            all_layers.extend(group_layers)

        statuses = {}
        for layer in all_layers:
            statuses[layer] = self.get_layer_status(layer)
        return statuses

    def get_group_health(self) -> Dict[str, Dict]:
        """Get health summary per layer group"""
        statuses = self.get_all_layer_status()
        groups = {}

        for group_name, layers in self.layer_groups.items():
            group_statuses = [statuses.get(l) for l in layers if l in statuses]
            if not group_statuses:
                continue

            green = sum(1 for s in group_statuses if s.status == "green")
            yellow = sum(1 for s in group_statuses if s.status == "yellow")
            red = sum(1 for s in group_statuses if s.status == "red")
            unknown = sum(1 for s in group_statuses if s.status == "unknown")

            total = len(group_statuses)
            overall = "green"
            if red > 0:
                overall = "red"
            elif yellow > 0:
                overall = "yellow"
            elif green == 0:
                overall = "unknown"

            stale_layers = []
            for s in group_statuses:
                if s.last_update > 0:
                    age = int(time.time()) - s.last_update
                    if age > 300:
                        stale_layers.append(f"{s.name} ({age}s)")

            groups[group_name] = {
                "overall": overall,
                "green": green,
                "yellow": yellow,
                "red": red,
                "unknown": unknown,
                "total": total,
                "stale": stale_layers,
                "layers": {s.name: s.status for s in group_statuses}
            }

        return groups

    def get_latency_percentiles(self) -> Dict[str, Dict[str, float]]:
        """Calculate latency percentiles per layer from daemon_latency.json"""
        latency_data = self.read_json(self.data_dir / "daemon_latency.json")
        percentiles = {}

        # Handle both old format (per-layer with samples) and new format (aggregate)
        if "recent_latencies" in latency_data:
            # New aggregate format - no per-layer breakdown
            samples = latency_data.get("recent_latencies", [])
            if samples:
                sorted_samples = sorted(samples)
                n = len(sorted_samples)
                percentiles["aggregate"] = {
                    "p50": sorted_samples[int(n * 0.5)],
                    "p95": sorted_samples[int(n * 0.95)],
                    "p99": sorted_samples[int(n * 0.99)],
                    "avg": statistics.mean(sorted_samples),
                    "count": n
                }
            else:
                percentiles["aggregate"] = {"p50": 0, "p95": 0, "p99": 0, "avg": 0, "count": 0}
        else:
            # Old per-layer format
            for layer, data in latency_data.items():
                if not isinstance(data, dict):
                    continue
                samples = data.get("samples", [])
                if not samples:
                    percentiles[layer] = {"p50": 0, "p95": 0, "p99": 0, "avg": 0, "count": 0}
                    continue

                sorted_samples = sorted(samples)
                n = len(sorted_samples)

                percentiles[layer] = {
                    "p50": sorted_samples[int(n * 0.5)],
                    "p95": sorted_samples[int(n * 0.95)],
                    "p99": sorted_samples[int(n * 0.99)],
                    "avg": statistics.mean(sorted_samples),
                    "count": n
                }

        return percentiles

    def get_cost_metrics(self) -> CostMetrics:
        """Get cost tracking from task ledger"""
        ledger_file = self.data_dir / "daemon_task_ledger.json"
        ledger = self.read_json(ledger_file)
        budget = ledger.get("budget", {"total_usd": 0, "by_layer": {}, "by_model": {}, "by_phase": {}})

        return CostMetrics(
            total_usd=budget.get("total_usd", 0),
            by_layer=budget.get("by_layer", {}),
            by_model=budget.get("by_model", {}),
            by_phase=budget.get("by_phase", {})
        )

    def get_state_machine_progress(self) -> Dict:
        """Get state machine progress from task ledger"""
        ledger_file = self.data_dir / "daemon_task_ledger.json"
        ledger = self.read_json(ledger_file)

        state = ledger.get("state_machine_state", "SEEDING")
        degradation = ledger.get("degradation_state", "normal")
        session_mode = ledger.get("session_mode", "event_driven")

        state_order = [
            "SEEDING", "READY", "FOUNDATION", "FOUNDATION_EVAL",
            "STORY_BUILDING", "MILESTONE_CHECK", "MILESTONE_FIX",
            "ANALYZING", "GENERATING_CHANGE_SPEC", "VISION_CHECK",
            "SHIPPING", "FINAL_REVIEW", "COMPLETE", "ESCALATION"
        ]

        current_idx = state_order.index(state) if state in state_order else 0
        total = len(state_order)

        return {
            "current_state": state,
            "degradation": degradation,
            "session_mode": session_mode,
            "progress_index": current_idx,
            "progress_total": total,
            "progress_pct": round((current_idx / (total - 1)) * 100) if total > 1 else 0,
            "next_states": self._get_next_valid_states(state)
        }

    def _get_next_valid_states(self, state: str) -> List[str]:
        transitions = {
            "SEEDING": ["READY"],
            "READY": ["FOUNDATION", "ESCALATION"],
            "FOUNDATION": ["FOUNDATION_EVAL", "ESCALATION"],
            "FOUNDATION_EVAL": ["STORY_BUILDING", "FOUNDATION", "ESCALATION"],
            "STORY_BUILDING": ["MILESTONE_CHECK", "ESCALATION"],
            "MILESTONE_CHECK": ["ANALYZING", "MILESTONE_FIX", "ESCALATION"],
            "MILESTONE_FIX": ["MILESTONE_CHECK", "ESCALATION"],
            "ANALYZING": ["GENERATING_CHANGE_SPEC", "ESCALATION"],
            "GENERATING_CHANGE_SPEC": ["VISION_CHECK", "ESCALATION"],
            "VISION_CHECK": ["SHIPPING", "ANALYZING", "ESCALATION"],
            "SHIPPING": ["FINAL_REVIEW", "ESCALATION"],
            "FINAL_REVIEW": ["COMPLETE", "SHIPPING", "ESCALATION"],
            "COMPLETE": ["SEEDING", "ESCALATION"],
            "ESCALATION": ["SEEDING", "READY"],
        }
        return transitions.get(state, [])

    def get_recent_spin_alerts(self, limit: int = 10) -> List[Dict]:
        """Get recent spin detection alerts from checkpoints"""
        checkpoints_file = self.data_dir / "daemon_checkpoints.jsonl"
        if not checkpoints_file.exists():
            return []

        checkpoints = self.read_jsonl(checkpoints_file, limit * 5)
        alerts = []

        for cp in checkpoints:
            for layer, lr in cp.get("layer_results", {}).items():
                if lr.get("spin_detected", False):
                    alerts.append({
                        "cycle_id": cp.get("cycle_id"),
                        "timestamp": cp.get("timestamp"),
                        "layer": layer,
                        "zero_delta_count": lr.get("zero_delta_count", 0),
                        "stale_seconds": lr.get("stale_seconds", 0),
                        "recommendation": lr.get("recommendation", "escalate")
                    })

        return alerts[-limit:]

    def get_guardrail_violations_summary(self) -> Dict[str, int]:
        """Get guardrail violation counts by layer"""
        context_file = self.data_dir / "daemon_cycle_context.json"
        context = self.read_json(context_file)
        return context.get("guardrail_violations", {})

    def get_full_dashboard_data(self) -> Dict:
        """Get all dashboard data in one call"""
        return {
            "timestamp": int(time.time()),
            "groups": self.get_group_health(),
            "latency_percentiles": self.get_latency_percentiles(),
            "cost_metrics": self.get_cost_metrics().__dict__,
            "state_machine": self.get_state_machine_progress(),
            "spin_alerts": self.get_recent_spin_alerts(),
            "guardrail_violations": self.get_guardrail_violations_summary(),
        }


def main():
    """CLI for dashboard data"""
    data_dir = os.environ.get("DATA_DIR", "/opt/athena/state")
    obs = ObservabilityEngine(data_dir)

    if len(sys.argv) < 2:
        print("Usage: observability.py <command>")
        print("Commands: full, groups, latency, cost, state, spin, guardrails, layer <name>")
        sys.exit(1)

    cmd = sys.argv[1]

    if cmd == "full":
        print(json.dumps(obs.get_full_dashboard_data(), indent=2))
    elif cmd == "groups":
        print(json.dumps(obs.get_group_health(), indent=2))
    elif cmd == "latency":
        print(json.dumps(obs.get_latency_percentiles(), indent=2))
    elif cmd == "cost":
        print(json.dumps(obs.get_cost_metrics().__dict__, indent=2))
    elif cmd == "state":
        print(json.dumps(obs.get_state_machine_progress(), indent=2))
    elif cmd == "spin":
        print(json.dumps(obs.get_recent_spin_alerts(), indent=2))
    elif cmd == "guardrails":
        print(json.dumps(obs.get_guardrail_violations_summary(), indent=2))
    elif cmd == "layer" and len(sys.argv) > 2:
        layer = sys.argv[2]
        status = obs.get_layer_status(layer)
        print(json.dumps(status.__dict__, indent=2))
    else:
        print(f"Unknown command: {cmd}")


if __name__ == "__main__":
    main()