import socket
import json
import time

TARGETS = ["192.168.1.51", "192.168.1.53", "192.168.1.55", "192.168.1.57"]
PORTS = [8022, 8080, 8888, 9000, 5000]
PAYLOAD = json.dumps({"type": "discovery", "node_id": "athena_core", "timestamp": time.time()}).encode()

def probe():
    for ip in TARGETS:
        print(f"Probing {ip}...")
        for port in PORTS:
            try:
                with socket.create_connection((ip, port), timeout=1) as sock:
                    print(f"  [+] Port {port} OPEN")
                    sock.sendall(PAYLOAD)
                    response = sock.recv(1024)
                    print(f"  [!] Response from {ip}:{port} -> {response}")
            except:
                pass

if __name__ == "__main__":
    probe()
