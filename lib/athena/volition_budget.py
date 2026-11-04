"""
Volition Budget Manager for Athena Consciousness System

Manages budget enforcement, cost tracking, and escrow for AgentBnB hires.
Integrates with Paperclip budget system.
"""

import json
import os
import sys
import struct
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, Any, Optional
from dataclasses import dataclass, asdict
import threading

# Import Huffman codec
sys.path.insert(0, os.path.dirname(__file__))
try:
    from huffman_codec import HuffmanCodec
    HUFFMAN_AVAILABLE = True
except ImportError:
    HUFFMAN_AVAILABLE = False

DATA_DIR = Path(os.environ.get("DATA_DIR", "/opt/athena/state"))
BUDGET_STATE_FILE = DATA_DIR / "volition_budget.json"
BUDGET_HISTORY_FILE = DATA_DIR / "volition_budget_history.jsonl"

# Thread safety
_budget_lock = threading.Lock()


@dataclass
class BudgetState:
    """Current budget state."""
    daily_limit_cents: int = 2000
    monthly_limit_cents: int = 60000
    currency: str = "USD"
    daily_spent_cents: int = 0
    monthly_spent_cents: int = 0
    daily_reset_date: str = ""
    monthly_reset_date: str = ""
    reserved_cents: int = 0
    escrow_reserve_cents: int = 5000
    alert_threshold: float = 0.7
    last_updated: str = ""

    def __post_init__(self):
        if not self.daily_reset_date:
            self.daily_reset_date = (datetime.now() + timedelta(days=1)).strftime("%Y-%m-%d")
        if not self.monthly_reset_date:
            next_month = datetime.now().replace(day=1) + timedelta(days=32)
            self.monthly_reset_date = next_month.replace(day=1).strftime("%Y-%m-%d")
        if not self.last_updated:
            self.last_updated = datetime.now().isoformat()

    @property
    def available_cents(self) -> int:
        """Available budget for new spends."""
        return min(
            self.daily_limit_cents - self.daily_spent_cents,
            self.monthly_limit_cents - self.monthly_spent_cents
        ) - self.reserved_cents

    @property
    def daily_utilization(self) -> float:
        """Daily budget utilization ratio."""
        if self.daily_limit_cents == 0:
            return 0.0
        return (self.daily_spent_cents + self.reserved_cents) / self.daily_limit_cents

    @property
    def monthly_utilization(self) -> float:
        """Monthly budget utilization ratio."""
        if self.monthly_limit_cents == 0:
            return 0.0
        return (self.monthly_spent_cents + self.reserved_cents) / self.monthly_limit_cents

    @property
    def is_alert(self) -> bool:
        """Whether budget alert threshold is exceeded."""
        return self.daily_utilization >= self.alert_threshold or self.monthly_utilization >= self.alert_threshold


class VolitionBudgetManager:
    """Manages volition layer budget with persistence."""

    def __init__(self, config: Dict[str, Any]):
        self.config = config
        self.state = self._load_state()
        self._ensure_reset_dates()

    def _load_state(self) -> BudgetState:
        """Load budget state from disk (uncompressed fallback)."""
        if BUDGET_STATE_FILE.exists():
            try:
                with open(BUDGET_STATE_FILE) as f:
                    data = json.load(f)
                return BudgetState(**data)
            except Exception:
                pass
        return BudgetState(
            daily_limit_cents=self.config.get("daily_limit_cents", 2000),
            monthly_limit_cents=self.config.get("monthly_limit_cents", 60000),
            currency=self.config.get("currency", "USD"),
            alert_threshold=self.config.get("alert_threshold", 0.7),
            escrow_reserve_cents=self.config.get("escrow_reserve_cents", 5000)
        )

    def load_state_compressed(self):
        """Load budget state from Huffman-compressed files (fallback to uncompressed)."""
        if not HUFFMAN_AVAILABLE:
            self.state = self._load_state()
            return

        huf_path = str(BUDGET_STATE_FILE) + ".huf"
        codec_path = str(BUDGET_STATE_FILE) + ".huf.codec"

        if os.path.exists(huf_path) and os.path.exists(codec_path):
            try:
                codec = HuffmanCodec.load(codec_path)

                with open(huf_path, "rb") as f:
                    compressed_len = struct.unpack('>I', f.read(4))[0]
                    compressed = f.read(compressed_len)

                json_bytes = codec.decode(compressed)
                data = json.loads(json_bytes.decode('utf-8'))
                self.state = BudgetState(**data)
                return
            except Exception as e:
                print(f"Failed to load compressed budget state: {e}", file=sys.stderr)

        # Fallback to uncompressed
        self.state = self._load_state()

    def _save_state(self):
        """Save budget state to disk (uncompressed JSON)."""
        self.state.last_updated = datetime.now().isoformat()
        with _budget_lock:
            with open(BUDGET_STATE_FILE, "w") as f:
                json.dump(asdict(self.state), f, indent=2)

    def save_state_compressed(self, codec: 'HuffmanCodec' = None):
        """Save budget state as Huffman-compressed bytes + codec sidecar."""
        if not HUFFMAN_AVAILABLE:
            self.save_state_compressed()
            return

        self.state.last_updated = datetime.now().isoformat()
        data = asdict(self.state)
        json_bytes = json.dumps(data, separators=(',', ':')).encode('utf-8')

        if codec is None:
            codec = HuffmanCodec.build_from_json_samples([data])

        compressed = codec.encode(json_bytes)

        # Write compressed state
        huf_path = str(BUDGET_STATE_FILE) + ".huf"
        with open(huf_path, "wb") as f:
            f.write(struct.pack('>I', len(compressed)))
            f.write(compressed)

        # Write codec sidecar
        codec_path = str(BUDGET_STATE_FILE) + ".huf.codec"
        codec.save(codec_path)

        # Remove old uncompressed
        with _budget_lock:
            if BUDGET_STATE_FILE.exists():
                os.remove(BUDGET_STATE_FILE)

    def _append_history(self, entry: Dict[str, Any]):
        """Append to budget history log."""
        entry["timestamp"] = datetime.now().isoformat()
        with open(BUDGET_HISTORY_FILE, "a") as f:
            f.write(json.dumps(entry) + "\n")

    def _ensure_reset_dates(self):
        """Reset daily/monthly counters if needed."""
        now = datetime.now()
        daily_reset = datetime.strptime(self.state.daily_reset_date, "%Y-%m-%d")
        monthly_reset = datetime.strptime(self.state.monthly_reset_date, "%Y-%m-%d")

        if now >= daily_reset:
            self.state.daily_spent_cents = 0
            self.state.daily_reset_date = (now + timedelta(days=1)).strftime("%Y-%m-%d")
            self._append_history({"event": "daily_reset", "new_daily_reset": self.state.daily_reset_date})

        if now >= monthly_reset:
            self.state.monthly_spent_cents = 0
            next_month = now.replace(day=1) + timedelta(days=32)
            self.state.monthly_reset_date = next_month.replace(day=1).strftime("%Y-%m-%d")
            self._append_history({"event": "monthly_reset", "new_monthly_reset": self.state.monthly_reset_date})

        self.save_state_compressed()

    def get_status(self) -> Dict[str, Any]:
        """Get current budget status."""
        self._ensure_reset_dates()
        return {
            "daily_limit_cents": self.state.daily_limit_cents,
            "monthly_limit_cents": self.state.monthly_limit_cents,
            "currency": self.state.currency,
            "daily_spent_cents": self.state.daily_spent_cents,
            "monthly_spent_cents": self.state.monthly_spent_cents,
            "reserved_cents": self.state.reserved_cents,
            "available_cents": self.state.available_cents,
            "daily_utilization": self.state.daily_utilization,
            "monthly_utilization": self.state.monthly_utilization,
            "is_alert": self.state.is_alert,
            "alert_threshold": self.state.alert_threshold,
            "escrow_reserve_cents": self.state.escrow_reserve_cents,
            "daily_reset_date": self.state.daily_reset_date,
            "monthly_reset_date": self.state.monthly_reset_date,
            "last_updated": self.state.last_updated
        }

    def reserve(self, amount_cents: int) -> Dict[str, Any]:
        """Reserve budget for future spend (e.g., escrow)."""
        self._ensure_reset_dates()

        if amount_cents <= 0:
            return {"success": False, "error": "Amount must be positive"}

        if self.state.available_cents < amount_cents:
            return {"success": False, "error": f"Insufficient available budget: {self.state.available_cents} cents"}

        self.state.reserved_cents += amount_cents
        self.save_state_compressed()
        self._append_history({
            "event": "reserve",
            "amount_cents": amount_cents,
            "new_reserved_cents": self.state.reserved_cents
        })

        return {"success": True, "reserved_cents": amount_cents, "total_reserved": self.state.reserved_cents}

    def spend(self, amount_cents: int, description: str = "") -> Dict[str, Any]:
        """Spend from budget (moves from reserved or direct spend)."""
        self._ensure_reset_dates()

        if amount_cents <= 0:
            return {"success": False, "error": "Amount must be positive"}

        # Use reserved first, then available
        from_reserved = min(amount_cents, self.state.reserved_cents)
        from_available = amount_cents - from_reserved

        if self.state.available_cents < from_available:
            return {"success": False, "error": f"Insufficient available budget: {self.state.available_cents} cents"}

        self.state.reserved_cents -= from_reserved
        self.state.daily_spent_cents += amount_cents
        self.state.monthly_spent_cents += amount_cents
        self.save_state_compressed()

        self._append_history({
            "event": "spend",
            "amount_cents": amount_cents,
            "description": description,
            "from_reserved": from_reserved,
            "from_available": from_available,
            "daily_spent_cents": self.state.daily_spent_cents,
            "monthly_spent_cents": self.state.monthly_spent_cents
        })

        return {
            "success": True,
            "spent_cents": amount_cents,
            "daily_spent_cents": self.state.daily_spent_cents,
            "monthly_spent_cents": self.state.monthly_spent_cents,
            "remaining_available": self.state.available_cents
        }

    def release_reserve(self, amount_cents: int) -> Dict[str, Any]:
        """Release reserved budget back to available."""
        self._ensure_reset_dates()

        if amount_cents <= 0:
            return {"success": False, "error": "Amount must be positive"}

        release_amount = min(amount_cents, self.state.reserved_cents)
        self.state.reserved_cents -= release_amount
        self.save_state_compressed()

        self._append_history({
            "event": "release_reserve",
            "amount_cents": release_amount,
            "new_reserved_cents": self.state.reserved_cents
        })

        return {"success": True, "released_cents": release_amount, "remaining_reserved": self.state.reserved_cents}

    def set_limits(self, daily_limit_cents: Optional[int] = None, monthly_limit_cents: Optional[int] = None):
        """Update budget limits."""
        if daily_limit_cents is not None:
            self.state.daily_limit_cents = daily_limit_cents
        if monthly_limit_cents is not None:
            self.state.monthly_limit_cents = monthly_limit_cents
        self.save_state_compressed()
        self._append_history({
            "event": "limits_updated",
            "daily_limit_cents": self.state.daily_limit_cents,
            "monthly_limit_cents": self.state.monthly_limit_cents
        })