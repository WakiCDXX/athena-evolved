"""
Unified State Management Utilities for Athena.
Provides optimized JSON I/O operations.
"""
import json
import os
from typing import Any, Optional, Union

def read_json(path: str, key: Optional[str] = None) -> Any:
    """Read a JSON file and optionally return a specific key."""
    try:
        if not os.path.exists(path):
            return {} if key else []
        with open(path, 'r') as f:
            data = json.load(f)
        if key:
            return data.get(key, [])
        return data
    except Exception:
        return {} if key else []

def set_json(path: str, key: str, value: Any) -> bool:
    """Set a key in a JSON file with atomic-like write."""
    try:
        data = read_json(path)
        if not isinstance(data, dict):
            data = {}
        
        # If value is a string that looks like JSON, try to parse it
        if isinstance(value, str):
            try:
                parsed = json.loads(value)
                value = parsed
            except json.JSONDecodeError:
                pass
        
        data[key] = value
        
        # Write to temp file then rename for atomic-like update
        temp_path = f"{path}.tmp"
        with open(temp_path, 'w') as f:
            json.dump(data, f, separators=(',', ':'))
        os.replace(temp_path, path)
        return True
    except Exception as e:
        print(f'Error setting JSON {key} in {path}: {e}')
        return False

def append_json(path: str, key: str, value: Any) -> bool:
    """Append a value to a list at a specific JSON key."""
    try:
        data = read_json(path)
        if not isinstance(data, dict):
            data = {}
        
        current_list = data.get(key, [])
        if not isinstance(current_list, list):
            current_list = [current_list] if current_list is not None else []
        
        current_list.append(value)
        return set_json(path, key, current_list)
    except Exception:
        return False

def init_json(path: str, initial_data: Optional[dict] = None) -> bool:
    """Initialize a JSON file with default data if it doesn't exist."""
    if os.path.exists(path):
        return True
    try:
        with open(path, 'w') as f:
            json.dump(initial_data or {}, f, separators=(',', ':'))
        return True
    except Exception:
        return False
