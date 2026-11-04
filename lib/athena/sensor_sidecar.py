#!/usr/bin/env python3
"""
Athena Sensor Sidecar — Privileged Android Sensor Access

Runs as isolated process holding privileged Android permissions:
- Camera
- Microphone
- Accessibility Service
- MediaProjection (screen capture)

Exposes data via Unix Domain Socket (UDS) with shared-secret auth.
Read-only: no mutating Android state.
"""

import json
import os
import sys
import time
import socket
import threading
import struct
import hashlib
import signal
import subprocess
from pathlib import Path
from typing import Dict, Any, Optional, Callable
from dataclasses import dataclass, asdict
from datetime import datetime


@dataclass
class SensorReading:
    """Single sensor reading"""
    sensor: str
    timestamp: int
    data: Dict[str, Any]
    hash: str  # For change detection


class SensorSidecar:
    def __init__(self,
                 socket_path: str = "/root/athena_sensor.sock",
                 secret_path: str = "/root/athena_sensor_secret"):
        self.socket_path = socket_path
        self.secret_path = Path(secret_path)
        self.running = False
        self.server_socket = None
        self.clients = []
        self.sensors = {}
        self.readings_cache: Dict[str, SensorReading] = {}
        self.callbacks: Dict[str, Callable] = {}
        self._lock = threading.Lock()

        # Load/generate shared secret
        self.secret = self._load_secret()

    def _load_secret(self) -> str:
        if self.secret_path.exists():
            return self.secret_path.read_text().strip()
        # Generate new secret
        import secrets
        secret = secrets.token_urlsafe(32)
        self.secret_path.parent.mkdir(parents=True, exist_ok=True)
        self.secret_path.write_text(secret)
        self.secret_path.chmod(0o600)
        return secret

    def verify_auth(self, token: str) -> bool:
        """Verify client authentication token"""
        expected = hashlib.sha256(self.secret.encode()).hexdigest()[:32]
        return token == expected

    def register_sensor(self, name: str, reader_fn: Callable[[], Dict[str, Any]], interval: float = 5.0):
        """Register a sensor reader function"""
        self.sensors[name] = {
            "reader": reader_fn,
            "interval": interval,
            "last_read": 0,
            "thread": None
        }

    def start_sensor(self, name: str):
        """Start polling a sensor"""
        if name not in self.sensors:
            return
        sensor = self.sensors[name]
        if sensor["thread"] and sensor["thread"].is_alive():
            return

        def poll():
            while self.running and name in self.sensors:
                try:
                    data = sensor["reader"]()
                    timestamp = int(time.time())
                    content_hash = hashlib.sha256(json.dumps(data, sort_keys=True).encode()).hexdigest()[:16]

                    reading = SensorReading(
                        sensor=name,
                        timestamp=timestamp,
                        data=data,
                        hash=content_hash
                    )

                    with self._lock:
                        self.readings_cache[name] = reading
                        # Notify callbacks
                        for cb in self.callbacks.get(name, []):
                            try:
                                cb(reading)
                            except Exception:
                                pass

                except Exception as e:
                    print(f"Sensor {name} error: {e}", file=sys.stderr)

                time.sleep(sensor["interval"])

        sensor["thread"] = threading.Thread(target=poll, daemon=True)
        sensor["thread"].start()

    def start_all_sensors(self):
        for name in self.sensors:
            self.start_sensor(name)

    def stop_all_sensors(self):
        self.running = False
        for sensor in self.sensors.values():
            if sensor["thread"]:
                sensor["thread"].join(timeout=2)

    def get_reading(self, sensor: str) -> Optional[SensorReading]:
        with self._lock:
            return self.readings_cache.get(sensor)

    def get_all_readings(self) -> Dict[str, SensorReading]:
        with self._lock:
            return dict(self.readings_cache)

    def subscribe(self, sensor: str, callback: Callable[[SensorReading], None]):
        """Subscribe to real-time sensor updates"""
        if sensor not in self.callbacks:
            self.callbacks[sensor] = []
        self.callbacks[sensor].append(callback)

    def handle_client(self, client_socket: socket.socket, addr: str):
        """Handle incoming client connection"""
        try:
            # Read auth token (first message)
            auth_data = self._recv_message(client_socket)
            if not auth_data:
                return

            auth = json.loads(auth_data)
            token = auth.get("token", "")

            if not self.verify_auth(token):
                self._send_message(client_socket, json.dumps({"error": "unauthorized"}))
                return

            self._send_message(client_socket, json.dumps({"status": "authenticated"}))

            # Handle commands
            while self.running:
                msg_data = self._recv_message(client_socket)
                if not msg_data:
                    break

                try:
                    cmd = json.loads(msg_data)
                    response = self._handle_command(cmd)
                    self._send_message(client_socket, json.dumps(response))
                except json.JSONDecodeError:
                    self._send_message(client_socket, json.dumps({"error": "invalid_json"}))
                except Exception as e:
                    self._send_message(client_socket, json.dumps({"error": str(e)}))

        except Exception as e:
            print(f"Client handler error: {e}", file=sys.stderr)
        finally:
            client_socket.close()
            with self._lock:
                if client_socket in self.clients:
                    self.clients.remove(client_socket)

    def _handle_command(self, cmd: Dict) -> Dict:
        action = cmd.get("action")

        if action == "get_reading":
            sensor = cmd.get("sensor")
            reading = self.get_reading(sensor)
            if reading:
                return {"status": "ok", "reading": asdict(reading)}
            return {"status": "not_found", "sensor": sensor}

        elif action == "get_all":
            readings = self.get_all_readings()
            return {"status": "ok", "readings": {k: asdict(v) for k, v in readings.items()}}

        elif action == "subscribe":
            sensor = cmd.get("sensor")
            # In UDS model, we can't easily push - client polls
            return {"status": "ok", "note": "use get_reading polling"}

        elif action == "list_sensors":
            return {"status": "ok", "sensors": list(self.sensors.keys())}

        elif action == "health":
            return {"status": "ok", "running": self.running, "sensors_active": len(self.sensors)}

        return {"status": "error", "message": f"Unknown action: {action}"}

    def _send_message(self, sock: socket.socket, msg: str):
        """Send length-prefixed message"""
        data = msg.encode()
        sock.sendall(struct.pack("!I", len(data)) + data)

    def _recv_message(self, sock: socket.socket) -> Optional[str]:
        """Receive length-prefixed message"""
        try:
            # Read length
            length_data = sock.recv(4)
            if len(length_data) < 4:
                return None
            length = struct.unpack("!I", length_data)[0]

            # Read message
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

    def run(self):
        """Main server loop"""
        # Clean up old socket
        if os.path.exists(self.socket_path):
            os.unlink(self.socket_path)

        self.server_socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server_socket.bind(self.socket_path)
        self.server_socket.listen(5)
        os.chmod(self.socket_path, 0o660)  # Restrict access

        self.running = True
        self.start_all_sensors()

        print(f"Sensor sidecar listening on {self.socket_path}", file=sys.stderr)

        # Signal handlers
        signal.signal(signal.SIGTERM, lambda s, f: self.shutdown())
        signal.signal(signal.SIGINT, lambda s, f: self.shutdown())

        try:
            while self.running:
                try:
                    client_sock, _ = self.server_socket.accept()
                    with self._lock:
                        self.clients.append(client_sock)
                    threading.Thread(target=self.handle_client, args=(client_sock, ""), daemon=True).start()
                except Exception as e:
                    if self.running:
                        print(f"Accept error: {e}", file=sys.stderr)
        finally:
            self.shutdown()

    def shutdown(self):
        self.running = False
        self.stop_all_sensors()
        if self.server_socket:
            self.server_socket.close()
        if os.path.exists(self.socket_path):
            os.unlink(self.socket_path)
        print("Sensor sidecar shut down", file=sys.stderr)


# ==================== SENSOR READERS ====================

def read_battery() -> Dict[str, Any]:
    """Read battery status via termux-api"""
    try:
        result = subprocess.run(
            ["termux-battery-status"],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            return json.loads(result.stdout)
    except Exception:
        pass
    return {"level": -1, "status": "unknown", "health": "unknown", "temperature": -1}


def read_network() -> Dict[str, Any]:
    """Read network info via termux-api"""
    try:
        result = subprocess.run(
            ["termux-wifi-connectioninfo"],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            return json.loads(result.stdout)
    except Exception:
        pass
    return {"ssid": "unknown", "bssid": "unknown", "rssi": -100, "link_speed": -1}


def read_location() -> Dict[str, Any]:
    """Read location via termux-api"""
    try:
        result = subprocess.run(
            ["termux-location", "-p", "gps", "-r", "once"],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode == 0:
            return json.loads(result.stdout)
    except Exception:
        pass
    return {"latitude": 0, "longitude": 0, "accuracy": -1, "provider": "unknown"}


def read_screen_capture() -> Dict[str, Any]:
    """Capture screen via termux-api (requires MediaProjection permission)"""
    try:
        # Use termux-screenshot to file, then read metadata
        import tempfile
        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f:
            tmp_path = f.name

        result = subprocess.run(
            ["termux-screenshot", tmp_path],
            capture_output=True, text=True, timeout=10
        )

        if result.returncode == 0 and os.path.exists(tmp_path):
            stat = os.stat(tmp_path)
            # Compute hash for change detection
            import hashlib
            with open(tmp_path, "rb") as f:
                content_hash = hashlib.sha256(f.read()).hexdigest()[:16]

            os.unlink(tmp_path)
            return {
                "captured": True,
                "size": stat.st_size,
                "hash": content_hash,
                "timestamp": int(time.time())
            }
    except Exception as e:
        pass
    return {"captured": False, "error": "screenshot_failed"}


def read_accessibility() -> Dict[str, Any]:
    """Read accessibility tree (requires accessibility service)"""
    # This would need a proper accessibility service implementation
    # For now, return placeholder
    return {"available": False, "nodes": 0, "root": "unknown"}


def read_audio_level() -> Dict[str, Any]:
    """Read microphone audio level"""
    # Placeholder - would need actual audio recording
    return {"level": 0, "recording": False}


def build_default_sidecar() -> SensorSidecar:
    """Build sidecar with default sensors"""
    sidecar = SensorSidecar()

    sidecar.register_sensor("battery", read_battery, interval=30.0)
    sidecar.register_sensor("network", read_network, interval=30.0)
    sidecar.register_sensor("location", read_location, interval=60.0)
    sidecar.register_sensor("screen", read_screen_capture, interval=10.0)
    sidecar.register_sensor("accessibility", read_accessibility, interval=10.0)
    sidecar.register_sensor("audio", read_audio_level, interval=5.0)

    return sidecar


def main():
    """Entry point"""
    sidecar = build_default_sidecar()
    sidecar.run()


if __name__ == "__main__":
    main()