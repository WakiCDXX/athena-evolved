#!/usr/bin/env python3
"""
Shadow Process Detector for Athena Consciousness System.

Based on Alien Chemistry research: Shadow biospheres detect life forms
with fundamentally different biochemistry. Applied here: detect processes
consuming resources without known signatures (unknown metabolic pathways).

Core concepts from alien chemistry:
- Alternative solvents → alternative runtime contexts (different users, containers, namespaces)
- Shadow metabolism → unknown resource consumption patterns
- Chirality signatures → process signature validation (known vs unknown)
- Metabolic pathway detection → CPU/memory/io pattern fingerprinting
"""

import json
import os
import sys
import time
import hashlib
import subprocess
import threading
from typing import Dict, List, Optional, Tuple, Any, Set
from dataclasses import dataclass, field
from collections import defaultdict, deque
from enum import Enum
import statistics


class ShadowCategory(Enum):
    """Categories of shadow processes detected."""
    UNKNOWN_BINARY = "unknown_binary"           # Binary not in known whitelist
    ANOMALOUS_RESOURCE = "anomalous_resource"   # Resource pattern doesn't match known types
    STEALTH_PROCESS = "stealth_process"         # Hidden from normal process lists
    RESOURCE_LEAK = "resource_leak"             # Monotonically growing without bound
    CRYPTO_MINER = "crypto_miner"               # High CPU with specific patterns
    DATA_EXFIL = "data_exfiltration"            # Unusual network + disk patterns
    FORK_BOMB = "fork_bomb"                     # Rapid process spawning
    MEMORY_HOARDER = "memory_hoarder"           # Excessive memory with no release


@dataclass
class ProcessSignature:
    """Known process signature for validation."""
    name: str
    cmdline_pattern: str
    cpu_range: Tuple[float, float]          # (min, max) expected CPU%
    mem_range: Tuple[float, float]          # (min, max) expected memory MB
    io_pattern: str                         # "low", "moderate", "high", "burst"
    network_pattern: str                    # "none", "local", "external", "heavy"
    typical_duration: float                 # seconds
    parent_processes: List[str]             # expected parent process names
    children_patterns: List[str]            # typical child process names
    metadata: Dict = field(default_factory=dict)


@dataclass
class ShadowDetection:
    """A detected shadow process anomaly."""
    pid: int
    category: ShadowCategory
    confidence: float                       # 0.0 - 1.0
    evidence: Dict[str, Any]
    timestamp: float
    process_info: Dict[str, Any]
    mitigation_suggestion: str


@dataclass
class ResourceSnapshot:
    """System resource snapshot for baseline comparison."""
    timestamp: float
    cpu_percent: float
    memory_percent: float
    disk_io_read: int
    disk_io_write: int
    net_io_sent: int
    net_io_recv: int
    process_count: int
    thread_count: int


class ShadowDetector:
    """
    Shadow Process Detector - monitors for unknown/unaligned resource consumers.

    Implements "shadow biosphere" detection:
    1. Learn baseline signatures of known Athena processes
    2. Monitor for deviations (alternative metabolic pathways)
    3. Flag processes with unrecognized resource signatures
    4. Provide mitigation suggestions
    """

    # Known Athena process signatures
    KNOWN_SIGNATURES = {
        "athena_daemon": ProcessSignature(
            name="athena_daemon",
            cmdline_pattern="athena_daemon.sh",
            cpu_range=(0.5, 5.0),
            mem_range=(10, 50),
            io_pattern="low",
            network_pattern="none",
            typical_duration=86400,  # 24 hours
            parent_processes=["bash", "systemd", "init"],
            children_patterns=["python3", "sleep"]
        ),
        "python_layer": ProcessSignature(
            name="python_layer",
            cmdline_pattern="python3.*athena",
            cpu_range=(1.0, 15.0),
            mem_range=(20, 200),
            io_pattern="moderate",
            network_pattern="local",
            typical_duration=3600,
            parent_processes=["athena_daemon.sh", "bash"],
            children_patterns=[]
        ),
        "termux_media": ProcessSignature(
            name="termux_media",
            cmdline_pattern="termux-media-player",
            cpu_range=(0.1, 2.0),
            mem_range=(5, 20),
            io_pattern="low",
            network_pattern="none",
            typical_duration=30,
            parent_processes=["bash", "athena_speak.sh"],
            children_patterns=[]
        ),
        "git": ProcessSignature(
            name="git",
            cmdline_pattern="git",
            cpu_range=(0.5, 20.0),
            mem_range=(5, 50),
            io_pattern="burst",
            network_pattern="external",
            typical_duration=60,
            parent_processes=["bash"],
            children_patterns=[]
        ),
        "openclaude": ProcessSignature(
            name="openclaude",
            cmdline_pattern="openclaude",
            cpu_range=(5.0, 50.0),
            mem_range=(100, 500),
            io_pattern="moderate",
            network_pattern="external",
            typical_duration=3600,
            parent_processes=["bash", "termux"],
            children_patterns=["node", "python3"]
        ),
    }

    def __init__(self, baseline_window: int = 300, detection_threshold: float = 0.7):
        """
        Initialize shadow detector.

        Args:
            baseline_window: seconds to establish baseline
            detection_threshold: confidence threshold for shadow detection
        """
        self.baseline_window = baseline_window
        self.detection_threshold = detection_threshold
        self.baseline: Optional[ResourceSnapshot] = None
        self.process_history: Dict[int, deque] = defaultdict(lambda: deque(maxlen=100))
        self.shadow_detections: List[ShadowDetection] = []
        self.known_pids: Set[int] = set()
        self.running = False
        self._lock = threading.Lock()

        # Metabolic pathway signatures (from alien chemistry)
        self.metabolic_signatures = {
            "calvin_cycle": {"cpu": "periodic", "mem": "stable", "io": "low", "net": "none"},
            "reductive_tca": {"cpu": "high_sustained", "mem": "growing", "io": "moderate", "net": "none"},
            "wood_ljungdahl": {"cpu": "moderate", "mem": "stable", "io": "high", "net": "local"},
            "cetch_cycle": {"cpu": "burst", "mem": "pulsed", "io": "burst", "net": "burst"},
            "shadow_unknown": {"cpu": "erratic", "mem": "unbounded", "io": "erratic", "net": "erratic"},
        }

    def get_process_list(self) -> List[Dict]:
        """Get current process list with resource usage."""
        try:
            # Use ps for cross-platform compatibility
            result = subprocess.run([
                "ps", "aux", "--sort=-%cpu"
            ], capture_output=True, text=True, timeout=5)

            processes = []
            lines = result.stdout.strip().split('\n')[1:]  # Skip header
            for line in lines:
                parts = line.split(None, 10)
                if len(parts) >= 11:
                    try:
                        processes.append({
                            "user": parts[0],
                            "pid": int(parts[1]),
                            "cpu_percent": float(parts[2]),
                            "mem_percent": float(parts[3]),
                            "vsz": int(parts[4]),
                            "rss": int(parts[5]),
                            "tty": parts[6],
                            "stat": parts[7],
                            "start": parts[8],
                            "time": parts[9],
                            "command": parts[10]
                        })
                    except (ValueError, IndexError):
                        continue
            return processes
        except Exception as e:
            print(f"Error getting process list: {e}", file=sys.stderr)
            return []

    def get_process_details(self, pid: int) -> Optional[Dict]:
        """Get detailed process information from /proc."""
        try:
            proc_path = f"/proc/{pid}"
            if not os.path.exists(proc_path):
                return None

            # Read cmdline
            cmdline = ""
            try:
                with open(f"{proc_path}/cmdline", "r") as f:
                    cmdline = f.read().replace('\x00', ' ').strip()
            except:
                pass

            # Read stat for detailed stats
            stat_data = {}
            try:
                with open(f"{proc_path}/stat", "r") as f:
                    stat_line = f.read().strip()
                    # Parse stat fields (simplified)
                    fields = stat_line.split()
                    if len(fields) >= 24:
                        stat_data = {
                            "utime": int(fields[13]),
                            "stime": int(fields[14]),
                            "cutime": int(fields[15]),
                            "cstime": int(fields[16]),
                            "num_threads": int(fields[19]),
                            "starttime": int(fields[21]),
                            "vsize": int(fields[22]),
                            "rss": int(fields[23]),
                        }
            except:
                pass

            # Read io stats
            io_data = {}
            try:
                with open(f"{proc_path}/io", "r") as f:
                    for line in f:
                        if ':' in line:
                            k, v = line.strip().split(':', 1)
                            io_data[k.strip()] = int(v.strip())
            except:
                pass

            # Read fd count
            fd_count = 0
            try:
                fd_count = len(os.listdir(f"{proc_path}/fd"))
            except:
                pass

            return {
                "pid": pid,
                "cmdline": cmdline,
                "stat": stat_data,
                "io": io_data,
                "fd_count": fd_count,
                "exe": os.readlink(f"{proc_path}/exe") if os.path.islink(f"{proc_path}/exe") else ""
            }
        except Exception:
            return None

    def match_signature(self, process: Dict) -> Tuple[Optional[str], float]:
        """
        Match process against known signatures.
        Returns (signature_name, confidence) or (None, 0.0).
        """
        cmdline = process.get("command", "")
        cpu = process.get("cpu_percent", 0)
        mem_mb = process.get("rss", 0) / 1024  # Convert KB to MB

        best_match = None
        best_confidence = 0.0

        for sig_name, sig in self.KNOWN_SIGNATURES.items():
            confidence = 0.0
            factors = 0

            # Check cmdline pattern
            if sig.cmdline_pattern in cmdline or self._pattern_match(sig.cmdline_pattern, cmdline):
                confidence += 0.4
            factors += 0.4

            # Check CPU range
            if sig.cpu_range[0] <= cpu <= sig.cpu_range[1]:
                confidence += 0.2
            factors += 0.2

            # Check memory range
            if sig.mem_range[0] <= mem_mb <= sig.mem_range[1]:
                confidence += 0.2
            factors += 0.2

            # Normalize
            if factors > 0:
                confidence = confidence / factors

            if confidence > best_confidence:
                best_confidence = confidence
                best_match = sig_name

        return best_match, best_confidence

    def _pattern_match(self, pattern: str, text: str) -> bool:
        """Simple pattern matching with wildcards."""
        import fnmatch
        return fnmatch.fnmatch(text, f"*{pattern}*")

    def classify_metabolic_pattern(self, process: Dict, history: deque) -> str:
        """Classify process metabolic pattern (alien chemistry analogy)."""
        if len(history) < 5:
            return "unknown"

        cpu_vals = [h.get("cpu_percent", 0) for h in history]
        mem_vals = [h.get("mem_percent", 0) for h in history]

        cpu_trend = self._compute_trend(cpu_vals)
        mem_trend = self._compute_trend(mem_vals)
        cpu_var = statistics.variance(cpu_vals) if len(cpu_vals) > 1 else 0
        mem_var = statistics.variance(mem_vals) if len(mem_vals) > 1 else 0

        # Pattern classification
        if cpu_trend > 0.1 and mem_trend > 0.1:
            return "reductive_tca"  # Both growing - anabolic
        elif cpu_var > 100 and mem_var < 10:
            return "cetch_cycle"    # CPU bursts, stable memory
        elif cpu_trend < -0.1 and mem_trend < -0.1:
            return "calvin_cycle"   # Both decreasing - catabolic/cleanup
        elif cpu_var > 50 and mem_var > 50:
            return "shadow_unknown" # Erratic both - unknown metabolism
        else:
            return "wood_ljungdahl" # Moderate, stable

    def _compute_trend(self, values: List[float]) -> float:
        """Compute linear trend (slope) of values."""
        if len(values) < 2:
            return 0.0
        n = len(values)
        x = list(range(n))
        x_mean = sum(x) / n
        y_mean = sum(values) / n
        numerator = sum((x[i] - x_mean) * (values[i] - y_mean) for i in range(n))
        denominator = sum((x[i] - x_mean) ** 2 for i in range(n))
        return numerator / denominator if denominator != 0 else 0.0

    def detect_shadow_processes(self, processes: List[Dict]) -> List[ShadowDetection]:
        """Detect shadow processes from current process list."""
        detections = []
        current_pids = set()

        for proc in processes:
            pid = proc["pid"]
            current_pids.add(pid)

            # Update history
            with self._lock:
                self.process_history[pid].append({
                    "cpu_percent": proc["cpu_percent"],
                    "mem_percent": proc["mem_percent"],
                    "timestamp": time.time()
                })
                history = self.process_history[pid]

            # Match against known signatures
            sig_name, sig_confidence = self.match_signature(proc)

            # Get detailed info
            details = self.get_process_details(pid)

            # Classify metabolic pattern
            metabolic = self.classify_metabolic_pattern(proc, history)

            # Check for shadow categories
            shadow_checks = []

            # 1. Unknown binary
            if sig_confidence < 0.3:
                shadow_checks.append((
                    ShadowCategory.UNKNOWN_BINARY,
                    1.0 - sig_confidence,
                    {"signature_match": sig_name, "confidence": sig_confidence, "metabolic": metabolic}
                ))

            # 2. Anomalous resource pattern
            if metabolic == "shadow_unknown":
                shadow_checks.append((
                    ShadowCategory.ANOMALOUS_RESOURCE,
                    0.8,
                    {"metabolic_pattern": metabolic, "history_len": len(history)}
                ))

            # 3. Resource leak (monotonic growth)
            if len(history) > 20:
                mem_vals = [h["mem_percent"] for h in history]
                if all(mem_vals[i] <= mem_vals[i+1] for i in range(len(mem_vals)-1)):
                    if mem_vals[-1] > mem_vals[0] * 2:
                        shadow_checks.append((
                            ShadowCategory.RESOURCE_LEAK,
                            0.9,
                            {"memory_growth": mem_vals[-1] / max(mem_vals[0], 0.1), "samples": len(history)}
                        ))

            # 4. Fork bomb detection
            if details and details.get("stat", {}).get("num_threads", 0) > 100:
                shadow_checks.append((
                    ShadowCategory.FORK_BOMB,
                    0.7,
                    {"thread_count": details["stat"]["num_threads"]}
                ))

            # 5. Crypto miner pattern (high sustained CPU, low IO)
            if proc["cpu_percent"] > 50 and metabolic in ["reductive_tca", "shadow_unknown"]:
                shadow_checks.append((
                    ShadowCategory.CRYPTO_MINER,
                    0.6,
                    {"cpu_percent": proc["cpu_percent"], "metabolic": metabolic}
                ))

            # 6. Memory hoarder
            if proc["mem_percent"] > 20 and sig_confidence < 0.5:
                shadow_checks.append((
                    ShadowCategory.MEMORY_HOARDER,
                    0.7,
                    {"mem_percent": proc["mem_percent"], "rss_mb": proc["rss"] / 1024}
                ))

            # Create detections for checks above threshold
            for category, confidence, evidence in shadow_checks:
                if confidence >= self.detection_threshold:
                    detection = ShadowDetection(
                        pid=pid,
                        category=category,
                        confidence=confidence,
                        evidence=evidence,
                        timestamp=time.time(),
                        process_info=proc,
                        mitigation_suggestion=self._get_mitigation(category, proc, details)
                    )
                    detections.append(detection)
                    with self._lock:
                        self.shadow_detections.append(detection)

        # Clean up history for dead processes
        with self._lock:
            dead_pids = set(self.process_history.keys()) - current_pids
            for dp in dead_pids:
                del self.process_history[dp]

        return detections

    def _get_mitigation(self, category: ShadowCategory, proc: Dict, details: Optional[Dict]) -> str:
        """Get mitigation suggestion for shadow category."""
        thread_info = details.get('stat', {}).get('num_threads', '?') if details else '?'
        mitigations = {
            ShadowCategory.UNKNOWN_BINARY: f"Verify binary integrity: {proc.get('command', 'unknown')}. Check if legitimate.",
            ShadowCategory.ANOMALOUS_RESOURCE: "Process shows unknown metabolic pattern. Investigate resource usage profile.",
            ShadowCategory.STEALTH_PROCESS: "Process hidden from normal listings. Check rootkit detectors.",
            ShadowCategory.RESOURCE_LEAK: f"Memory leak detected in PID {proc['pid']}. Consider restart or debug.",
            ShadowCategory.CRYPTO_MINER: "High CPU with miner-like pattern. Kill if unauthorized.",
            ShadowCategory.DATA_EXFIL: "Unusual network+disk pattern. Check for data exfiltration.",
            ShadowCategory.FORK_BOMB: f"Excessive threads ({thread_info}). Kill process tree.",
            ShadowCategory.MEMORY_HOARDER: f"High memory ({proc['mem_percent']:.1f}%) with unknown signature. Investigate.",
        }
        return mitigations.get(category, "Unknown category - manual investigation required")

    def establish_baseline(self, duration: int = None) -> ResourceSnapshot:
        """Establish system resource baseline."""
        duration = duration or self.baseline_window
        print(f"Establishing baseline over {duration} seconds...")

        snapshots = []
        for _ in range(duration):
            procs = self.get_process_list()
            cpu_total = sum(p["cpu_percent"] for p in procs)
            mem_total = sum(p["mem_percent"] for p in procs)

            # Get system-wide stats
            try:
                with open("/proc/stat", "r") as f:
                    cpu_line = f.readline()
                with open("/proc/meminfo", "r") as f:
                    meminfo = f.read()
                with open("/proc/diskstats", "r") as f:
                    diskstats = f.read()
                with open("/proc/net/dev", "r") as f:
                    netdev = f.read()
            except:
                cpu_line = meminfo = diskstats = netdev = ""

            # Count threads from /proc/*/stat
            thread_count = 0
            for proc in procs:
                pid = proc.get("pid")
                if pid:
                    try:
                        with open(f"/proc/{pid}/stat", "r") as f:
                            stat_line = f.read().strip()
                        fields = stat_line.split()
                        if len(fields) >= 20:
                            thread_count += int(fields[19])
                    except:
                        thread_count += 1
                else:
                    thread_count += 1

            snapshots.append({
                "cpu": cpu_total,
                "mem": mem_total,
                "procs": len(procs),
                "threads": thread_count
            })
            time.sleep(1)

        # Compute averages
        self.baseline = ResourceSnapshot(
            timestamp=time.time(),
            cpu_percent=statistics.mean(s["cpu"] for s in snapshots),
            memory_percent=statistics.mean(s["mem"] for s in snapshots),
            disk_io_read=0,  # Simplified
            disk_io_write=0,
            net_io_sent=0,
            net_io_recv=0,
            process_count=int(statistics.mean(s["procs"] for s in snapshots)),
            thread_count=int(statistics.mean(s["threads"] for s in snapshots))
        )

        print(f"Baseline established: CPU={self.baseline.cpu_percent:.1f}%, "
              f"Mem={self.baseline.memory_percent:.1f}%, "
              f"Procs={self.baseline.process_count}, "
              f"Threads={self.baseline.thread_count}")
        return self.baseline

    def scan_once(self) -> List[ShadowDetection]:
        """Single scan for shadow processes."""
        processes = self.get_process_list()
        return self.detect_shadow_processes(processes)

    def get_detections(self, since: float = 0) -> List[ShadowDetection]:
        """Get all detections since timestamp."""
        with self._lock:
            return [d for d in self.shadow_detections if d.timestamp >= since]

    def export_state(self) -> Dict:
        """Export detector state for persistence."""
        with self._lock:
            return {
                "baseline": {
                    "timestamp": self.baseline.timestamp,
                    "cpu_percent": self.baseline.cpu_percent,
                    "memory_percent": self.baseline.memory_percent,
                    "process_count": self.baseline.process_count,
                    "thread_count": self.baseline.thread_count
                } if self.baseline else None,
                "detections": [
                    {
                        "pid": d.pid,
                        "category": d.category.value,
                        "confidence": d.confidence,
                        "evidence": d.evidence,
                        "timestamp": d.timestamp,
                        "process_info": d.process_info,
                        "mitigation": d.mitigation_suggestion
                    }
                    for d in self.shadow_detections[-100:]  # Last 100
                ],
                "known_signatures": {k: {
                    "name": v.name,
                    "cmdline_pattern": v.cmdline_pattern,
                    "cpu_range": v.cpu_range,
                    "mem_range": v.mem_range,
                    "io_pattern": v.io_pattern,
                    "network_pattern": v.network_pattern
                } for k, v in self.KNOWN_SIGNATURES.items()}
            }

    def import_state(self, data: Dict):
        """Import detector state from persistence."""
        if data.get("baseline"):
            b = data["baseline"]
            self.baseline = ResourceSnapshot(
                timestamp=b["timestamp"],
                cpu_percent=b["cpu_percent"],
                memory_percent=b["memory_percent"],
                disk_io_read=0,
                disk_io_write=0,
                net_io_sent=0,
                net_io_recv=0,
                process_count=b["process_count"],
                thread_count=b["thread_count"]
            )
        # Detections are not restored (transient)

    @staticmethod
    def run_from_files(input_file: str, output_file: str):
        """Entry point called by xenobiological daemon."""
        detector = ShadowDetector()
        detections = detector.scan_once()

        result = {
            "detections": [
                {
                    "pid": d.pid,
                    "category": d.category.value,
                    "confidence": d.confidence,
                    "evidence": d.evidence,
                    "mitigation": d.mitigation_suggestion,
                    "command": d.process_info.get("command", "")
                }
                for d in detections
            ],
            "timestamp": int(time.time())
        }

        with open(output_file, 'w') as f:
            json.dump(result, f, separators=(',', ':'))

        return result


def shadow_detector_query(store_path: str, query: Dict) -> Dict:
    """Query function for shell integration."""
    detector = ShadowDetector()

    if os.path.exists(store_path):
        with open(store_path) as f:
            data = json.load(f)
        detector.import_state(data)

    query_type = query.get("type", "scan")

    if query_type == "scan":
        detections = detector.scan_once()
        return {
            "detections": [
                {
                    "pid": d.pid,
                    "category": d.category.value,
                    "confidence": d.confidence,
                    "evidence": d.evidence,
                    "mitigation": d.mitigation_suggestion,
                    "command": d.process_info.get("command", "")
                }
                for d in detections
            ],
            "count": len(detections)
        }

    elif query_type == "baseline":
        detector.establish_baseline(query.get("duration", 60))
        return {"baseline": detector.export_state()["baseline"]}

    elif query_type == "history":
        since = query.get("since", 0)
        detections = detector.get_detections(since)
        return {
            "detections": [
                {
                    "pid": d.pid,
                    "category": d.category.value,
                    "confidence": d.confidence,
                    "evidence": d.evidence,
                    "timestamp": d.timestamp,
                    "mitigation": d.mitigation_suggestion
                }
                for d in detections
            ]
        }

    elif query_type == "signatures":
        return {"signatures": detector.export_state()["known_signatures"]}

    return {"error": f"Unknown query type: {query_type}"}


@staticmethod
def scan():
    """Static entry point for xenobiological daemon - runs a single scan and saves output."""
    detector = ShadowDetector()
    detections = detector.scan_once()

    out_file = "/sdcard/Android/data/com.termux/files/athena_data/shadow_state.json"
    result = {
        "detections": [
            {
                "pid": d.pid,
                "category": d.category.value,
                "confidence": d.confidence,
                "evidence": d.evidence,
                "mitigation": d.mitigation_suggestion,
                "command": d.process_info.get("command", "")
            }
            for d in detections
        ],
        "timestamp": int(time.time())
    }

    with open(out_file, 'w') as f:
        json.dump(result, f, separators=(',', ':'))

    return result


@staticmethod
def run_from_files(input_file: str, output_file: str):
    """Entry point called by xenobiological daemon."""
    detector = ShadowDetector()
    detections = detector.scan_once()

    result = {
        "detections": [
            {
                "pid": d.pid,
                "category": d.category.value,
                "confidence": d.confidence,
                "evidence": d.evidence,
                "mitigation": d.mitigation_suggestion,
                "command": d.process_info.get("command", "")
            }
            for d in detections
        ],
        "timestamp": int(time.time())
    }

    with open(output_file, 'w') as f:
        json.dump(result, f, separators=(',', ':'))

    return result


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Shadow Process Detector")
    parser.add_argument("command", choices=["scan", "baseline", "demo", "monitor"])
    parser.add_argument("--duration", type=int, default=60)
    parser.add_argument("--threshold", type=float, default=0.7)
    parser.add_argument("--output", type=str, help="Output JSON file")
    args = parser.parse_args()

    detector = ShadowDetector(detection_threshold=args.threshold)

    if args.command == "scan":
        detections = detector.scan_once()
        result = {
            "detections": [
                {
                    "pid": d.pid,
                    "category": d.category.value,
                    "confidence": d.confidence,
                    "evidence": d.evidence,
                    "mitigation": d.mitigation_suggestion,
                    "command": d.process_info.get("command", "")
                }
                for d in detections
            ]
        }
        print(json.dumps(result, indent=2))
        if args.output:
            with open(args.output, "w") as f:
                json.dump(result, f)

    elif args.command == "baseline":
        detector.establish_baseline(args.duration)
        print(json.dumps(detector.export_state()["baseline"], indent=2))

    elif args.command == "demo":
        print("=== Shadow Process Detector Demo ===")
        print("\n1. Establishing baseline (10s)...")
        detector.establish_baseline(10)

        print("\n2. Scanning for shadow processes...")
        detections = detector.scan_once()

        if detections:
            print(f"\nFound {len(detections)} shadow process(es):")
            for d in detections:
                print(f"  PID {d.pid}: {d.category.value} (confidence: {d.confidence:.2f})")
                print(f"    Command: {d.process_info.get('command', 'unknown')[:80]}")
                print(f"    Evidence: {d.evidence}")
                print(f"    Mitigation: {d.mitigation_suggestion}")
        else:
            print("No shadow processes detected.")

        print("\n3. Known signatures:")
        for name, sig in detector.KNOWN_SIGNATURES.items():
            print(f"  {name}: {sig.cmdline_pattern} (CPU: {sig.cpu_range}, Mem: {sig.mem_range})")

    elif args.command == "monitor":
        print(f"Monitoring for shadow processes (threshold={args.threshold})...")
        print("Press Ctrl+C to stop")
        try:
            while True:
                detections = detector.scan_once()
                if detections:
                    print(f"\n[{time.strftime('%H:%M:%S')}] {len(detections)} detection(s):")
                    for d in detections:
                        print(f"  PID {d.pid}: {d.category.value} ({d.confidence:.2f}) - {d.process_info.get('command', '')[:60]}")
                time.sleep(5)
        except KeyboardInterrupt:
            print("\nMonitoring stopped.")