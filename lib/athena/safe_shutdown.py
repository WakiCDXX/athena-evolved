import os
import signal
import subprocess
import time
import json

DATA_DIR = "/opt/athena/state"

def get_all_layer_pids():
    """
    Collects PIDs from all known layer pidfiles in the state directory.
    """
    pids = []
    # Common layer names used in Athena
    layers = [
        "body", "emotions", "continuity", "attention", "introspection", 
        "doubt", "volition", "memory", "heartbeat", "archive", 
        "memory_backup", "openappa", "archestra", "vera_cpu", 
        "wayfinder", "implement_spec", "tdd", "handoff", 
        "to_spec", "workflow_chain", "senses", "sd_health_monitor"
    ]
    
    for name in layers:
        pid_file = os.path.join(DATA_DIR, f"{name}.pid")
        if os.path.exists(pid_file):
            try:
                with open(pid_file, 'r') as f:
                    pid = f.read().strip()
                    if pid and pid.isdigit():
                        pids.append(int(pid))
            except Exception:
                continue
    return list(set(pids))

def kill_process_tree(pid, sig=signal.SIGTERM):
    """
    Kills a process and all its children.
    """
    try:
        # Find children using pgrep -P
        children = subprocess.check_output(["pgrep", "-P", str(pid)], text=True).splitlines()
        for child in children:
            kill_process_tree(int(child), sig)
        os.kill(pid, sig)
    except (subprocess.CalledProcessError, ProcessLookupError, PermissionError):
        pass

def perform_safe_shutdown(timeout=2.0):
    """
    Executes a parallel shutdown: SIGTERM -> Wait -> SIGKILL.
    """
    pids = get_all_layer_pids()
    if not pids:
        print("No active layer PIDs found.")
        return

    print(f"Initiating safe shutdown for {len(pids)} processes...")

    # Phase 1: Parallel SIGTERM
    for pid in pids:
        kill_process_tree(pid, signal.SIGTERM)
    
    # Wait for processes to exit
    start_time = time.time()
    while time.time() - start_time < timeout:
        remaining = [pid for pid in pids if os.path.exists(f"/proc/{pid}")]
        if not remaining:
            break
        time.sleep(0.2)
    
    # Phase 2: Parallel SIGKILL for survivors
    remaining = [pid for pid in pids if os.path.exists(f"/proc/{pid}")]
    if remaining:
        print(f"Forcing shutdown for {len(remaining)} stubborn processes...")
        for pid in remaining:
            kill_process_tree(pid, signal.SIGKILL)

    # Cleanup PID files
    for name in ["body", "emotions", "continuity", "attention", "introspection", 
                 "doubt", "volition", "memory", "heartbeat", "archive", 
                 "memory_backup", "openappa", "archestra", "vera_cpu", 
                 "wayfinder", "implement_spec", "tdd", "handoff", 
                 "to_spec", "workflow_chain", "senses", "sd_health_monitor"]:
        pid_file = os.path.join(DATA_DIR, f"{name}.pid")
        if os.path.exists(pid_file):
            os.remove(pid_file)

    print("Safe shutdown completed.")

if __name__ == "__main__":
    perform_safe_shutdown()
