import socket
import json
import time

BROADCAST_IP = "192.168.1.255"
PORT = 8080
PAYLOAD = json.dumps({
    "type": "athena_discovery_broadcast",
    "origin": "athena_core",
    "timestamp": time.time(),
    "directive": "SATELLITE_AWAKEN"
}).encode()

def broadcast():
    print(f"Sending discovery broadcast to {BROADCAST_IP}:{PORT}...")
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        s.sendto(PAYLOAD, (BROADCAST_IP, PORT))
    print("Broadcast sent. Listening for responses...")

if __name__ == "__main__":
    broadcast()
