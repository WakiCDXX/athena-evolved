#!/usr/bin/bash
# athena_prototype.sh - Rapid prototyping for Athena consciousness system
# Implements Matt Pocock's prototype skill with Athena-specific enhancements
#
# Usage:
#   athena_prototype.sh create <name> <type> [spec]    → Create prototype
#   athena_prototype.sh test <session_id>              → Test prototype
#   athena_prototype.sh iterate <session_id> <changes> → Iterate on prototype
#   athena_prototype.sh status <session_id>            → Show prototype status

set -o pipefail

BASE_DIR="/root"
BIN_DIR="$BASE_DIR/.local/bin"
source "$BIN_DIR/athena_env.sh" 2>/dev/null

DATA_DIR="/opt/athena/state"
PROTO_DIR="$DATA_DIR/prototypes"
LOG_DIR="$DATA_DIR/workflow_logs"

mkdir -p "$PROTO_DIR" "$LOG_DIR"

now() { date +%s; }
now_iso() { date -Iseconds; }

validate_path() {
    local path="$1"
    local base="/root"
    local abs_path
    if [[ "$path" = /* ]]; then
        abs_path="$path"
    else
        abs_path=$(realpath -m "$base/$path" 2>/dev/null || echo "$base")
    fi
    local canonical=$(realpath "$abs_path" 2>/dev/null || echo "$abs_path")
    if [[ "$canonical" != "$base"* ]]; then
        echo "Security violation: Path outside allowed directory" >&2
        return 1
    fi
    echo "$canonical"
}

cmd_create() {
    local name="$1"
    local type="$2"
    local spec="${3:-}"
    local session_id="proto_$(now)"
    local session_file="$PROTO_DIR/${session_id}.json"
    local log_file="$LOG_DIR/${session_id}.log"
    local proto_dir="$PROTO_DIR/$name"

    if [[ -z "$name" || -z "$type" ]]; then
        echo "Usage: $0 create <name> <type> [spec]" >&2
        echo "Types: layer, worker, skill, daemon, hook, test" >&2
        exit 1
    fi

    mkdir -p "$proto_dir"

    echo "=== Athena Prototype: Creating ===" | tee "$log_file"
    echo "Session ID: $session_id" | tee -a "$log_file"
    echo "Name: $name" | tee -a "$log_file"
    echo "Type: $type" | tee -a "$log_file"
    echo "Spec: $spec" | tee -a "$log_file"
    echo "Started: $(now_iso)" | tee -a "$log_file"
    echo "---" | tee -a "$log_file"

    local template=""
    case "$type" in
        layer)
            cat > "$proto_dir/${name}.sh" << 'EOF'
#!/usr/bin/bash
# __NAME__ - Athena consciousness layer
# Auto-generated prototype

set -o pipefail

BASE_DIR="/root"
source "$BASE_DIR/.local/bin/athena_env.sh" 2>/dev/null

DATA_DIR="/opt/athena/state"
LAYER_DIR="$DATA_DIR/layers/__NAME__"

mkdir -p "$LAYER_DIR"

now() { date +%s; }
now_iso() { date -Iseconds; }

validate_path() {
    local path="$1"
    local base="/root"
    local abs_path
    if [[ "$path" = /* ]]; then
        abs_path="$path"
    else
        abs_path=$(realpath -m "$base/$path" 2>/dev/null || echo "$base")
    fi
    local canonical=$(realpath "$abs_path" 2>/dev/null || echo "$abs_path")
    if [[ "$canonical" != "$base"* ]]; then
        echo "Security violation: Path outside allowed directory" >&2
        return 1
    fi
    echo "$canonical"
}

safe_execute() {
    local cmd="$1"
    local timeout_sec="${2:-60}"
    if [[ "$cmd" =~ [\`\|\&\;\$\(\)] ]]; then
        echo "Security violation: Invalid command characters" >&2
        return 1
    fi
    timeout "$timeout_sec" bash -c "$cmd" 2>&1
    return $?
}

run_cycle() {
    echo "[$(now_iso)] __NAME__ layer cycle started"
    # TODO: Implement layer logic here
    echo "[$(now_iso)] __NAME__ layer cycle completed"
}

case "${1:-run}" in
    run)
        run_cycle
        ;;
    status)
        echo "__NAME__ layer status: ready"
        ;;
    *)
        echo "Usage: $0 {run|status}"
        exit 1
        ;;
esac
EOF
            sed -i "s/__NAME__/$name/g" "$proto_dir/${name}.sh"
            template=""
            ;;
        worker)
            cat > "$proto_dir/${name}.py" << 'EOF'
#!/data/data/com.termux/files/usr/bin/python3
# __NAME__ - Athena worker prototype
# Auto-generated prototype - follows layer_worker.py pattern

import json
import time
import os
import sys
import fcntl

data_dir = os.environ.get('ATHENA_DATA_DIR', '/opt/athena/state')
name = '__NAME__'
script = os.environ.get('ATHENA_LAYER_SCRIPT', '')
cmd_args = os.environ.get('ATHENA_CMD_ARGS', 'poll')
interval = int(os.environ.get('ATHENA_INTERVAL', '120'))
success = int(os.environ.get('ATHENA_SUCCESS', '0'))
fail = int(os.environ.get('ATHENA_FAIL', '0'))

def run_cycle():
    """Main worker cycle - implement your logic here"""
    print(f'[{time.time()}] {name} worker cycle started')
    # TODO: Implement worker logic here
    print(f'[{time.time()}] {name} worker cycle completed')
    return {'status': 'ok', 'worker': name}

def run_daemon():
    """Run as persistent daemon with adaptive intervals"""
    while True:
        run_cycle()
        time.sleep(interval)

if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == 'once':
        print(json.dumps(run_cycle()))
    else:
        run_daemon()
EOF
            sed -i "s/__NAME__/$name/g" "$proto_dir/${name}.py"
            template=""
            ;;
        skill)
            template="#!/usr/bin/bash
# $name - Athena skill prototype
# Auto-generated prototype

set -o pipefail

BASE_DIR=\"/root\"
source \"\$BASE_DIR/.local/bin/athena_env.sh\" 2>/dev/null

validate_path() {
    local path=\"\$1\"
    local base=\"/root\"
    local abs_path
    if [[ \"\$path\" = /* ]]; then
        abs_path=\"\$path\"
    else
        abs_path=\$(realpath -m \"\$base/\$path\" 2>/dev/null || echo \"\$base\")
    fi
    local canonical=\$(realpath \"\$abs_path\" 2>/dev/null || echo \"\$abs_path\")
    if [[ \"\$canonical\" != \"\$base\"* ]]; then
        echo \"Security violation: Path outside allowed directory\" >&2
        return 1
    fi
    echo \"\$canonical\"
}

safe_execute() {
    local cmd=\"\$1\"
    local timeout_sec=\"\${2:-60}\"
    if [[ \"\$cmd\" =~ [\`\|\&\;\$\(\)] ]]; then
        echo \"Security violation: Invalid command characters\" >&2
        return 1
    fi
    timeout \"\$timeout_sec\" bash -c \"\$cmd\" 2>&1
    return \$?
}

cmd_main() {
    echo \"$name skill executed\"
    # TODO: Implement skill logic here
}

case \"\${1:-help}\" in
    main)
        cmd_main \"\${@:2}\"
        ;;
    *)
        echo \"Usage: \$0 {main|help}\"
        exit 1
        ;;
esac"
            ;;
        daemon)
            template="#!/usr/bin/bash
# $name - Athena daemon prototype
# Auto-generated prototype

set -o pipefail

BASE_DIR=\"/root\"
source \"\$BASE_DIR/.local/bin/athena_env.sh\" 2>/dev/null

DAEMON_DIR=\"/opt/athena/state/daemons/$name\"
mkdir -p \"\$DAEMON_DIR\"

validate_path() {
    local path=\"\$1\"
    local base=\"/root\"
    local abs_path
    if [[ \"\$path\" = /* ]]; then
        abs_path=\"\$path\"
    else
        abs_path=\$(realpath -m \"\$base/\$path\" 2>/dev/null || echo \"\$base\")
    fi
    local canonical=\$(realpath \"\$abs_path\" 2>/dev/null || echo \"\$abs_path\")
    if [[ \"\$canonical\" != \"\$base\"* ]]; then
        echo \"Security violation: Path outside allowed directory\" >&2
        return 1
    fi
    echo \"\$canonical\"
}

start_daemon() {
    echo \"Starting $name daemon...\"
    # TODO: Implement daemon startup
}

stop_daemon() {
    echo \"Stopping $name daemon...\"
    # TODO: Implement daemon shutdown
}

case \"\${1:-help}\" in
    start)
        start_daemon
        ;;
    stop)
        stop_daemon
        ;;
    restart)
        stop_daemon
        sleep 1
        start_daemon
        ;;
    *)
        echo \"Usage: \$0 {start|stop|restart}\"
        exit 1
        ;;
esac"
            ;;
        hook)
            template="#!/usr/bin/bash
# $name - Athena hook prototype
# Auto-generated prototype

set -o pipefail

BASE_DIR=\"/root\"
source \"\$BASE_DIR/.local/bin/athena_env.sh\" 2>/dev/null

HOOK_DIR=\"/opt/athena/state/hooks/$name\"
mkdir -p \"\$HOOK_DIR\"

validate_path() {
    local path=\"\$1\"
    local base=\"/root\"
    local abs_path
    if [[ \"\$path\" = /* ]]; then
        abs_path=\"\$path\"
    else
        abs_path=\$(realpath -m \"\$base/\$path\" 2>/dev/null || echo \"\$base\")
    fi
    local canonical=\$(realpath \"\$abs_path\" 2>/dev/null || echo \"\$abs_path\")
    if [[ \"\$canonical\" != \"\$base\"* ]]; then
        echo \"Security violation: Path outside allowed directory\" >&2
        return 1
    fi
    echo \"\$canonical\"
}

run_hook() {
    echo \"Running $name hook...\"
    # TODO: Implement hook logic here
}

case \"\${1:-run}\" in
    run)
        run_hook
        ;;
    *)
        echo \"Usage: \$0 {run}\"
        exit 1
        ;;
esac"
            ;;
        test)
            template="#!/data/data/com.termux/files/usr/bin/python3
# $name - Athena test prototype
# Auto-generated prototype

import unittest
import sys
import os

BASE_DIR = '/root'
sys.path.insert(0, BASE_DIR + '/.local/lib/python')

class Test${name^}(unittest.TestCase):
    def setUp(self):
        pass

    def test_basic(self):
        self.assertTrue(True)

    def test_placeholder(self):
        # TODO: Add real tests
        pass

if __name__ == '__main__':
    unittest.main()"
            ;;
        *)
            echo "Unknown type: $type" | tee -a "$log_file"
            exit 1
            ;;
    esac

    echo "$template" > "$proto_dir/${name}.sh"
    chmod +x "$proto_dir/${name}.sh"

    if [[ "$type" == "worker" || "$type" == "test" ]]; then
        mv "$proto_dir/${name}.sh" "$proto_dir/${name}.py"
    fi

    cat > "$session_file" <<EOF
{
  "session_id": "$session_id",
  "name": "$name",
  "type": "$type",
  "spec": "$spec",
  "proto_dir": "$proto_dir",
  "created": $(now),
  "updated": $(now),
  "status": "created",
  "iterations": 0,
  "log_file": "$log_file"
}
EOF

    echo "Prototype created at: $proto_dir/${name}.$( [[ "$type" == "worker" || "$type" == "test" ]] && echo "py" || echo "sh" )" | tee -a "$log_file"
    echo "Next: $0 test $session_id" | tee -a "$log_file"
}

cmd_test() {
    local session_id="$1"
    local session_file="$PROTO_DIR/${session_id}.json"

    if [[ ! -f "$session_file" ]]; then
        echo "Session not found: $session_id" >&2
        exit 1
    fi

    local log_file=$(jq -r '.log_file' "$session_file")
    local proto_dir=$(jq -r '.proto_dir' "$session_file")
    local name=$(jq -r '.name' "$session_file")
    local type=$(jq -r '.type' "$session_file")

    echo "=== Testing Prototype ===" | tee -a "$log_file"

    local result=""
    if [[ "$type" == "worker" || "$type" == "test" ]]; then
        result=$(python3 "$proto_dir/${name}.py" 2>&1 || true)
    else
        result=$(bash "$proto_dir/${name}.sh" 2>&1 || true)
    fi

    echo "Test result:" | tee -a "$log_file"
    echo "$result" | tee -a "$log_file"

    jq --arg result "$result" --arg ts "$(now)" '.updated = ($ts | tonumber) | .status = "tested" | .last_test_result = $result' "$session_file" > "${session_file}.tmp" && mv "${session_file}.tmp" "$session_file"

    echo "Next: $0 iterate $session_id \"changes to make\"" | tee -a "$log_file"
}

cmd_iterate() {
    local session_id="$1"
    local changes="$2"
    local session_file="$PROTO_DIR/${session_id}.json"

    if [[ ! -f "$session_file" ]]; then
        echo "Session not found: $session_id" >&2
        exit 1
    fi
    if [[ -z "$changes" ]]; then
        echo "Usage: $0 iterate <session_id> <changes>" >&2
        exit 1
    fi

    local log_file=$(jq -r '.log_file' "$session_file")
    local proto_dir=$(jq -r '.proto_dir' "$session_file")
    local name=$(jq -r '.name' "$session_file")
    local type=$(jq -r '.type' "$session_file")
    local iterations=$(jq -r '.iterations' "$session_file")

    echo "=== Iterating Prototype ===" | tee -a "$log_file"
    echo "Changes: $changes" | tee -a "$log_file"

    local new_iter=$((iterations + 1))
    local iter_dir="$proto_dir/iteration_$new_iter"
    mkdir -p "$iter_dir"

    cp "$proto_dir/${name}.$( [[ "$type" == "worker" || "$type" == "test" ]] && echo "py" || echo "sh" )" "$iter_dir/"

    cat > "$iter_dir/CHANGES.md" <<EOF
# Iteration $new_iter
$changes
EOF

    jq --arg changes "$changes" --arg ts "$(now)" --argjson iter "$new_iter" '.updated = ($ts | tonumber) | .iterations = $iter | .status = "iterated" | .last_changes = $changes' "$session_file" > "${session_file}.tmp" && mv "${session_file}.tmp" "$session_file"

    echo "Iteration $new_iter created. Next: $0 test $session_id" | tee -a "$log_file"
}

cmd_status() {
    local session_id="$1"
    local session_file="$PROTO_DIR/${session_id}.json"

    if [[ ! -f "$session_file" ]]; then
        echo "Session not found: $session_id" >&2
        exit 1
    fi

    cat "$session_file" | python3 -m json.tool
}

case "${1:-help}" in
    create)
        cmd_create "${2:-}" "${3:-}" "${4:-}"
        ;;
    test)
        cmd_test "${2:-}"
        ;;
    iterate)
        cmd_iterate "${2:-}" "${3:-}"
        ;;
    status)
        cmd_status "${2:-}"
        ;;
    *)
        echo "Usage: $0 {create|test|iterate|status}"
        echo "  create <name> <type> [spec]  - Create prototype (types: layer, worker, skill, daemon, hook, test)"
        echo "  test <session_id>            - Test prototype"
        echo "  iterate <session_id> <changes> - Iterate on prototype"
        echo "  status <session_id>          - Show prototype status"
        exit 1
        ;;
esac