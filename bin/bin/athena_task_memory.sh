#!/usr/bin/env bash
# athena_task_memory.sh - Persistent task memory checkpoint system
# Saves task state to JSON so context survives compaction
#
# Usage:
#   athena_task_memory.sh checkpoint <task_id> [subject]    - Create/refresh checkpoint
#   athena_task_memory.sh resume <task_id>                  - Print checkpoint summary
#   athena_task_memory.sh log <task_id> <key> <value>        - Append key/value entry
#   athena_task_memory.sh status                            - Show all checkpoints

set -o pipefail

BASE_DIR="$HOME"
MEMORY_DIR="$BASE_DIR/.openclaude/task_memory"
TASKS_DIR="$BASE_DIR/.openclaude/tasks"

mkdir -p "$MEMORY_DIR"

now_iso() { date -Iseconds; }
now() { date +%s; }

# Get task info from OpenClaude task JSON
get_task_info() {
    local task_id="$1"
    local session_dir
    session_dir=$(find "$TASKS_DIR" -name "${task_id}.json" -print -quit 2>/dev/null)
    if [[ -f "$session_dir" ]]; then
        python3 -c "
import json, sys
with open('$session_dir') as f:
    d = json.load(f)
print(d.get('subject', ''))
" 2>/dev/null
    fi
}

# checkpoint <task_id> [subject]
cmd_checkpoint() {
    local task_id="$1"
    local subject="${2:-}"
    local cp_file="$MEMORY_DIR/${task_id}.json"

    if [[ -z "$task_id" ]]; then
        echo "Usage: $0 checkpoint <task_id> [subject]" >&2
        return 1
    fi

    # If no subject provided, try to read from task JSON
    if [[ -z "$subject" ]]; then
        subject=$(get_task_info "$task_id")
    fi
    [[ -z "$subject" ]] && subject="Task $task_id"

    # If checkpoint exists, update timestamp and status; else create new
    if [[ -f "$cp_file" ]]; then
        python3 -c "
import json, sys
with open('$cp_file') as f:
    d = json.load(f)
d['last_updated'] = '$(now_iso)'
d.setdefault('status', 'in_progress')
if d.get('subject') == '' or d.get('subject') == 'Task $task_id':
    d['subject'] = '''$subject'''
with open('$cp_file', 'w') as f:
    json.dump(d, f, indent=2)
print(json.dumps(d))
" 2>/dev/null
    else
        cat > "$cp_file" <<EOF
{
  "task_id": "$task_id",
  "subject": "$subject",
  "created_at": "$(now_iso)",
  "last_updated": "$(now_iso)",
  "status": "in_progress",
  "files_examined": [],
  "commands_tested": [],
  "next_steps": [],
  "freeform_notes": []
}
EOF
        cat "$cp_file"
    fi
}

# resume <task_id> - print summary
cmd_resume() {
    local task_id="$1"
    local cp_file="$MEMORY_DIR/${task_id}.json"

    if [[ ! -f "$cp_file" ]]; then
        echo "No checkpoint found for task $task_id" >&2
        return 1
    fi

    python3 -c "
import json
with open('$cp_file') as f:
    d = json.load(f)
print(f\"=== Task Checkpoint: #{d['task_id']} ===\")
print(f\"Subject: {d.get('subject', 'N/A')}\")
print(f\"Status: {d.get('status', 'N/A')}\")
print(f\"Last updated: {d.get('last_updated', 'N/A')}\")
print()
if d.get('files_examined'):
    print('Files examined:')
    for f in d['files_examined']:
        print(f\"  - {f['path']} [{f['status']}]: {f.get('notes','')}\")
    print()
if d.get('commands_tested'):
    print('Commands tested:')
    for c in d['commands_tested']:
        print(f\"  - {c['cmd']} → {c['result']}\")
    print()
if d.get('next_steps'):
    print('Next steps:')
    for s in d['next_steps']:
        print(f\"  - {s}\")
    print()
if d.get('freeform_notes'):
    print('Notes:')
    for n in d['freeform_notes']:
        print(f\"  - {n}\")
" 2>/dev/null
}

# log <task_id> <key> <value> - append to a list key
cmd_log() {
    local task_id="$1"
    local key="$2"
    local value="$3"
    local cp_file="$MEMORY_DIR/${task_id}.json"

    if [[ -z "$task_id" || -z "$key" || -z "$value" ]]; then
        echo "Usage: $0 log <task_id> <key> <value>" >&2
        echo "  key: files_examined, commands_tested, next_steps, freeform_notes" >&2
        return 1
    fi

    # Ensure checkpoint exists
    if [[ ! -f "$cp_file" ]]; then
        cmd_checkpoint "$task_id" >/dev/null
    fi

    python3 -c "
import json, sys, shlex
with open('$cp_file') as f:
    d = json.load(f)
d['last_updated'] = '$(now_iso)'
# For structured keys, append dict; for others, append string
if '$key' in ('files_examined', 'commands_tested'):
    entry = json.loads('$value')
    d.setdefault('$key', []).append(entry)
elif '$key' == 'next_steps':
    d.setdefault('next_steps', []).append('$value')
else:
    d.setdefault('freeform_notes', []).append('$value')
with open('$cp_file', 'w') as f:
    json.dump(d, f, indent=2)
" 2>/dev/null && echo "Logged to task $task_id: $key"
}

# status - show all checkpoints
cmd_status() {
    echo "=== Task Memory Checkpoints ==="
    if [[ ! -d "$MEMORY_DIR" ]] || [[ -z "$(ls -A "$MEMORY_DIR" 2>/dev/null)" ]]; then
        echo "No checkpoints found."
        return 0
    fi
    for cp in "$MEMORY_DIR"/*.json; do
        local tid
        tid=$(python3 -c "import json; d=json.load(open('$cp')); print(d['task_id'])" 2>/dev/null)
        local subj
        subj=$(python3 -c "import json; d=json.load(open('$cp')); print(d.get('subject',''))" 2>/dev/null)
        local status
        status=$(python3 -c "import json; d=json.load(open('$cp')); print(d.get('status','pending'))" 2>/dev/null)
        local updated
        updated=$(python3 -c "import json; d=json.load(open('$cp')); print(d.get('last_updated','N/A'))" 2>/dev/null)
        printf "  #%s  %-40s  [%s]  updated: %s\n" "$tid" "$subj" "$status" "$updated"
    done
}

case "${1:-help}" in
    checkpoint) cmd_checkpoint "$2" "$3" ;;
    resume)     cmd_resume "$2" ;;
    log)        cmd_log "$2" "$3" "$4" ;;
    status)     cmd_status ;;
    help|--help)
        echo "Usage: $0 <command> [args]"
        echo ""
        echo "Commands:"
        echo "  checkpoint <task_id> [subject]  Create/refresh checkpoint"
        echo "  resume <task_id>                Print checkpoint summary"
        echo "  log <task_id> <key> <value>     Append to checkpoint"
        echo "  status                          Show all checkpoints"
        echo ""
        echo "Log keys: files_examined, commands_tested, next_steps, freeform_notes"
        ;;
    *)
        echo "Unknown command: $1" >&2
        echo "Run '$0 help' for usage." >&2
        exit 1
        ;;
esac
