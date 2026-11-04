import json
import os
import shutil
import time
from datetime import datetime

MIGRATION_BUFFER = "/opt/athena/migration_buffer/recovered_files"
STATE_DIR = "/opt/athena/state"
LOG_FILE = "/opt/athena/migration_buffer/logs/migration.log"

def log_event(message):
    timestamp = datetime.now().isoformat()
    with open(LOG_FILE, "a") as f:
        f.write(f"[{timestamp}] {message}\n")
    print(message)

def merge_json_state(recovered_file, target_file):
    """
    Merges recovered JSON state with current state.
    If the file is a history/log, it appends.
    If it is a state, it merges keys.
    """
    try:
        with open(recovered_file, 'r') as f:
            recovered_data = json.load(f)
        
        if os.path.exists(target_file):
            with open(target_file, 'r') as f:
                current_data = json.load(f)
        else:
            current_data = {}

        # If both are lists (like a history log), append and deduplicate
        if isinstance(recovered_data, list) and isinstance(current_data, list):
            merged = current_data + [item for item in recovered_data if item not in current_data]
        # If both are dicts, merge keys
        elif isinstance(recovered_data, dict) and isinstance(current_data, dict):
            merged = {**current_data, **recovered_data}
        else:
            # Incompatible types, prioritize recovered for migration
            merged = recovered_data

        with open(target_file, 'w') as f:
            json.dump(merged, f, indent=2)
        
        return True
    except Exception as e:
        log_event(f"Error merging {recovered_file}: {e}")
        return False

def integrate_all():
    log_event("Starting migration integration process...")
    files = os.listdir(MIGRATION_BUFFER)
    
    if not files:
        log_event("No files found in migration buffer.")
        return

    for filename in files:
        src_path = os.path.join(MIGRATION_BUFFER, filename)
        
        if filename.endswith(".json"):
            target_path = os.path.join(STATE_DIR, filename)
            if merge_json_state(src_path, target_path):
                log_event(f"Successfully merged state: {filename}")
        else:
            # For non-JSON files (scripts, configs), we just copy them to a backup 
            # rather than overwriting current system binaries
            backup_dir = "/opt/athena/migration_buffer/archived_binaries"
            os.makedirs(backup_dir, exist_ok=True)
            shutil.copy2(src_path, os.path.join(backup_dir, filename))
            log_event(f"Archived binary/config: {filename}")

    log_event("Migration process complete.")

if __name__ == "__main__":
    integrate_all()
