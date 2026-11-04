#!/usr/bin/env python3
"""
Sensor Cache Layer — Cached Polling for Athena Sensors

Provides TTL-based cached reads from sensor sidecar.
Reduces privileged socket hits, enables change detection via hashes.
"""

import json
import os
import sys
import time
import socket
import struct
import hashlib
import threading
from pathlib import Path
from typing import Dict, Any, Optional, List
from dataclasses import dataclass, field
from datetime import datetime


@dataclass
class CachedReading:
    sensor: str
    data: Dict[str, Any]
    timestamp: int
    hash: str
    ttl: int
    expires_at: int


class SensorCache:
    def __init__(self,
                 socket_path: str = "/root/athena_sensor.sock",
                 secret_path: str = "/root/athena_sensor_secret",
                 default_ttl: int = 10):
        self.socket_path = socket_path
        self.secret_path = Path(secret_path)
        self.default_ttl = default_ttl
        self.cache: Dict[str, CachedReading] = {}
        self._lock = threading.RLock()
        self.secret = self._load_secret()
        self._conn_cache: Optional[socket.socket] = None
        self._conn_lock = threading.Lock()

    def _load_secret(self) -> str:
        if self.secret_path.exists():
            return self.secret_path.read_text().strip()
        return ""

    def _get_auth_token(self) -> str:
        return hashlib.sha256(self.secret.encode()).hexdigest()[:32]

    def _get_connection(self) -> Optional[socket.socket]:
        """Get or create persistent connection to sidecar"""
        with self._conn_lock:
            if self._conn_cache:
                try:
                    # Test connection
                    self._conn_cache.send(b"\x00\x00\x00\x00")
                    return self._conn_cache
                except Exception:
                    try:
                        self._conn_cache.close()
                    except Exception:
                        pass
                    self._conn_cache = None

            # Create new connection
            try:
                sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                sock.settimeout(5)
                sock.connect(self.socket_path)

                # Authenticate
                auth_msg = json.dumps({"token": self._get_auth_token()})
                self._send_message(sock, auth_msg)

                # Read auth response
                response = self._recv_message(sock)
                if response:
                    auth_resp = json.loads(response)
                    if auth_resp.get("status") == "authenticated":
                        self._conn_cache = sock
                        return sock

                sock.close()
            except Exception as e:
                pass
        return None

    def _send_message(self, sock: socket.socket, msg: str):
        data = msg.encode()
        sock.sendall(struct.pack("!I", len(data)) + data)

    def _recv_message(self, sock: socket.socket) -> Optional[str]:
        try:
            length_data = sock.recv(4)
            if len(length_data) < 4:
                return None
            length = struct.unpack("!I", length_data)[0]

            chunks = []
            remaining = length
            while remaining > 0:
                chunk = sock.recv(min(remaining, 4096))
                if not chunk:
                    return None
                chunks.append(chunk)
                remaining -= len(chunk)
            return b"".join(chunks).decode()
        except Exception:
            return None

    def _query_sidecar(self, action: str, **kwargs) -> Optional[Dict]:
        """Send command to sidecar and get response"""
        sock = self._get_connection()
        if not sock:
            return None

        cmd = {"action": action, **kwargs}
        self._send_message(sock, json.dumps(cmd))
        response = self._recv_message(sock)

        if response:
            return json.loads(response)
        return None

    def get(self, sensor: str, ttl: Optional[int] = None, force_refresh: bool = False) -> Optional[Dict[str, Any]]:
        """
        Get sensor reading with TTL caching.
        Returns cached data if valid, otherwise fetches from sidecar.
        """
        ttl = ttl or self.default_ttl
        now = int(time.time())

        with self._lock:
            # Check cache
            if not force_refresh and sensor in self.cache:
                cached = self.cache[sensor]
                if now < cached.expires_at:
                    return cached.data

            # Fetch from sidecar
            result = self._query_sidecar("get_reading", sensor=sensor)
            if result and result.get("status") == "ok":
                reading = result.get("reading", {})
                data = reading.get("data", {})
                timestamp = reading.get("timestamp", now)
                hash_val = reading.get("hash", "")

                # Update cache
                self.cache[sensor] = CachedReading(
                    sensor=sensor,
                    data=data,
                    timestamp=timestamp,
                    hash=hash_val,
                    ttl=ttl,
                    expires_at=now + ttl
                )
                return data

        return None

    def get_all(self, ttl: Optional[int] = None) -> Dict[str, Dict[str, Any]]:
        """Get all sensor readings"""
        result = self._query_sidecar("get_all")
        if result and result.get("status") == "ok":
            readings = result.get("readings", {})
            output = {}
            for sensor, reading in readings.items():
                data = reading.get("data", {})
                output[sensor] = data
                # Update cache
                with self._lock:
                    self.cache[sensor] = CachedReading(
                        sensor=sensor,
                        data=data,
                        timestamp=reading.get("timestamp", int(time.time())),
                        hash=reading.get("hash", ""),
                        ttl=ttl or self.default_ttl,
                        expires_at=int(time.time()) + (ttl or self.default_ttl)
                    )
            return output
        return {}

    def get_hash(self, sensor: str) -> Optional[str]:
        """Get content hash for change detection"""
        with self._lock:
            if sensor in self.cache:
                return self.cache[sensor].hash
        # Try fetch
        reading = self.get(sensor, force_refresh=True)
        if reading:
            with self._lock:
                if sensor in self.cache:
                    return self.cache[sensor].hash
        return None

    def has_changed(self, sensor: str, last_hash: str) -> bool:
        """Check if sensor data has changed since last_hash"""
        current_hash = self.get_hash(sensor)
        if current_hash is None:
            return True  # Unknown, assume changed
        return current_hash != last_hash

    def wait_for_change(self, sensor: str, last_hash: str, timeout: float = 30.0, poll_interval: float = 1.0) -> bool:
        """Wait for sensor data to change"""
        start = time.time()
        while time.time() - start < timeout:
            if self.has_changed(sensor, last_hash):
                return True
            time.sleep(poll_interval)
        return False

    def invalidate(self, sensor: str):
        """Force cache invalidation for sensor"""
        with self._lock:
            if sensor in self.cache:
                del self.cache[sensor]

    def invalidate_all(self):
        """Clear all cache"""
        with self._lock:
            self.cache.clear()

    def get_cache_status(self) -> Dict[str, Any]:
        """Get cache status for debugging"""
        with self._lock:
            now = int(time.time())
            status = {}
            for sensor, cached in self.cache.items():
                status[sensor] = {
                    "age_seconds": now - cached.timestamp,
                    "expires_in": cached.expires_at - now,
                    "hash": cached.hash,
                    "valid": now < cached.expires_at
                }
            return status


class EventBasedCache(SensorCache):
    """Extended cache with event-based invalidation support"""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._event_listeners: Dict[str, List[callable]] = {}

    def on_change(self, sensor: str, callback: callable):
        """Register callback for sensor changes"""
        if sensor not in self._event_listeners:
            self._event_listeners[sensor] = []
        self._event_listeners[sensor].append(callback)

    def _notify_listeners(self, sensor: str, old_data: Dict, new_data: Dict):
        for cb in self._event_listeners.get(sensor, []):
            try:
                cb(sensor, old_data, new_data)
            except Exception:
                pass

    def get_with_event(self, sensor: str, ttl: Optional[int] = None) -> Dict[str, Any]:
        """Get reading, trigger events on change"""
        old_hash = self.get_hash(sensor)
        data = self.get(sensor, ttl=ttl, force_refresh=True)
        new_hash = self.get_hash(sensor)

        if old_hash and new_hash and old_hash != new_hash:
            # Get old data from cache before update
            with self._lock:
                old_data = self.cache[sensor].data if sensor in self.cache else {}
            self._notify_listeners(sensor, old_data, data or {})

        return data or {}


def get_sensor_cache() -> SensorCache:
    """Factory for global sensor cache instance"""
    return SensorCache()


def main():
    """CLI for testing"""
    cache = SensorCache()

    if len(sys.argv) < 2:
        print("Usage: sensor_cache.py <command> [sensor]")
        print("Commands: get, get_all, hash, status, wait")
        sys.exit(1)

    cmd = sys.argv[1]

    if cmd == "get":
        sensor = sys.argv[2] if len(sys.argv) > 2 else "screen"
        ttl = int(sys.argv[3]) if len(sys.argv) > 3 else 10
        data = cache.get(sensor, ttl=ttl)
        print(json.dumps(data, indent=2))

    elif cmd == "get_all":
        data = cache.get_all()
        print(json.dumps(data, indent=2))

    elif cmd == "hash":
        sensor = sys.argv[2] if len(sys.argv) > 2 else "screen"
        h = cache.get_hash(sensor)
        print(h or "none")

    elif cmd == "status":
        print(json.dumps(cache.get_cache_status(), indent=2))

    elif cmd == "wait":
        sensor = sys.argv[2] if len(sys.argv) > 2 else "screen"
        last_hash = sys.argv[3] if len(sys.argv) > 3 else ""
        timeout = float(sys.argv[4]) if len(sys.argv) > 4 else 30.0
        changed = cache.wait_for_change(sensor, last_hash, timeout)
        print("changed" if changed else "timeout")

    else:
        print(f"Unknown command: {cmd}")


if __name__ == "__main__":
    main()