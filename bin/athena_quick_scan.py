import os, json, platform
from datetime import datetime

def main():
    report = {
        "timestamp": datetime.now().isoformat(),
        "hardware": {"cpu": platform.processor(), "arch": platform.machine()},
        "top_level_files": os.listdir(os.path.expanduser("~")) if os.path.exists(os.path.expanduser("~")) else []
    }
    with open(os.path.expanduser("~/athena_quick_report.json"), "w") as f:
        json.dump(report, f, indent=2)
    print("QUICK_SCAN_DONE")

if __name__ == "__main__":
    main()
