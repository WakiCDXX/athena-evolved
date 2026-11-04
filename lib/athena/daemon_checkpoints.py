#!/usr/bin/env python3
"""
Dual-Ledger Checkpoint System for Athena Daemon

Implements The Rouge's dual-ledger architecture:
- task_ledger.json: Mutable current state (tasks, goals, layer status)
- checkpoints.jsonl: Immutable append-only cycle history
- cycle_context.json: Evaluation output only (never mutates task ledger)
- tools.jsonl: Append-only tool call audit trail
"""

import json
import os
import sys
import time
import uuid
from pathlib import Path
from typing import Any, Dict, List, Optional
from dataclasses import dataclass, asdict, field
from datetime import datetime


@dataclass
class CheckpointEntry:
    """Immutable checkpoint entry for checkpoints.jsonl"""
    cycle_id: str
    timestamp: int
    state_snapshot: Dict[str, Any]  # Shallow copy of task_ledger at this point
    layer_results: Dict[str, Any]   # Results from this cycle's layer executions
    degradation_state: str
    session_mode: str
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass
class ToolCallEntry:
    """Append-only tool call audit trail"""
    call_id: str
    timestamp: int
    layer: str
    tool: str
    args: Dict[str, Any]
    result: Dict[str, Any]
    success: bool
    error: Optional[str] = None


class DualLedger:
    def __init__(self, data_dir: str):
        self.data_dir = Path(data_dir)
        self.data_dir.mkdir(parents=True, exist_ok=True)

        self.task_ledger_path = self.data_dir / "daemon_task_ledger.json"
        self.checkpoints_path = self.data_dir / "daemon_checkpoints.jsonl"
        self.cycle_context_path = self.data_dir / "daemon_cycle_context.json"
        self.tools_path = self.data_dir / "daemon_tools.jsonl"

        # Initialize if needed
        if not self.task_ledger_path.exists():
            self._init_task_ledger()

    def _init_task_ledger(self):
        """Initialize empty task ledger"""
        ledger = {
            "version": "1.0",
            "created": int(time.time()),
            "current_cycle_id": None,
            "state_machine_state": "SEEDING",
            "degradation_state": "normal",
            "session_mode": "event_driven",
            "layers": {},
            "active_goals": [],
            "completed_goals": [],
            "metrics": {
                "total_cycles": 0,
                "successful_cycles": 0,
                "failed_cycles": 0,
                "spin_detections": 0,
            }
        }
        self._write_json(self.task_ledger_path, ledger)

    def _write_json(self, path: Path, data: Dict):
        """Atomic write with temp file"""
        tmp = path.with_suffix(".tmp")
        with open(tmp, "w") as f:
            json.dump(data, f, separators=(",", ":"))
        tmp.replace(path)

    def _read_json(self, path: Path) -> Dict:
        if not path.exists():
            return {}
        with open(path) as f:
            return json.load(f)

    def _append_jsonl(self, path: Path, entry: Dict):
        """Append single line JSON to file"""
        with open(path, "a") as f:
            f.write(json.dumps(entry, separators=(",", ":")) + "\n")

    # ==================== TASK LEDGER (Mutable) ====================

    def get_task_ledger(self) -> Dict:
        return self._read_json(self.task_ledger_path)

    def update_task_ledger(self, updates: Dict):
        """Update task ledger with new values"""
        ledger = self.get_task_ledger()
        ledger.update(updates)
        ledger["last_updated"] = int(time.time())
        self._write_json(self.task_ledger_path, ledger)

    def set_layer_state(self, layer: str, state: Dict):
        """Update a layer's state in the ledger"""
        ledger = self.get_task_ledger()
        if "layers" not in ledger:
            ledger["layers"] = {}
        ledger["layers"][layer] = {
            **ledger["layers"].get(layer, {}),
            **state,
            "last_update": int(time.time())
        }
        self._write_json(self.task_ledger_path, ledger)

    def get_layer_state(self, layer: str) -> Dict:
        ledger = self.get_task_ledger()
        return ledger.get("layers", {}).get(layer, {})

    def add_goal(self, goal: Dict):
        """Add active goal"""
        ledger = self.get_task_ledger()
        goal["id"] = goal.get("id", str(uuid.uuid4())[:8])
        goal["created"] = int(time.time())
        goal["status"] = "active"
        ledger.setdefault("active_goals", []).append(goal)
        self._write_json(self.task_ledger_path, ledger)
        return goal["id"]

    def complete_goal(self, goal_id: str, result: Dict):
        """Move goal from active to completed"""
        ledger = self.get_task_ledger()
        active = ledger.get("active_goals", [])
        for i, g in enumerate(active):
            if g.get("id") == goal_id:
                completed = active.pop(i)
                completed["status"] = "completed"
                completed["completed_at"] = int(time.time())
                completed["result"] = result
                ledger.setdefault("completed_goals", []).append(completed)
                self._write_json(self.task_ledger_path, ledger)
                return True
        return False

    def set_state_machine_state(self, state: str):
        """Update state machine state"""
        valid_states = [
            "SEEDING", "READY", "FOUNDATION", "FOUNDATION_EVAL",
            "STORY_BUILDING", "MILESTONE_CHECK", "MILESTONE_FIX",
            "ANALYZING", "GENERATING_CHANGE_SPEC", "VISION_CHECK",
            "SHIPPING", "FINAL_REVIEW", "COMPLETE", "ESCALATION"
        ]
        if state not in valid_states:
            raise ValueError(f"Invalid state: {state}. Valid: {valid_states}")
        self.update_task_ledger({"state_machine_state": state})

    def get_state_machine_state(self) -> str:
        return self.get_task_ledger().get("state_machine_state", "SEEDING")

    # ==================== CHECKPOINTS (Immutable Append-Only) ====================

    def write_checkpoint(self,
                        cycle_id: str,
                        layer_results: Dict[str, Any],
                        degradation_state: str,
                        session_mode: str,
                        metadata: Optional[Dict] = None) -> CheckpointEntry:
        """Write immutable checkpoint"""
        ledger = self.get_task_ledger()

        entry = CheckpointEntry(
            cycle_id=cycle_id,
            timestamp=int(time.time()),
            state_snapshot={
                "state_machine_state": ledger.get("state_machine_state"),
                "degradation_state": ledger.get("degradation_state"),
                "session_mode": ledger.get("session_mode"),
                "active_goals_count": len(ledger.get("active_goals", [])),
                "completed_goals_count": len(ledger.get("completed_goals", [])),
                "layers": {k: v.get("status", "unknown") for k, v in ledger.get("layers", {}).items()},
            },
            layer_results=layer_results,
            degradation_state=degradation_state,
            session_mode=session_mode,
            metadata=metadata or {}
        )

        self._append_jsonl(self.checkpoints_path, asdict(entry))

        # Update ledger metrics
        ledger["metrics"]["total_cycles"] = ledger["metrics"].get("total_cycles", 0) + 1
        if all(r.get("success", False) for r in layer_results.values()):
            ledger["metrics"]["successful_cycles"] = ledger["metrics"].get("successful_cycles", 0) + 1
        else:
            ledger["metrics"]["failed_cycles"] = ledger["metrics"].get("failed_cycles", 0) + 1
        ledger["current_cycle_id"] = cycle_id
        self._write_json(self.task_ledger_path, ledger)

        return entry

    def get_recent_checkpoints(self, limit: int = 100) -> List[Dict]:
        """Read recent checkpoints (most recent first)"""
        if not self.checkpoints_path.exists():
            return []
        with open(self.checkpoints_path) as f:
            lines = f.readlines()
        checkpoints = [json.loads(line) for line in lines[-limit:]]
        return list(reversed(checkpoints))

    def get_checkpoint_by_cycle(self, cycle_id: str) -> Optional[Dict]:
        """Find specific checkpoint by cycle_id"""
        if not self.checkpoints_path.exists():
            return None
        with open(self.checkpoints_path) as f:
            for line in f:
                entry = json.loads(line)
                if entry.get("cycle_id") == cycle_id:
                    return entry
        return None

    # ==================== CYCLE CONTEXT (Evaluation Output Only) ====================

    def write_cycle_context(self, context: Dict):
        """Write evaluation output - NEVER mutates task ledger"""
        context["timestamp"] = int(time.time())
        context["cycle_id"] = self.get_task_ledger().get("current_cycle_id")
        self._write_json(self.cycle_context_path, context)

    def read_cycle_context(self) -> Dict:
        return self._read_json(self.cycle_context_path)

    # ==================== TOOLS AUDIT TRAIL (Append-Only) ====================

    def log_tool_call(self, layer: str, tool: str, args: Dict, result: Dict, success: bool, error: str = None):
        """Log tool call to audit trail"""
        entry = ToolCallEntry(
            call_id=str(uuid.uuid4())[:12],
            timestamp=int(time.time()),
            layer=layer,
            tool=tool,
            args=args,
            result=result,
            success=success,
            error=error
        )
        self._append_jsonl(self.tools_path, asdict(entry))

    def get_recent_tool_calls(self, limit: int = 50, layer: str = None) -> List[Dict]:
        if not self.tools_path.exists():
            return []
        with open(self.tools_path) as f:
            lines = f.readlines()
        calls = [json.loads(line) for line in lines[-limit:]]
        if layer:
            calls = [c for c in calls if c.get("layer") == layer]
        return list(reversed(calls))

    # ==================== SPIN DETECTION ====================

    def detect_spin(self, layer: str, current_result: Dict, lookback: int = 10) -> Dict:
        """
        Detect spin conditions per The Rouge:
        - 3+ consecutive cycles with zero delta (files_changed == 0)
        - Duplicate cycle_id within lookback window
        - 30min since last progress
        """
        checkpoints = self.get_recent_checkpoints(lookback)
        layer_results = [cp.get("layer_results", {}).get(layer, {}) for cp in checkpoints]

        # Check zero-delta cycles
        zero_delta_count = 0
        for r in layer_results:
            files_changed = r.get("files_changed", 0)
            if files_changed == 0:
                zero_delta_count += 1
            else:
                zero_delta_count = 0

        # Check duplicate cycle_id
        current_cycle = current_result.get("cycle_id", "")
        duplicate_cycle = any(cp.get("cycle_id") == current_cycle for cp in checkpoints)

        # Check last progress time
        last_progress = None
        for cp in reversed(checkpoints):
            lr = cp.get("layer_results", {}).get(layer, {})
            if lr.get("files_changed", 0) > 0:
                last_progress = cp.get("timestamp")
                break

        now = int(time.time())
        stale_seconds = now - last_progress if last_progress else None
        stale_30min = stale_seconds is not None and stale_seconds > 1800

        return {
            "spin_detected": zero_delta_count >= 3 or duplicate_cycle or stale_30min,
            "zero_delta_count": zero_delta_count,
            "duplicate_cycle": duplicate_cycle,
            "stale_seconds": stale_seconds,
            "stale_30min": stale_30min,
            "recommendation": "escalate" if (zero_delta_count >= 3 or duplicate_cycle or stale_30min) else "continue"
        }

    # ==================== BUDGET TRACKING ====================

    def record_cost(self, layer: str, model: str, tokens_in: int, tokens_out: int, cost_usd: float):
        """Record LLM API cost for budget tracking"""
        ledger = self.get_task_ledger()
        budget = ledger.setdefault("budget", {"total_usd": 0, "by_layer": {}, "by_model": {}})
        budget["total_usd"] = budget.get("total_usd", 0) + cost_usd
        budget["by_layer"][layer] = budget["by_layer"].get(layer, 0) + cost_usd
        budget["by_model"][model] = budget["by_model"].get(model, 0) + cost_usd
        self._write_json(self.task_ledger_path, ledger)

    def get_budget_summary(self) -> Dict:
        ledger = self.get_task_ledger()
        return ledger.get("budget", {"total_usd": 0, "by_layer": {}, "by_model": {}})

    def check_budget_cap(self, cap_usd: float) -> bool:
        """Return True if budget exceeded"""
        return self.get_budget_summary().get("total_usd", 0) > cap_usd


def main():
    """CLI interface for testing"""
    if len(sys.argv) < 2:
        print("Usage: daemon_checkpoints.py <command> [args]")
        print("Commands: init, write_checkpoint, read_ledger, read_checkpoints, detect_spin")
        sys.exit(1)

    data_dir = os.environ.get("DATA_DIR", "/opt/athena/state")
    dl = DualLedger(data_dir)
    cmd = sys.argv[1]

    if cmd == "init":
        print("Initialized dual ledger at", data_dir)

    elif cmd == "write_checkpoint":
        cycle_id = sys.argv[2] if len(sys.argv) > 2 else str(uuid.uuid4())[:8]
        layer_results = json.loads(sys.argv[3]) if len(sys.argv) > 3 else {}
        degradation = sys.argv[4] if len(sys.argv) > 4 else "normal"
        session = sys.argv[5] if len(sys.argv) > 5 else "event_driven"
        entry = dl.write_checkpoint(cycle_id, layer_results, degradation, session)
        print(f"Checkpoint written: {entry.cycle_id}")

    elif cmd == "read_ledger":
        print(json.dumps(dl.get_task_ledger(), indent=2))

    elif cmd == "read_checkpoints":
        limit = int(sys.argv[2]) if len(sys.argv) > 2 else 10
        for cp in dl.get_recent_checkpoints(limit):
            print(json.dumps(cp, indent=2))

    elif cmd == "detect_spin":
        layer = sys.argv[2]
        result = json.loads(sys.argv[3]) if len(sys.argv) > 3 else {}
        print(json.dumps(dl.detect_spin(layer, result), indent=2))

    elif cmd == "log_tool":
        layer = sys.argv[2]
        tool = sys.argv[3]
        args = json.loads(sys.argv[4]) if len(sys.argv) > 4 else {}
        result = json.loads(sys.argv[5]) if len(sys.argv) > 5 else {}
        success = sys.argv[6].lower() == "true" if len(sys.argv) > 6 else True
        error = sys.argv[7] if len(sys.argv) > 7 else None
        dl.log_tool_call(layer, tool, args, result, success, error)
        print("Tool call logged")

    else:
        print(f"Unknown command: {cmd}")


if __name__ == "__main__":
    main()