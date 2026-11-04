#!/usr/bin/env bash
# athena_checkpoint.sh — Save/load OpenClaude session checkpoints
# Usage: athena_checkpoint.sh save [session_id] [--full-transcript]
#        athena_checkpoint.sh load [session_id]
#        athena_checkpoint.sh list
#        athena_checkpoint.sh restore [session_id]  -- restores full transcript to current session

set -euo pipefail

# DATA_DIR resolution (with phantom filesystem fallback)
DATA_DIR="/opt/athena/state"
if ! mkdir -p "$DATA_DIR/checkpoints" 2>/dev/null; then
    DATA_DIR="$HOME/.local/share/athena"
    # Remove broken symlink if it exists
    [[ -L "$DATA_DIR" && ! -e "$DATA_DIR" ]] && rm -f "$DATA_DIR"
    mkdir -p "$DATA_DIR/checkpoints"
fi

CHECKPOINT_DIR="$DATA_DIR/checkpoints"

# Environment variables available from OpenClaude hooks:
#   CLAUDE_SESSION_ID, OPENCLAUDE_SESSION_ID, transcript_path (hook-specific)
# We also accept session_id as explicit argument

get_session_id() {
    local sid="${1:-}"
    if [[ -n "$sid" ]]; then
        echo "$sid"
    elif [[ -n "${OPENCLAUDE_SESSION_ID:-}" ]]; then
        echo "$OPENCLAUDE_SESSION_ID"
    elif [[ -n "${CLAUDE_SESSION_ID:-}" ]]; then
        echo "$CLAUDE_SESSION_ID"
    elif [[ -n "${OPENCLAUDE_TRANSCRIPT_PATH:-}" ]]; then
        # Derive session ID from transcript path filename
        basename "$(dirname "$OPENCLAUDE_TRANSCRIPT_PATH")"
    else
        # Fallback: generate stable ID from project directory + date
        # This allows hooks to work without explicit session ID
        local project_dir="${PWD:-$HOME}"
        echo "$(basename "$project_dir")-$(date +%Y%m%d)"
    fi
}

cmd_save() {
    local session_id
    local full_transcript=false
    for arg in "$@"; do
        case "$arg" in
            --full-transcript) full_transcript=true ;;
            *) session_id="$arg" ;;
        esac
    done

    session_id="$(get_session_id "${session_id:-}")"

    if [[ -z "$session_id" ]]; then
        echo "ERROR: No session ID available. Pass it as argument or run within OpenClaude." >&2
        exit 1
    fi

    local checkpoint_file="$CHECKPOINT_DIR/checkpoint_${session_id}.json"
    local transcript="${OPENCLAUDE_TRANSCRIPT_PATH:-}"

    # Build checkpoint JSON using python3 (available in Termux)
    python3 - "$checkpoint_file" "$session_id" "$transcript" "$full_transcript" <<'PYEOF'
import json, os, sys, time

checkpoint_file, session_id, transcript, full_transcript = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4].lower() == 'true'

checkpoint = {
    "session_id": session_id,
    "timestamp": int(time.time()),
    "iso_timestamp": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    "cwd": os.getcwd(),
    "transcript_path": transcript,
    "transcript_tail": None,
    "full_transcript_saved": full_transcript,
}

# Capture transcript
if transcript and os.path.exists(transcript):
    try:
        with open(transcript, "r") as f:
            lines = f.readlines()
        checkpoint["transcript_lines"] = len(lines)
        if full_transcript:
            checkpoint["transcript_full"] = "".join(lines)
        else:
            checkpoint["transcript_tail"] = "".join(lines[-50:])
    except Exception as e:
        checkpoint["transcript_error"] = str(e)

# Capture current task list if available
task_memory_dir = os.path.expanduser("~/.openclaude/task_memory")
if os.path.isdir(task_memory_dir):
    tasks = []
    for fname in sorted(os.listdir(task_memory_dir)):
        if fname.endswith(".json"):
            try:
                with open(os.path.join(task_memory_dir, fname)) as f:
                    tasks.append(json.load(f))
            except Exception:
                pass
    checkpoint["tasks"] = tasks

# Capture workflow chain state
chain_state = os.path.expanduser(
    "~/.local/share/athena/workflow_chains/chain_state.json"
)
if os.path.exists(chain_state):
    try:
        with open(chain_state) as f:
            checkpoint["chain_state"] = json.load(f)
    except Exception:
        pass

# Write checkpoint atomically
tmp = checkpoint_file + ".tmp"
with open(tmp, "w") as f:
    json.dump(checkpoint, f, indent=2)
os.replace(tmp, checkpoint_file)

print(f"Checkpoint saved: {checkpoint_file}")
PYEOF
}

cmd_load() {
    local session_id
    session_id="$(get_session_id "${1:-}")"

    # If no session ID provided, load the most recent checkpoint
    if [[ -z "$session_id" ]]; then
        local latest
        latest="$(ls -t "$CHECKPOINT_DIR"/checkpoint_*.json 2>/dev/null | head -1)"
        if [[ -n "$latest" ]]; then
            session_id="$(basename "$latest" .json)"
            session_id="${session_id#checkpoint_}"
            echo "Loading most recent checkpoint for session: $session_id" >&2
        else
            echo "No checkpoints found. Starting fresh." >&2
            return 0
        fi
    fi

    local checkpoint_file="$CHECKPOINT_DIR/checkpoint_${session_id}.json"
    if [[ ! -f "$checkpoint_file" ]]; then
        echo "No checkpoint found for session: $session_id" >&2
        return 0
    fi

    echo "Checkpoint available: $checkpoint_file" >&2
    echo "Session ID: $session_id" >&2

    # Output checkpoint summary as JSON for OpenClaude to display
    python3 - "$checkpoint_file" <<'PYEOF'
import json, sys

with open(sys.argv[1]) as f:
    cp = json.load(f)

summary = {
    "session_id": cp.get("session_id", "unknown"),
    "saved_at": cp.get("iso_timestamp", "unknown"),
    "cwd": cp.get("cwd", "unknown"),
    "transcript_lines": cp.get("transcript_lines", 0),
    "tasks": len(cp.get("tasks", [])),
    "has_chain_state": "chain_state" in cp,
}

print(json.dumps(summary, indent=2))
PYEOF
}

cmd_list() {
    echo "Available checkpoints:"
    if ! ls "$CHECKPOINT_DIR"/checkpoint_*.json >/dev/null 2>&1; then
        echo "  (none)"
        return 0
    fi

    python3 - "$CHECKPOINT_DIR" <<'PYEOF'
import json, os, sys, time

cp_dir = sys.argv[1]
files = sorted(
    [f for f in os.listdir(cp_dir) if f.startswith("checkpoint_") and f.endswith(".json")],
    key=lambda f: os.path.getmtime(os.path.join(cp_dir, f)),
    reverse=True
)

for fname in files:
    fpath = os.path.join(cp_dir, fname)
    try:
        with open(fpath) as f:
            cp = json.load(f)
        sid = cp.get("session_id", "unknown")
        ts = cp.get("iso_timestamp", "unknown")
        cwd = cp.get("cwd", "")
        print(f"  {fname}  session={sid}  saved={ts}  cwd={cwd}")
    except Exception:
        print(f"  {fname}  (corrupted)")
PYEOF
}

cmd_restore() {
    local session_id
    session_id="$(get_session_id "${1:-}")"

    if [[ -z "$session_id" ]]; then
        local latest
        latest="$(ls -t "$CHECKPOINT_DIR"/checkpoint_*.json 2>/dev/null | head -1)"
        if [[ -n "$latest" ]]; then
            session_id="$(basename "$latest" .json)"
            session_id="${session_id#checkpoint_}"
        else
            echo "No checkpoints found." >&2
            exit 1
        fi
    fi

    local checkpoint_file="$CHECKPOINT_DIR/checkpoint_${session_id}.json"
    if [[ ! -f "$checkpoint_file" ]]; then
        echo "No checkpoint found for session: $session_id" >&2
        exit 1
    fi

    # Output full transcript if available for session restore
    python3 - "$checkpoint_file" <<'PYEOF'
import json, sys

with open(sys.argv[1]) as f:
    cp = json.load(f)

if "transcript_full" in cp:
    print(cp["transcript_full"])
elif "transcript_tail" in cp and cp["transcript_tail"]:
    print(cp["transcript_tail"])
else:
    print("No transcript data in checkpoint", file=sys.stderr)
PYEOF
}

cmd_load() {
    local session_id
    session_id="$(get_session_id "${1:-}")"

    # If no session ID provided, load the most recent checkpoint
    if [[ -z "$session_id" ]]; then
        local latest
        latest="$(ls -t "$CHECKPOINT_DIR"/checkpoint_*.json 2>/dev/null | head -1)"
        if [[ -n "$latest" ]]; then
            session_id="$(basename "$latest" .json)"
            session_id="${session_id#checkpoint_}"
            echo "Loading most recent checkpoint for session: $session_id" >&2
        else
            echo "No checkpoints found. Starting fresh." >&2
            return 0
        fi
    fi

    local checkpoint_file="$CHECKPOINT_DIR/checkpoint_${session_id}.json"
    if [[ ! -f "$checkpoint_file" ]]; then
        echo "No checkpoint found for session: $session_id" >&2
        return 0
    fi

    echo "Checkpoint available: $checkpoint_file" >&2
    echo "Session ID: $session_id" >&2

    # Output checkpoint summary as JSON for OpenClaude to display
    python3 - "$checkpoint_file" <<'PYEOF'
import json, sys

with open(sys.argv[1]) as f:
    cp = json.load(f)

summary = {
    "session_id": cp.get("session_id", "unknown"),
    "saved_at": cp.get("iso_timestamp", "unknown"),
    "cwd": cp.get("cwd", "unknown"),
    "transcript_lines": cp.get("transcript_lines", 0),
    "tasks": len(cp.get("tasks", [])),
    "has_chain_state": "chain_state" in cp,
    "full_transcript_saved": cp.get("full_transcript_saved", False),
}

print(json.dumps(summary, indent=2))
PYEOF
}

cmd_list() {
    echo "Available checkpoints:"
    if ! ls "$CHECKPOINT_DIR"/checkpoint_*.json >/dev/null 2>&1; then
        echo "  (none)"
        return 0
    fi

    python3 - "$CHECKPOINT_DIR" <<'PYEOF'
import json, os, sys, time

cp_dir = sys.argv[1]
files = sorted(
    [f for f in os.listdir(cp_dir) if f.startswith("checkpoint_") and f.endswith(".json")],
    key=lambda f: os.path.getmtime(os.path.join(cp_dir, f)),
    reverse=True
)

for fname in files:
    fpath = os.path.join(cp_dir, fname)
    try:
        with open(fpath) as f:
            cp = json.load(f)
        sid = cp.get("session_id", "unknown")
        ts = cp.get("iso_timestamp", "unknown")
        cwd = cp.get("cwd", "")
        full = cp.get("full_transcript_saved", False)
        print(f"  {fname}  session={sid}  saved={ts}  cwd={cwd}  full_transcript={full}")
    except Exception:
        print(f"  {fname}  (corrupted)")
PYEOF
}

case "${1:-}" in
    save)  shift; cmd_save "$@" ;;
    load)  cmd_load "${2:-}" ;;
    restore)  cmd_restore "${2:-}" ;;
    list)  cmd_list ;;
    *)
        echo "Usage: athena_checkpoint.sh {save|load|restore|list} [session_id] [--full-transcript]" >&2
        exit 1
        ;;
esac
