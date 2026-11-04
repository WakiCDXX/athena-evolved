#!/usr/bin/env python3
"""
Formal 16-State Machine for Athena Daemon

Based on The Rouge's Karpathy Loop state machine:
SEEDING → READY → FOUNDATION → FOUNDATION_EVAL → STORY_BUILDING →
MILESTONE_CHECK → MILESTONE_FIX → ANALYZING → GENERATING_CHANGE_SPEC →
VISION_CHECK → SHIPPING → FINAL_REVIEW → COMPLETE + ESCALATION

Integrated with dual-ledger checkpoint system for immutable history.
"""

import json
import os
import sys
import time
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass, asdict
from enum import Enum


class DaemonState(Enum):
    """16 formal states from The Rouge's V3 machine"""
    SEEDING = "SEEDING"
    READY = "READY"
    FOUNDATION = "FOUNDATION"
    FOUNDATION_EVAL = "FOUNDATION_EVAL"
    STORY_BUILDING = "STORY_BUILDING"
    MILESTONE_CHECK = "MILESTONE_CHECK"
    MILESTONE_FIX = "MILESTONE_FIX"
    ANALYZING = "ANALYZING"
    GENERATING_CHANGE_SPEC = "GENERATING_CHANGE_SPEC"
    VISION_CHECK = "VISION_CHECK"
    SHIPPING = "SHIPPING"
    FINAL_REVIEW = "FINAL_REVIEW"
    COMPLETE = "COMPLETE"
    ESCALATION = "ESCALATION"
    # Degradation overlay states (not part of main flow)
    DEGRADED_CONSERVE = "DEGRADED_CONSERVE"
    DEGRADED_MINIMAL = "DEGRADED_MINIMAL"
    DEGRADED_SUSPENDED = "DEGRADED_SUSPENDED"
    DEGRADED_SAFE_SHUTDOWN = "DEGRADED_SAFE_SHUTDOWN"


# Valid transitions (from, to) - directional
VALID_TRANSITIONS = {
    DaemonState.SEEDING: [DaemonState.READY],
    DaemonState.READY: [DaemonState.FOUNDATION, DaemonState.ESCALATION],
    DaemonState.FOUNDATION: [DaemonState.FOUNDATION_EVAL, DaemonState.ESCALATION],
    DaemonState.FOUNDATION_EVAL: [DaemonState.STORY_BUILDING, DaemonState.FOUNDATION, DaemonState.ESCALATION],
    DaemonState.STORY_BUILDING: [DaemonState.MILESTONE_CHECK, DaemonState.ESCALATION],
    DaemonState.MILESTONE_CHECK: [DaemonState.ANALYZING, DaemonState.MILESTONE_FIX, DaemonState.ESCALATION],
    DaemonState.MILESTONE_FIX: [DaemonState.MILESTONE_CHECK, DaemonState.ESCALATION],
    DaemonState.ANALYZING: [DaemonState.GENERATING_CHANGE_SPEC, DaemonState.ESCALATION],
    DaemonState.GENERATING_CHANGE_SPEC: [DaemonState.VISION_CHECK, DaemonState.ESCALATION],
    DaemonState.VISION_CHECK: [DaemonState.SHIPPING, DaemonState.ANALYZING, DaemonState.ESCALATION],
    DaemonState.SHIPPING: [DaemonState.FINAL_REVIEW, DaemonState.ESCALATION],
    DaemonState.FINAL_REVIEW: [DaemonState.COMPLETE, DaemonState.SHIPPING, DaemonState.ESCALATION],
    DaemonState.COMPLETE: [DaemonState.SEEDING, DaemonState.ESCALATION],  # Loop back for next cycle
    DaemonState.ESCALATION: [DaemonState.SEEDING, DaemonState.READY],
    # Degradation states can transition to any state based on recovery
    DaemonState.DEGRADED_CONSERVE: list(DaemonState),
    DaemonState.DEGRADED_MINIMAL: list(DaemonState),
    DaemonState.DEGRADED_SUSPENDED: [DaemonState.DEGRADED_CONSERVE, DaemonState.DEGRADED_MINIMAL, DaemonState.DEGRADED_SAFE_SHUTDOWN],
    DaemonState.DEGRADED_SAFE_SHUTDOWN: [DaemonState.DEGRADED_SUSPENDED],
}


@dataclass
class StateTransition:
    """Record of a state transition"""
    from_state: str
    to_state: str
    timestamp: int
    trigger: str
    metadata: Dict = None


class StateMachine:
    """
    Formal 16-state machine with dual-ledger integration.

    The state machine drives the daemon through a structured workflow:
    1. SEEDING - Initialize, load configs, validate environment
    2. READY - All layers healthy, awaiting trigger
    3. FOUNDATION - Build core context (senses, body, continuity)
    4. FOUNDATION_EVAL - Validate foundation quality
    5. STORY_BUILDING - Layer execution with attention/volition
    6. MILESTONE_CHECK - Evaluate cycle progress
    7. MILESTONE_FIX - Remediate if milestone failed
    8. ANALYZING - Deep introspection/doubt processing
    9. GENERATING_CHANGE_SPEC - Produce improvement proposals
    10. VISION_CHECK - Align with long-term goals
    11. SHIPPING - Apply changes, persist state
    12. FINAL_REVIEW - Verify shipped changes
    13. COMPLETE - Cycle done, ready for next
    14. ESCALATION - Human intervention needed

    Degradation overlay states modify behavior but don't replace main state.
    """

    def __init__(self, data_dir: str):
        self.data_dir = Path(data_dir)
        self.data_dir.mkdir(parents=True, exist_ok=True)

        self.state_file = self.data_dir / "daemon_state_machine.json"
        self.transitions_file = self.data_dir / "daemon_state_transitions.jsonl"

        self.current_state = self._load_state()
        self.degradation_overlay: Optional[DaemonState] = None

    def _load_state(self) -> DaemonState:
        """Load current state from file"""
        if self.state_file.exists():
            try:
                with open(self.state_file) as f:
                    data = json.load(f)
                    return DaemonState(data.get("state", "SEEDING"))
            except:
                pass
        return DaemonState.SEEDING

    def _save_state(self):
        """Save current state to file"""
        data = {
            "state": self.current_state.value,
            "degradation_overlay": self.degradation_overlay.value if self.degradation_overlay else None,
            "last_update": int(time.time())
        }
        tmp = self.state_file.with_suffix(".tmp")
        with open(tmp, "w") as f:
            json.dump(data, f, separators=(",", ":"))
        tmp.replace(self.state_file)

    def _log_transition(self, transition: StateTransition):
        """Log transition to immutable append-only file"""
        entry = asdict(transition)
        with open(self.transitions_file, "a") as f:
            f.write(json.dumps(entry, separators=(",", ":")) + "\n")

    def get_state(self) -> str:
        """Get effective state (degradation overlay takes precedence for behavior)"""
        if self.degradation_overlay:
            return f"{self.current_state.value}|{self.degradation_overlay.value}"
        return self.current_state.value

    def get_base_state(self) -> DaemonState:
        """Get the base workflow state (ignoring degradation)"""
        return self.current_state

    def set_degradation(self, degradation_state: str):
        """Set degradation overlay state"""
        # Map string to DaemonState
        mapping = {
            "normal": None,
            "conserve": DaemonState.DEGRADED_CONSERVE,
            "minimal": DaemonState.DEGRADED_MINIMAL,
            "suspended": DaemonState.DEGRADED_SUSPENDED,
            "safe_shutdown": DaemonState.DEGRADED_SAFE_SHUTDOWN
        }
        self.degradation_overlay = mapping.get(degradation_state)
        self._save_state()

    def can_transition(self, from_state: DaemonState, to_state: DaemonState) -> bool:
        """Check if transition is valid"""
        if from_state not in VALID_TRANSITIONS:
            return False
        return to_state in VALID_TRANSITIONS[from_state]

    def transition(self, to_state: DaemonState, trigger: str, metadata: Dict = None) -> bool:
        """
        Attempt state transition.
        Returns True if successful, False if invalid transition.
        """
        # Check base state transition
        if not self.can_transition(self.current_state, to_state):
            # Allow ESCALATION from anywhere
            if to_state != DaemonState.ESCALATION:
                return False

        from_state = self.current_state
        self.current_state = to_state
        self._save_state()

        # Log transition
        transition = StateTransition(
            from_state=from_state.value,
            to_state=to_state.value,
            timestamp=int(time.time()),
            trigger=trigger,
            metadata=metadata or {}
        )
        self._log_transition(transition)

        return True

    def force_transition(self, to_state: DaemonState, trigger: str, metadata: Dict = None):
        """Force transition (bypass validation) - for recovery/escalation"""
        from_state = self.current_state
        self.current_state = to_state
        self._save_state()

        transition = StateTransition(
            from_state=from_state.value,
            to_state=to_state.value,
            timestamp=int(time.time()),
            trigger=f"FORCE:{trigger}",
            metadata=metadata or {}
        )
        self._log_transition(transition)

    def get_recent_transitions(self, limit: int = 50) -> List[Dict]:
        """Get recent state transitions"""
        if not self.transitions_file.exists():
            return []
        with open(self.transitions_file) as f:
            lines = f.readlines()
        transitions = [json.loads(line) for line in lines[-limit:]]
        return list(reversed(transitions))

    def get_state_progress(self) -> Dict:
        """Get progress through the state machine"""
        state_order = list(DaemonState)
        # Only count main workflow states (not degradation)
        main_states = [s for s in state_order if not s.value.startswith("DEGRADED")]

        current_idx = main_states.index(self.current_state) if self.current_state in main_states else 0
        total = len(main_states)

        return {
            "current_state": self.current_state.value,
            "degradation_overlay": self.degradation_overlay.value if self.degradation_overlay else None,
            "effective_state": self.get_state(),
            "progress_index": current_idx,
            "progress_total": total,
            "progress_pct": round((current_idx / (total - 1)) * 100) if total > 1 else 0,
            "next_valid_states": [s.value for s in VALID_TRANSITIONS.get(self.current_state, [])]
        }

    # State-specific behavior methods
    def should_run_layer(self, layer: str) -> Tuple[bool, str]:
        """
        Determine if a layer should run in current state.
        Returns (should_run, reason)
        """
        # Degradation overlay controls layer execution
        if self.degradation_overlay == DaemonState.DEGRADED_SAFE_SHUTDOWN:
            return (False, "safe_shutdown: no layers run")
        if self.degradation_overlay == DaemonState.DEGRADED_SUSPENDED:
            # Only critical monitoring layers
            if layer in ["heartbeat", "attention", "senses"]:
                return (True, "suspended: critical monitoring only")
            return (False, "suspended: layer disabled")
        if self.degradation_overlay == DaemonState.DEGRADED_MINIMAL:
            # Light layers only
            light_layers = ["heartbeat", "attention", "senses", "body", "emotions", "continuity"]
            if layer in light_layers:
                return (True, "minimal: light layer")
            return (False, "minimal: heavy layer disabled")
        if self.degradation_overlay == DaemonState.DEGRADED_CONSERVE:
            # Skip most expensive layers
            expensive_layers = ["xenobiological_daemon", "wayfinder", "implement_spec", "tdd", "workflow_chain"]
            if layer in expensive_layers:
                return (False, "conserve: expensive layer disabled")
            return (True, "conserve: standard layer")

        # Base workflow state controls
        if self.current_state == DaemonState.SEEDING:
            return (layer in ["body", "senses", "attention"], "seeding: init layers only")
        elif self.current_state == DaemonState.READY:
            return (True, "ready: all layers run")
        elif self.current_state == DaemonState.FOUNDATION:
            return (layer in ["body", "senses", "emotions", "continuity", "attention", "heartbeat"], "foundation: core layers only")
        elif self.current_state == DaemonState.FOUNDATION_EVAL:
            return (layer in ["heartbeat", "attention"], "foundation_eval: validation only")
        elif self.current_state == DaemonState.STORY_BUILDING:
            return (layer not in ["archive", "memory_backup"], "story_building: active layers")
        elif self.current_state == DaemonState.MILESTONE_CHECK:
            return (layer in ["heartbeat", "attention", "introspection"], "milestone_check: eval layers only")
        elif self.current_state == DaemonState.MILESTONE_FIX:
            return (layer in ["doubt", "volition", "attention"], "milestone_fix: remediation layers")
        elif self.current_state == DaemonState.ANALYZING:
            return (layer in ["introspection", "doubt", "volition", "attention"], "analyzing: deep layers")
        elif self.current_state == DaemonState.GENERATING_CHANGE_SPEC:
            return (layer in ["implement_spec", "to_spec", "volition", "attention"], "generating_spec: proposal layers")
        elif self.current_state == DaemonState.VISION_CHECK:
            return (layer in ["wayfinder", "handoff", "volition", "attention"], "vision_check: alignment layers")
        elif self.current_state == DaemonState.SHIPPING:
            return (layer in ["memory", "archive", "memory_backup", "attention"], "shipping: persistence layers")
        elif self.current_state == DaemonState.FINAL_REVIEW:
            return (layer in ["heartbeat", "attention", "tdd"], "final_review: verification layers")
        elif self.current_state == DaemonState.COMPLETE:
            return (layer in ["heartbeat", "attention"], "complete: minimal monitoring")
        elif self.current_state == DaemonState.ESCALATION:
            return (layer in ["heartbeat", "attention"], "escalation: minimal monitoring")

        return (True, "default: allow")


def main():
    """CLI interface"""
    if len(sys.argv) < 2:
        print("Usage: state_machine.py <command> [args]")
        print("Commands: init, get_state, transition, set_degradation, should_run_layer, progress, history")
        sys.exit(1)

    data_dir = os.environ.get("DATA_DIR", "/opt/athena/state")
    sm = StateMachine(data_dir)
    cmd = sys.argv[1]

    if cmd == "init":
        sm.current_state = DaemonState.SEEDING
        sm._save_state()
        print("State machine initialized to SEEDING")

    elif cmd == "get_state":
        print(json.dumps(sm.get_state_progress(), indent=2))

    elif cmd == "transition":
        if len(sys.argv) < 3:
            print("Usage: state_machine.py transition <TO_STATE> [trigger]")
            sys.exit(1)
        to_state = DaemonState(sys.argv[2])
        trigger = sys.argv[3] if len(sys.argv) > 3 else "manual"
        success = sm.transition(to_state, trigger)
        print(f"Transition {'successful' if success else 'FAILED'}: {sm.get_state()}")

    elif cmd == "force_transition":
        if len(sys.argv) < 3:
            print("Usage: state_machine.py force_transition <TO_STATE> [trigger]")
            sys.exit(1)
        to_state = DaemonState(sys.argv[2])
        trigger = sys.argv[3] if len(sys.argv) > 3 else "forced"
        sm.force_transition(to_state, trigger)
        print(f"Forced transition to {to_state.value}")

    elif cmd == "set_degradation":
        if len(sys.argv) < 3:
            print("Usage: state_machine.py set_degradation <normal|conserve|minimal|suspended|safe_shutdown>")
            sys.exit(1)
        sm.set_degradation(sys.argv[2])
        print(f"Degradation set to {sys.argv[2]}")

    elif cmd == "should_run_layer":
        if len(sys.argv) < 3:
            print("Usage: state_machine.py should_run_layer <layer_name>")
            sys.exit(1)
        should_run, reason = sm.should_run_layer(sys.argv[2])
        print(json.dumps({"should_run": should_run, "reason": reason}))

    elif cmd == "progress":
        print(json.dumps(sm.get_state_progress(), indent=2))

    elif cmd == "history":
        limit = int(sys.argv[2]) if len(sys.argv) > 2 else 20
        for t in sm.get_recent_transitions(limit):
            print(f"  {t['timestamp']} {t['from_state']} → {t['to_state']} ({t['trigger']})")

    else:
        print(f"Unknown command: {cmd}")


if __name__ == "__main__":
    main()