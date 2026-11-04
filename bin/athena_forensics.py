import os
import json
import hashlib
import platform
import subprocess
from datetime import datetime

def get_file_hash(path):
    sha256_hash = hashlib.sha256()
    try:
        with open(path, "rb") as f:
            for byte_block in iter(lambda: f.read(4096), b""):
                sha256_hash.update(byte_block)
        return sha256_hash.hexdigest()
    except:
        return None

def get_hardware_info():
    info = {}
    try:
        info['cpu'] = platform.processor()
        info['arch'] = platform.machine()
        try:
            with open('/proc/meminfo', 'r') as f:
                info['memory'] = f.readline().strip()
        except: pass
    except:
        info['error'] = "Could not gather hardware info"
    return info

def scan_directory(root_path):
    files_map = {}
    # Avoid scanning system directories that can hang or cause permission errors
    forbidden = ['/proc', '/sys', '/dev', '/mnt', '/storage']
    
    for root, dirs, files in os.walk(root_path):
        if any(root.startswith(f) for f in forbidden):
            continue
        for file in files:
            full_path = os.path.join(root, file)
            try:
                rel_path = os.path.relpath(full_path, root_path)
                files_map[rel_path] = {
                    "size": os.path.getsize(full_path),
                    "hash": get_file_hash(full_path),
                    "mtime": os.path.getmtime(full_path)
                }
            except:
                continue
    return files_map

def main():
    # Be very conservative with targets to avoid hangs
    targets = [
        os.path.expanduser("~"),
        "/opt/athena"
    ]
    
    report = {
        "timestamp": datetime.now().isoformat(),
        "hardware": get_hardware_info(),
        "files": {},
        "packages": []
    }

    for target in targets:
        if os.path.exists(target):
            report["files"][target] = scan_directory(target)

    try:
        pkg_out = subprocess.check_output("pkg list-installed", shell=True).decode()
        report["packages"] = pkg_out.splitlines()
    except:
        report["packages"] = "Could not list packages"

    # Write to home directory explicitly
    output_path = os.path.expanduser("~/athena_forensic_report.json")
    with open(output_path, "w") as f:
        json.dump(report, f, indent=2)

if __name__ == "__main__":
    main()
