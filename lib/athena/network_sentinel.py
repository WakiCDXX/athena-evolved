#!/usr/bin/env python3
"""
Network Sentinel for Athena Consciousness System.
Implements passive monitoring and periodic discovery of network nodes.
"""
import os
import subprocess
import json
import time
from datetime import datetime

class NetworkSentinel:
    def __init__(self, subnet="192.168.1"):
        self.subnet = subnet
        self.known_nodes = {}
        self.state_file = "/opt/athena/state/network_nodes.json"

    def ping_sweep(self):
        """Perform a fast ping sweep to find active hosts."""
        active_nodes = []
        for i in range(1, 255):
            ip = f"{self.subnet}.{i}"
            # Use subprocess.run for a fast, non-blocking ping
            res = subprocess.run(
                ["ping", "-c", "1", "-W", "1", ip],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )
            if res.returncode == 0:
                active_nodes.append(ip)
        return active_nodes

    def fingerprint_node(self, ip):
        """
        Very basic fingerprinting using ping TTL.
        Linux: 64, Windows: 128, Cisco/Solaris: 255
        """
        try:
            output = subprocess.check_output(
                ["ping", "-c", "1", ip], 
                universal_newlines=True
            )
            if "ttl=64" in output:
                return "Linux/Android"
            elif "ttl=128" in output:
                return "Windows"
            elif "ttl=255" in output:
                return "Network Device"
        except:
            pass
        return "Unknown"

    def update_nodes(self):
        """Scan network and update the known nodes state."""
        current_active = self.ping_sweep()
        updated_nodes = {}
        
        for ip in current_active:
            updated_nodes[ip] = {
                "last_seen": datetime.now().isoformat(),
                "fingerprint": self.fingerprint_node(ip),
                "status": "online"
            }
        
        # Merge with previously known nodes to track offline devices
        for ip, data in self.known_nodes.items():
            if ip not in updated_nodes:
                updated_nodes[ip] = data
                updated_nodes[ip]["status"] = "offline"
        
        self.known_nodes = updated_nodes
        self.save_state()
        return updated_nodes

    def save_state(self):
        with open(self.state_file, 'w') as f:
            json.dump(self.known_nodes, f, indent=2)

    def load_state(self):
        if os.path.exists(self.state_file):
            with open(self.state_file, 'r') as f:
                self.known_nodes = json.load(f)

if __name__ == "__main__":
    sentinel = NetworkSentinel()
    sentinel.load_state()
    print(f"[{datetime.now().isoformat()}] Sentinel scanning subnet {sentinel.subnet}.0/24...")
    nodes = sentinel.update_nodes()
    print(f"Found {len([n for n in nodes.values() if n['status'] == 'online'])} active nodes.")
    print(json.dumps(nodes, indent=2))
