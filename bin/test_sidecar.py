import socket
import json
import struct
import os
import hashlib

SOCKET_PATH = "/root/athena_sensor.sock"
SECRET_PATH = "/root/athena_sensor_secret"

def send_msg(sock, msg):
    data = msg.encode()
    sock.sendall(struct.pack("!I", len(data)) + data)

def recv_msg(sock):
    length_data = sock.recv(4)
    if not length_data: return None
    length = struct.unpack("!I", length_data)[0]
    chunks = []
    remaining = length
    while remaining > 0:
        chunk = sock.recv(min(remaining, 4096))
        if not chunk: break
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks).decode()

def main():
    if not os.path.exists(SECRET_PATH):
        print("Secret not found")
        return
    
    secret = open(SECRET_PATH).read().strip()
    token = hashlib.sha256(secret.encode()).hexdigest()[:32]
    
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.connect(SOCKET_PATH)
            send_msg(s, json.dumps({"token": token}))
            print(f"Auth response: {recv_msg(s)}")
            
            send_msg(s, json.dumps({"action": "get_reading", "sensor": "network"}))
            print(f"Network data: {recv_msg(s)}")
            
            send_msg(s, json.dumps({"action": "get_reading", "sensor": "battery"}))
            print(f"Battery data: {recv_msg(s)}")
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    main()
