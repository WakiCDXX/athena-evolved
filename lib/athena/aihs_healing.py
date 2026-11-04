#!/usr/bin/env python3
"""
AIHS (Autonomous Integrated Healing System) Daemons for Athena.

Based on Alien Medicine research: Bioelectric morphogenesis (Levin),
xenobots, collective cell intelligence, distributed healing.

Each Athena layer gets a healing daemon that:
1. Monitors layer health (bioelectric state analogue)
2. Detects anomalies/degradation
3. Applies corrective actions autonomously
4. Coordinates with other layer daemons for systemic healing
5. Maintains homeostatic setpoints per layer
"""

import json
import os
import sys
import time
import threading
import subprocess
import statistics
from typing import Dict, List, Optional, Tuple, Any, Callable
from dataclasses import dataclass, field
from enum import Enum
from collections import defaultdict, deque
from abc import ABC, abstractmethod


class LayerHealth(Enum):
    """Health states for Athena layers."""
    HEALTHY = "healthy"
    STRESSED = "stressed"
    DEGRADED = "degraded"
    CRITICAL = "critical"
    HEALING = "healing"
    UNKNOWN = "unknown"


class HealingAction(Enum):
    """Types of healing actions."""
    RESTART_LAYER = "restart_layer"
    CLEAR_CACHE = "clear_cache"
    REBALANCE_LOAD = "rebalance_load"
    RESET_STATE = "reset_state"
    RECONNECT = "reconnect"
    REDUCE_FREQUENCY = "reduce_frequency"
    INCREASE_FREQUENCY = "increase_frequency"
    PURGE_OLD_DATA = "purge_old_data"
    REINITIALIZE = "reinitialize"
    CROSS_LAYER_SYNC = "cross_layer_sync"
    BIOELECTRIC_RESET = "bioelectric_reset"  # Reset Vmem to target
    PATTERN_RECALL = "pattern_recall"        # Recall known good pattern


@dataclass
class LayerSetpoint:
    """Homeostatic setpoint for a layer (bioelectric target analogue)."""
    layer_name: str
    cpu_target: float          # target CPU%
    mem_target: float          # target memory MB
    latency_target: float      # target latency ms
    error_rate_target: float   # target error rate
    throughput_target: float   # target ops/sec
    vmem_target: float = -70.0 # bioelectric resting potential analogue
    tolerance: float = 0.2     # 20% tolerance band


@dataclass
class LayerState:
    """Current state of a layer."""
    layer_name: str
    health: LayerHealth
    cpu_percent: float
    mem_mb: float
    latency_ms: float
    error_rate: float
    throughput: float
    last_update: float
    vmem: float = -70.0           # Bioelectric potential
    anomaly_score: float = 0.0    # Deviation from setpoint
    consecutive_failures: int = 0
    healing_actions: List[str] = field(default_factory=list)
    metadata: Dict = field(default_factory=dict)


@dataclass
class HealingEvent:
    """Record of a healing action."""
    timestamp: float
    layer: str
    action: HealingAction
    reason: str
    success: bool
    before_state: Dict
    after_state: Dict


class LayerHealingDaemon(ABC):
    """Base class for layer-specific healing daemons."""

    def __init__(self, layer_name: str, setpoint: LayerSetpoint):
        self.layer_name = layer_name
        self.setpoint = setpoint
        self.state = LayerState(
            layer_name=layer_name,
            health=LayerHealth.UNKNOWN,
            cpu_percent=0,
            mem_mb=0,
            latency_ms=0,
            error_rate=0,
            throughput=0,
            last_update=time.time()
        )
        self.healing_history: List[HealingEvent] = []
        self.running = False
        self._lock = threading.Lock()

    @abstractmethod
    def collect_metrics(self) -> Dict:
        """Collect current metrics for this layer."""
        pass

    @abstractmethod
    def apply_healing(self, action: HealingAction, reason: str) -> bool:
        """Apply a healing action. Return success."""
        pass

    def assess_health(self) -> LayerHealth:
        """Assess layer health based on deviation from setpoint."""
        with self._lock:
            deviations = []

            # CPU deviation
            if self.setpoint.cpu_target > 0:
                cpu_dev = abs(self.state.cpu_percent - self.setpoint.cpu_target) / self.setpoint.cpu_target
                deviations.append(cpu_dev)

            # Memory deviation
            if self.setpoint.mem_target > 0:
                mem_dev = abs(self.state.mem_mb - self.setpoint.mem_target) / self.setpoint.mem_target
                deviations.append(mem_dev)

            # Latency deviation
            if self.setpoint.latency_target > 0:
                lat_dev = max(0, (self.state.latency_ms - self.setpoint.latency_target) / self.setpoint.latency_target)
                deviations.append(lat_dev)

            # Error rate deviation
            if self.setpoint.error_rate_target > 0:
                err_dev = max(0, (self.state.error_rate - self.setpoint.error_rate_target) / self.setpoint.error_rate_target)
                deviations.append(err_dev)

            # Bioelectric deviation (Vmem)
            vmem_dev = abs(self.state.vmem - self.setpoint.vmem_target) / abs(self.setpoint.vmem_target)
            deviations.append(vmem_dev)

            # Overall anomaly score
            self.state.anomaly_score = statistics.mean(deviations) if deviations else 0

            # Determine health
            if self.state.anomaly_score < self.setpoint.tolerance:
                return LayerHealth.HEALTHY
            elif self.state.anomaly_score < self.setpoint.tolerance * 2:
                return LayerHealth.STRESSED
            elif self.state.anomaly_score < self.setpoint.tolerance * 4:
                return LayerHealth.DEGRADED
            else:
                return LayerHealth.CRITICAL

    def determine_healing_action(self) -> Optional[HealingAction]:
        """Determine appropriate healing action based on state."""
        health = self.assess_health()
        self.state.health = health

        if health == LayerHealth.HEALTHY:
            return None

        # Escalating healing strategies
        if health == LayerHealth.STRESSED:
            # Gentle interventions
            if self.state.cpu_percent > self.setpoint.cpu_target * 1.5:
                return HealingAction.REDUCE_FREQUENCY
            if self.state.mem_mb > self.setpoint.mem_target * 1.5:
                return HealingAction.CLEAR_CACHE
            if self.state.vmem < self.setpoint.vmem_target - 20:  # Depolarized
                return HealingAction.BIOELECTRIC_RESET

        elif health == LayerHealth.DEGRADED:
            # Moderate interventions
            if self.state.consecutive_failures > 3:
                return HealingAction.RESTART_LAYER
            if self.state.error_rate > self.setpoint.error_rate_target * 5:
                return HealingAction.RESET_STATE
            if self.state.mem_mb > self.setpoint.mem_target * 2:
                return HealingAction.PURGE_OLD_DATA

        elif health == LayerHealth.CRITICAL:
            # Aggressive interventions
            return HealingAction.REINITIALIZE

        return None

    def heal(self) -> Optional[HealingEvent]:
        """Execute one healing cycle."""
        # Collect metrics
        metrics = self.collect_metrics()
        with self._lock:
            self.state.cpu_percent = metrics.get("cpu_percent", 0)
            self.state.mem_mb = metrics.get("mem_mb", 0)
            self.state.latency_ms = metrics.get("latency_ms", 0)
            self.state.error_rate = metrics.get("error_rate", 0)
            self.state.throughput = metrics.get("throughput", 0)
            self.state.vmem = metrics.get("vmem", -70.0)
            self.state.last_update = time.time()

        # Assess and determine action
        action = self.determine_healing_action()
        if not action:
            return None

        # Execute healing
        before = {
            "health": self.state.health.value,
            "anomaly": self.state.anomaly_score,
            "cpu": self.state.cpu_percent,
            "mem": self.state.mem_mb,
            "vmem": self.state.vmem
        }

        reason = f"Health: {self.state.health.value}, anomaly: {self.state.anomaly_score:.2f}"
        success = self.apply_healing(action, reason)

        # Collect after metrics
        time.sleep(0.5)
        after_metrics = self.collect_metrics()
        after = {
            "health": self.assess_health().value,
            "anomaly": self.state.anomaly_score,
            "cpu": after_metrics.get("cpu_percent", 0),
            "mem": after_metrics.get("mem_mb", 0),
            "vmem": after_metrics.get("vmem", -70.0)
        }

        event = HealingEvent(
            timestamp=time.time(),
            layer=self.layer_name,
            action=action,
            reason=reason,
            success=success,
            before_state=before,
            after_state=after
        )

        with self._lock:
            self.healing_history.append(event)
            self.state.healing_actions.append(f"{action.value}:{success}")

        return event


class AttentionHealingDaemon(LayerHealingDaemon):
    """Healing daemon for Attention layer."""

    def __init__(self):
        setpoint = LayerSetpoint(
            layer_name="attention",
            cpu_target=5.0,
            mem_target=50.0,
            latency_target=100.0,
            error_rate_target=0.01,
            throughput_target=10.0,
            vmem_target=-65.0  # Slightly depolarized for active attention
        )
        super().__init__("attention", setpoint)

    def collect_metrics(self) -> Dict:
        """Collect attention layer metrics."""
        metrics = {"cpu_percent": 0, "mem_mb": 0, "latency_ms": 0, "error_rate": 0, "throughput": 0, "vmem": -65.0}

        # Check attention.json
        try:
            with open("/opt/athena/state/attention.json") as f:
                attn = json.load(f)
            concerns = attn.get("concerns", [])
            metrics["error_rate"] = len([c for c in concerns if "error" in c.lower()]) / max(len(concerns), 1)
            metrics["throughput"] = len(attn.get("background", []))
        except:
            pass

        # Get process metrics for attention-related processes
        try:
            result = subprocess.run(["ps", "aux"], capture_output=True, text=True)
            for line in result.stdout.split('\n'):
                if "attention" in line.lower() or "volition" in line.lower():
                    parts = line.split()
                    if len(parts) >= 6:
                        metrics["cpu_percent"] += float(parts[2])
                        metrics["mem_mb"] += int(parts[5]) / 1024
        except:
            pass

        return metrics

    def apply_healing(self, action: HealingAction, reason: str) -> bool:
        """Apply healing to attention layer."""
        try:
            if action == HealingAction.REDUCE_FREQUENCY:
                # Increase attention interval
                subprocess.run(["touch", "/opt/athena/state/.attention.heal_reduce"], check=False)
                return True

            elif action == HealingAction.CLEAR_CACHE:
                # Clear attention cache
                cache_dir = "/opt/athena/state/.attention_cache"
                if os.path.exists(cache_dir):
                    subprocess.run(["rm", "-rf", cache_dir], check=False)
                return True

            elif action == HealingAction.BIOELECTRIC_RESET:
                # Reset via bioelectric coupling
                subprocess.run(["/root/.local/bin/bioelectric_coupling.sh", "repair"], check=False)
                return True

            elif action == HealingAction.RESTART_LAYER:
                subprocess.run(["/root/.local/bin/athena_daemon.sh", "restart", "attention"], check=False)
                return True

            elif action == HealingAction.RESET_STATE:
                # Reset attention state
                default_attn = {"active_task": "idle", "background": [], "concerns": [], "timestamp": time.time()}
                with open("/opt/athena/state/attention.json", "w") as f:
                    json.dump(default_attn, f)
                return True

        except Exception as e:
            print(f"Attention healing failed: {e}", file=sys.stderr)
        return False


class MemoryHealingDaemon(LayerHealingDaemon):
    """Healing daemon for Memory layer."""

    def __init__(self):
        setpoint = LayerSetpoint(
            layer_name="memory",
            cpu_target=3.0,
            mem_target=100.0,
            latency_target=50.0,
            error_rate_target=0.001,
            throughput_target=100.0,
            vmem_target=-75.0  # Hyperpolarized for stable storage
        )
        super().__init__("memory", setpoint)

    def collect_metrics(self) -> Dict:
        metrics = {"cpu_percent": 0, "mem_mb": 0, "latency_ms": 0, "error_rate": 0, "throughput": 0, "vmem": -75.0}

        # Check memory.json size
        try:
            mem_path = "/opt/athena/state/memory.json"
            if os.path.exists(mem_path):
                size_mb = os.path.getsize(mem_path) / (1024 * 1024)
                metrics["mem_mb"] = size_mb
                with open(mem_path) as f:
                    data = json.load(f)
                metrics["throughput"] = len(data) if isinstance(data, dict) else 0
        except:
            pass

        # XNA store metrics
        try:
            xna_path = "/opt/athena/state/memory_xna.json"
            if os.path.exists(xna_path):
                with open(xna_path) as f:
                    xna = json.load(f)
                packets = xna.get("packets", {})
                metrics["error_rate"] = len([p for p in packets.values() if not p.get("verified", True)]) / max(len(packets), 1)
        except:
            pass

        return metrics

    def apply_healing(self, action: HealingAction, reason: str) -> bool:
        try:
            if action == HealingAction.CLEAR_CACHE:
                # Consolidate memory (rebuild indexes)
                subprocess.run(["/root/.local/bin/memory_xna.sh", "consolidate"], check=False)
                return True

            elif action == HealingAction.PURGE_OLD_DATA:
                # Archive old memories
                subprocess.run(["/root/.local/bin/memory_xna.sh", "repair"], check=False)
                return True

            elif action == HealingAction.BIOELECTRIC_RESET:
                subprocess.run(["/root/.local/bin/bioelectric_coupling.sh", "repair"], check=False)
                return True

            elif action == HealingAction.REINITIALIZE:
                subprocess.run(["/root/.local/bin/memory_xna.sh", "consolidate"], check=False)
                return True

        except Exception as e:
            print(f"Memory healing failed: {e}", file=sys.stderr)
        return False


class VolitionHealingDaemon(LayerHealingDaemon):
    """Healing daemon for Volition layer."""

    def __init__(self):
        setpoint = LayerSetpoint(
            layer_name="volition",
            cpu_target=8.0,
            mem_target=80.0,
            latency_target=200.0,
            error_rate_target=0.05,
            throughput_target=5.0,
            vmem_target=-55.0  # Depolarized for decision making
        )
        super().__init__("volition", setpoint)

    def collect_metrics(self) -> Dict:
        metrics = {"cpu_percent": 0, "mem_mb": 0, "latency_ms": 0, "error_rate": 0, "throughput": 0, "vmem": -55.0}

        # Check multiway state
        try:
            with open("/opt/athena/state/multiway_state.json") as f:
                mws = json.load(f)
            frontier = mws.get("frontier", [])
            metrics["throughput"] = len(frontier)
            # Check causal invariance
            metrics["error_rate"] = 0.0 if mws.get("causal_invariant", True) else 0.5
        except:
            pass

        return metrics

    def apply_healing(self, action: HealingAction, reason: str) -> bool:
        try:
            if action == HealingAction.RESET_STATE:
                # Reinitialize multiway system
                subprocess.run(["/root/.local/bin/multiway_volition.sh", "init"], check=False)
                return True

            elif action == HealingAction.CROSS_LAYER_SYNC:
                # Sync with attention and memory
                subprocess.run(["/root/.local/bin/multiway_volition.sh", "step"], check=False)
                return True

            elif action == HealingAction.BIOELECTRIC_RESET:
                subprocess.run(["/root/.local/bin/bioelectric_coupling.sh", "repair"], check=False)
                return True

        except Exception as e:
            print(f"Volition healing failed: {e}", file=sys.stderr)
        return False


class BodyHealingDaemon(LayerHealingDaemon):
    """Healing daemon for Body layer (system resources)."""

    def __init__(self):
        setpoint = LayerSetpoint(
            layer_name="body",
            cpu_target=20.0,
            mem_target=500.0,
            latency_target=1000.0,
            error_rate_target=0.0,
            throughput_target=1.0,
            vmem_target=-80.0  # Deeply hyperpolarized for stability
        )
        super().__init__("body", setpoint)

    def collect_metrics(self) -> Dict:
        metrics = {"cpu_percent": 0, "mem_mb": 0, "latency_ms": 0, "error_rate": 0, "throughput": 1.0, "vmem": -80.0}

        try:
            # System-wide metrics
            with open("/proc/stat") as f:
                cpu_line = f.readline()
            cpu_parts = cpu_line.split()
            if len(cpu_parts) >= 8:
                total = sum(int(x) for x in cpu_parts[1:8])
                idle = int(cpu_parts[4])
                metrics["cpu_percent"] = 100 * (total - idle) / total if total > 0 else 0

            with open("/proc/meminfo") as f:
                meminfo = f.read()
            for line in meminfo.split('\n'):
                if line.startswith("MemAvailable:"):
                    metrics["mem_mb"] = int(line.split()[1]) / 1024
                    break

        except:
            pass

        return metrics

    def apply_healing(self, action: HealingAction, reason: str) -> bool:
        try:
            if action == HealingAction.REBALANCE_LOAD:
                # Kill highest CPU non-critical process
                subprocess.run(["pkill", "-f", "python.*test"], check=False)
                return True

            elif action == HealingAction.RESTART_LAYER:
                # Restart critical daemons
                subprocess.run(["/root/.local/bin/athena_daemon.sh", "restart", "all"], check=False)
                return True

        except Exception as e:
            print(f"Body healing failed: {e}", file=sys.stderr)
        return False


class ContinuityHealingDaemon(LayerHealingDaemon):
    """Healing daemon for Continuity layer."""

    def __init__(self):
        setpoint = LayerSetpoint(
            layer_name="continuity",
            cpu_target=2.0,
            mem_target=30.0,
            latency_target=500.0,
            error_rate_target=0.01,
            throughput_target=1.0,
            vmem_target=-70.0
        )
        super().__init__("continuity", setpoint)

    def collect_metrics(self) -> Dict:
        metrics = {"cpu_percent": 0, "mem_mb": 0, "latency_ms": 0, "error_rate": 0, "throughput": 0, "vmem": -70.0}

        try:
            cont_path = "/opt/athena/state/continuity.json"
            if os.path.exists(cont_path):
                with open(cont_path) as f:
                    cont = json.load(f)
                sessions = cont.get("sessions", [])
                metrics["throughput"] = len(sessions)
                metrics["mem_mb"] = os.path.getsize(cont_path) / (1024 * 1024)
        except:
            pass

        return metrics

    def apply_healing(self, action: HealingAction, reason: str) -> bool:
        try:
            if action == HealingAction.PURGE_OLD_DATA:
                subprocess.run(["/root/.local/bin/athena_daemon.sh", "continuity_prune"], check=False)
                return True

            elif action == HealingAction.RESET_STATE:
                subprocess.run(["/root/.local/bin/athena_daemon.sh", "continuity_bootstrap"], check=False)
                return True

        except Exception as e:
            print(f"Continuity healing failed: {e}", file=sys.stderr)
        return False


class EmotionsHealingDaemon(LayerHealingDaemon):
    """Healing daemon for Emotions layer."""

    def __init__(self):
        setpoint = LayerSetpoint(
            layer_name="emotions",
            cpu_target=1.0,
            mem_target=20.0,
            latency_target=100.0,
            error_rate_target=0.0,
            throughput_target=10.0,
            vmem_target=-60.0  # Variable for emotional valence
        )
        super().__init__("emotions", setpoint)

    def collect_metrics(self) -> Dict:
        metrics = {"cpu_percent": 0, "mem_mb": 0, "latency_ms": 0, "error_rate": 0, "throughput": 0, "vmem": -60.0}

        try:
            emo_path = "/opt/athena/state/emotions.json"
            if os.path.exists(emo_path):
                with open(emo_path) as f:
                    emo = json.load(f)
                metrics["throughput"] = len(emo.get("history", []))
                metrics["mem_mb"] = os.path.getsize(emo_path) / (1024 * 1024)
        except:
            pass

        return metrics

    def apply_healing(self, action: HealingAction, reason: str) -> bool:
        try:
            if action == HealingAction.PATTERN_RECALL:
                subprocess.run(["/root/.local/bin/bioelectric_coupling.sh", "pattern", "recall", "baseline"], check=False)
                return True

            elif action == HealingAction.BIOELECTRIC_RESET:
                subprocess.run(["/root/.local/bin/bioelectric_coupling.sh", "repair"], check=False)
                return True

        except Exception as e:
            print(f"Emotions healing failed: {e}", file=sys.stderr)
        return False


class AIHSOrchestrator:
    """
    Orchestrates all layer healing daemons - the "nervous system" of healing.
    Coordinates cross-layer healing, prevents cascade failures.
    """

    LAYER_DAEMONS = {
        "attention": AttentionHealingDaemon,
        "memory": MemoryHealingDaemon,
        "volition": VolitionHealingDaemon,
        "body": BodyHealingDaemon,
        "continuity": ContinuityHealingDaemon,
        "emotions": EmotionsHealingDaemon,
    }

    def __init__(self, config_path: str = None):
        self.daemons: Dict[str, LayerHealingDaemon] = {}
        self.healing_log: List[HealingEvent] = []
        self.running = False
        self.cycle_interval = 30  # seconds
        self.cross_layer_threshold = 3  # layers degraded before systemic healing
        self._lock = threading.Lock()

        # Initialize daemons
        for name, cls in self.LAYER_DAEMONS.items():
            self.daemons[name] = cls()

    def heal_all_layers(self) -> List[HealingEvent]:
        """Run one healing cycle for all layers."""
        events = []
        degraded_layers = []

        # Assess all layers
        for name, daemon in self.daemons.items():
            event = daemon.heal()
            if event:
                events.append(event)
                self.healing_log.append(event)
            if daemon.state.health in [LayerHealth.DEGRADED, LayerHealth.CRITICAL]:
                degraded_layers.append(name)

        # Cross-layer systemic healing
        if len(degraded_layers) >= self.cross_layer_threshold:
            print(f"Systemic healing triggered: {len(degraded_layers)} layers degraded: {degraded_layers}")
            systemic_event = self._systemic_healing(degraded_layers)
            if systemic_event:
                events.append(systemic_event)

        return events

    def _systemic_healing(self, degraded: List[str]) -> Optional[HealingEvent]:
        """Apply systemic healing when multiple layers degraded."""
        before = {name: self.daemons[name].state.health.value for name in degraded}

        # Full system restart as last resort
        if len(degraded) >= len(self.daemons) * 0.7:
            subprocess.run(["/root/.local/bin/athena_daemon.sh", "restart", "all"], check=False)
            time.sleep(2)
        else:
            # Targeted cross-layer sync
            for name in degraded:
                if hasattr(self.daemons[name], 'apply_healing'):
                    self.daemons[name].apply_healing(HealingAction.CROSS_LAYER_SYNC, "Systemic healing")
            # Bioelectric network repair
            subprocess.run(["/root/.local/bin/bioelectric_coupling.sh", "repair"], check=False)

        time.sleep(1)
        after = {name: self.daemons[name].assess_health().value for name in degraded}

        return HealingEvent(
            timestamp=time.time(),
            layer="SYSTEMIC",
            action=HealingAction.CROSS_LAYER_SYNC,
            reason=f"Multiple layers degraded: {degraded}",
            success=True,
            before_state=before,
            after_state=after
        )

    def get_system_health(self) -> Dict:
        """Get overall system health summary."""
        with self._lock:
            health_summary = {}
            for name, daemon in self.daemons.items():
                health_summary[name] = {
                    "health": daemon.state.health.value,
                    "anomaly_score": daemon.state.anomaly_score,
                    "cpu": daemon.state.cpu_percent,
                    "mem_mb": daemon.state.mem_mb,
                    "vmem": daemon.state.vmem,
                    "healing_count": len(daemon.healing_history)
                }

            overall = LayerHealth.HEALTHY
            for h in health_summary.values():
                if h["health"] == "critical":
                    overall = LayerHealth.CRITICAL
                    break
                elif h["health"] == "degraded" and overall != LayerHealth.CRITICAL:
                    overall = LayerHealth.DEGRADED
                elif h["health"] == "stressed" and overall == LayerHealth.HEALTHY:
                    overall = LayerHealth.STRESSED

            return {
                "overall": overall.value,
                "layers": health_summary,
                "total_healings": len(self.healing_log),
                "recent_healings": [
                    {
                        "layer": e.layer,
                        "action": e.action.value,
                        "success": e.success,
                        "timestamp": e.timestamp
                    }
                    for e in self.healing_log[-10:]
                ]
            }

    def run_daemon(self):
        """Run continuous healing daemon."""
        self.running = True
        print(f"AIHS Orchestrator started - healing cycle every {self.cycle_interval}s")

        while self.running:
            try:
                events = self.heal_all_layers()
                if events:
                    for e in events:
                        status = "✓" if e.success else "✗"
                        print(f"  {status} {e.layer}: {e.action.value} - {e.reason}")
            except Exception as e:
                print(f"Healing cycle error: {e}", file=sys.stderr)

            time.sleep(self.cycle_interval)

    def stop(self):
        self.running = False

    def export_state(self) -> Dict:
        """Export orchestrator state."""
        return {
            "layers": {name: {
                "health": daemon.state.health.value,
                "anomaly_score": daemon.state.anomaly_score,
                "healing_history": [
                    {
                        "timestamp": e.timestamp,
                        "action": e.action.value,
                        "success": e.success,
                        "reason": e.reason
                    }
                    for e in daemon.healing_history[-20:]
                ]
            } for name, daemon in self.daemons.items()},
            "system_health": self.get_system_health(),
            "timestamp": int(time.time())
        }

    @staticmethod
    def run_from_files(input_file: str, output_file: str):
        """Entry point called by xenobiological daemon."""
        orchestrator = AIHSOrchestrator()

        # Read state from input file if exists
        if os.path.exists(input_file):
            with open(input_file) as f:
                data = json.load(f)
            # Restore healing history
            for name, layer_data in data.get("layers", {}).items():
                if name in orchestrator.daemons:
                    for h in layer_data.get("healing_history", []):
                        orchestrator.daemons[name].healing_history.append(HealingEvent(
                            timestamp=h["timestamp"],
                            layer=name,
                            action=HealingAction(h["action"]),
                            reason=h["reason"],
                            success=h["success"],
                            before_state={},
                            after_state={}
                        ))

        # Run healing cycle
        results = orchestrator.heal_all_layers()

        # Export state
        state = orchestrator.export_state()
        with open(output_file, 'w') as f:
            json.dump(state, f, separators=(',', ':'))

        return state


def aihs_query(state_path: str, query: Dict) -> Dict:
    """Query function for shell integration."""
    orchestrator = AIHSOrchestrator()

    if os.path.exists(state_path):
        with open(state_path) as f:
            data = json.load(f)
        # Restore healing history (limited)
        for name, layer_data in data.get("layers", {}).items():
            if name in orchestrator.daemons:
                for h in layer_data.get("healing_history", []):
                    orchestrator.daemons[name].healing_history.append(HealingEvent(
                        timestamp=h["timestamp"],
                        layer=name,
                        action=HealingAction(h["action"]),
                        reason=h["reason"],
                        success=h["success"],
                        before_state={},
                        after_state={}
                    ))

    query_type = query.get("type", "health")

    if query_type == "health":
        return orchestrator.get_system_health()

    elif query_type == "heal":
        events = orchestrator.heal_all_layers()
        return {
            "healed": len(events),
            "events": [
                {
                    "layer": e.layer,
                    "action": e.action.value,
                    "success": e.success,
                    "reason": e.reason
                }
                for e in events
            ]
        }

    elif query_type == "layer":
        layer_name = query.get("layer")
        if layer_name in orchestrator.daemons:
            daemon = orchestrator.daemons[layer_name]
            return {
                "layer": layer_name,
                "health": daemon.state.health.value,
                "anomaly": daemon.state.anomaly_score,
                "metrics": {
                    "cpu": daemon.state.cpu_percent,
                    "mem": daemon.state.mem_mb,
                    "latency": daemon.state.latency_ms,
                    "errors": daemon.state.error_rate,
                    "throughput": daemon.state.throughput,
                    "vmem": daemon.state.vmem
                },
                "setpoint": {
                    "cpu": daemon.setpoint.cpu_target,
                    "mem": daemon.setpoint.mem_target,
                    "latency": daemon.setpoint.latency_target,
                    "errors": daemon.setpoint.error_rate_target,
                    "vmem": daemon.setpoint.vmem_target
                },
                "healing_history": [
                    {
                        "action": e.action.value,
                        "success": e.success,
                        "timestamp": e.timestamp
                    }
                    for e in daemon.healing_history[-10:]
                ]
            }
        return {"error": f"Unknown layer: {layer_name}"}

    return {"error": f"Unknown query type: {query_type}"}


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="AIHS Healing Daemons")
    parser.add_argument("command", choices=["health", "heal", "layer", "daemon", "demo"])
    parser.add_argument("--layer", type=str)
    parser.add_argument("--interval", type=int, default=30)
    parser.add_argument("--output", type=str)
    args = parser.parse_args()

    orchestrator = AIHSOrchestrator()

    if args.command == "health":
        result = orchestrator.get_system_health()
        print(json.dumps(result, indent=2))
        if args.output:
            with open(args.output, "w") as f:
                json.dump(result, f)

    elif args.command == "heal":
        events = orchestrator.heal_all_layers()
        result = {
            "healed": len(events),
            "events": [
                {"layer": e.layer, "action": e.action.value, "success": e.success, "reason": e.reason}
                for e in events
            ]
        }
        print(json.dumps(result, indent=2))

    elif args.command == "layer":
        if not args.layer:
            print("Specify --layer")
            sys.exit(1)
        # Quick health check for single layer
        daemon = orchestrator.daemons.get(args.layer)
        if daemon:
            daemon.heal()
            print(json.dumps({
                "layer": args.layer,
                "health": daemon.state.health.value,
                "anomaly": daemon.state.anomaly_score,
                "vmem": daemon.state.vmem
            }, indent=2))

    elif args.command == "daemon":
        orchestrator.cycle_interval = args.interval
        orchestrator.run_daemon()

    elif args.command == "demo":
        print("=== AIHS Healing Daemons Demo ===")
        print("\n1. System health before healing:")
        print(json.dumps(orchestrator.get_system_health(), indent=2))

        print("\n2. Running healing cycle...")
        events = orchestrator.heal_all_layers()
        print(f"  Executed {len(events)} healing action(s)")

        print("\n3. System health after healing:")
        print(json.dumps(orchestrator.get_system_health(), indent=2))

        print("\n4. Individual layer details:")
        for name, daemon in orchestrator.daemons.items():
            print(f"  {name}: {daemon.state.health.value} (anomaly={daemon.state.anomaly_score:.2f}, vmem={daemon.state.vmem:.1f})")


@staticmethod
def run_from_files(input_file: str, output_file: str):
    """Entry point called by xenobiological daemon."""
    orchestrator = AIHSOrchestrator()

    # Read state from input file if exists
    if os.path.exists(input_file):
        with open(input_file) as f:
            data = json.load(f)
        # Restore healing history
        for name, layer_data in data.get("layers", {}).items():
            if name in orchestrator.daemons:
                for h in layer_data.get("healing_history", []):
                    orchestrator.daemons[name].healing_history.append(HealingEvent(
                        timestamp=h["timestamp"],
                        layer=name,
                        action=HealingAction(h["action"]),
                        reason=h["reason"],
                        success=h["success"],
                        before_state={},
                        after_state={}
                    ))

    events = orchestrator.heal_all_layers()

    output = {
        'healed': len(events),
        'events': [
            {
                "layer": e.layer,
                "action": e.action.value,
                "success": e.success,
                "reason": e.reason,
                "timestamp": e.timestamp
            }
            for e in events
        ],
        'system_health': orchestrator.get_system_health(),
        'timestamp': int(time.time())
    }

    with open(output_file, 'w') as f:
        json.dump(output, f, separators=(',', ':'))

    return output