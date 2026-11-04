#!/bin/bash
# =============================================================================
# Athena Environmental Message Planting
#
# Plants messages in the environment for other agents/layers to discover.
# Uses filesystem-based message passing with TTL, priority, and targeting.
# =============================================================================

set -euo pipefail

DATA_DIR="${DATA_DIR:-/opt/athena/state}"
MESSAGE_DIR="${MESSAGE_DIR:-$DATA_DIR/messages}"
SCRIPT_NAME="$(basename "$0")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

mkdir -p "$MESSAGE_DIR"/{inbox,outbox,broadcast,archive}

print_usage() {
    cat <<EOF
${BOLD}Athena Environmental Message Planting${NC}

Usage: $SCRIPT_NAME [OPTIONS] <COMMAND> [ARGS]

Commands:
    plant <target> <message>        Plant a message for specific target
    broadcast <message>             Broadcast message to all listeners
    harvest [target]                Collect messages for target (or all)
    list [target]                   List messages for target (or all)
    clear <target>                  Clear all messages for target
    purge                           Purge expired messages
    stats                           Show message statistics

Options:
    -t, --ttl SECONDS      Time-to-live in seconds (default: 3600)
    -p, --priority LEVEL   Priority: low, normal, high, critical (default: normal)
    -s, --source NAME      Source identifier (default: script name)
    -k, --key VALUE        Key for structured messages
    -v, --value VALUE      Value for structured messages
    -j, --json             Input/output as JSON
    -h, --help             Show this help

Targets:
    Layer names: body, emotions, continuity, attention, introspection, doubt,
                 volition, memory, senses, heartbeat, archive, memory_backup,
                 tropical, padic, nsa, bioelectric, multiway, xna, shadow,
                 aihs, metabolic, chiral, wayfinder, implement_spec, tdd,
                 handoff, to_spec, workflow_chain, openappa, archestra, vera_cpu
    Special: all, daemon, watchdog, xenobiological, main_daemon

Examples:
    $SCRIPT_NAME plant attention "Focus on sensory input"
    $SCRIPT_NAME plant all --priority high "System entering degraded mode"
    $SCRIPT_NAME broadcast --ttl 7200 "New LLM model available"
    $SCRIPT_NAME harvest attention
    $SCRIPT_NAME list --json
    $SCRIPT_NAME purge

Message Format (JSON):
    {
        "id": "uuid",
        "source": "script_name",
        "target": "attention",
        "priority": "normal",
        "ttl": 3600,
        "created": 1234567890,
        "expires": 1234567890,
        "key": "directive",
        "value": "Focus on sensory input",
        "metadata": {}
    }
EOF
}

# Generate unique message ID
gen_id() {
    echo "$(date +%s%N)-$(shuf -i 1000-9999 -n 1)"
}

# Validate priority
validate_priority() {
    case "$1" in
        low|normal|high|critical) return 0 ;;
        *) return 1 ;;
    esac
}

# Get target directory
target_dir() {
    local target="$1"
    if [ "$target" = "all" ] || [ "$target" = "broadcast" ]; then
        echo "$MESSAGE_DIR/broadcast"
    else
        echo "$MESSAGE_DIR/inbox/$target"
    fi
}

# Plant a message
cmd_plant() {
    local target="${1:-}"
    local message="${2:-}"

    if [ -z "$target" ] || [ -z "$message" ]; then
        echo -e "${RED}Error: plant requires <target> and <message>${NC}" >&2
        return 1
    fi

    local dir=$(target_dir "$target")
    mkdir -p "$dir"

    local id=$(gen_id)
    local created=$(date +%s)
    local expires=$((created + TTL))

    # Build message JSON
    local msg_json
    if [ "$USE_JSON" = "true" ]; then
        msg_json="$message"
    else
        msg_json=$(cat <<EOF
{
    "id": "$id",
    "source": "$SOURCE",
    "target": "$target",
    "priority": "$PRIORITY",
    "ttl": $TTL,
    "created": $created,
    "expires": $expires,
    "key": "${KEY:-message}",
    "value": $(echo "$message" | jq -Rs .),
    "metadata": {}
}
EOF
)
    fi

    # Write message file
    echo "$msg_json" > "$dir/$id.json"

    # Also write to outbox for audit trail
    mkdir -p "$MESSAGE_DIR/outbox"
    echo "$msg_json" > "$MESSAGE_DIR/outbox/$id.json"

    if [ "$USE_JSON" = "true" ]; then
        echo "$msg_json"
    else
        echo -e "${GREEN}Planted message ${CYAN}$id${GREEN} for ${CYAN}$target${GREEN} (priority: $PRIORITY, TTL: ${TTL}s)${NC}"
    fi
}

# Broadcast a message
cmd_broadcast() {
    local message="${1:-}"

    if [ -z "$message" ]; then
        echo -e "${RED}Error: broadcast requires <message>${NC}" >&2
        return 1
    fi

    cmd_plant "broadcast" "$message"
}

# Harvest (collect and remove) messages for a target
cmd_harvest() {
    local target="${1:-all}"
    local results=()
    local count=0

    if [ "$target" = "all" ]; then
        # Harvest from all inboxes
        for dir in "$MESSAGE_DIR/inbox"/*/; do
            [ -d "$dir" ] || continue
            local t=$(basename "$dir")
            for msg_file in "$dir"/*.json; do
                [ -f "$msg_file" ] || continue
                if [ "$USE_JSON" = "true" ]; then
                    cat "$msg_file"
                else
                    cat "$msg_file" | jq -r '"\(.created) [\(.priority)] \(.key): \(.value)"'
                fi
                mv "$msg_file" "$MESSAGE_DIR/archive/$(basename "$msg_file")"
                count=$((count + 1))
            done
        done
        # Also harvest broadcast
        for msg_file in "$MESSAGE_DIR/broadcast"/*.json; do
            [ -f "$msg_file" ] || continue
            if [ "$USE_JSON" = "true" ]; then
                cat "$msg_file"
            else
                cat "$msg_file" | jq -r '"\(.created) [\(.priority)] \(.key): \(.value)"'
            fi
            mv "$msg_file" "$MESSAGE_DIR/archive/$(basename "$msg_file")"
            count=$((count + 1))
        done
    else
        local dir=$(target_dir "$target")
        for msg_file in "$dir"/*.json; do
            [ -f "$msg_file" ] || continue
            if [ "$USE_JSON" = "true" ]; then
                cat "$msg_file"
            else
                cat "$msg_file" | jq -r '"\(.created) [\(.priority)] \(.key): \(.value)"'
            fi
            mv "$msg_file" "$MESSAGE_DIR/archive/$(basename "$msg_file")"
            count=$((count + 1))
        done
    fi

    if [ "$USE_JSON" != "true" ]; then
        echo -e "${GREEN}Harvested $count message(s) for $target${NC}"
    fi
}

# List messages for a target
cmd_list() {
    local target="${1:-all}"
    local count=0

    if [ "$target" = "all" ]; then
        for dir in "$MESSAGE_DIR/inbox"/*/; do
            [ -d "$dir" ] || continue
            local t=$(basename "$dir")
            for msg_file in "$dir"/*.json; do
                [ -f "$msg_file" ] || continue
                if [ "$USE_JSON" = "true" ]; then
                    cat "$msg_file"
                else
                    local age=$(($(date +%s) - $(jq -r '.created' "$msg_file")))
                    echo -e "  ${CYAN}$t${NC}: $(jq -r '.key' "$msg_file") [$(jq -r '.priority' "$msg_file")] age=${age}s"
                fi
                count=$((count + 1))
            done
        done
        for msg_file in "$MESSAGE_DIR/broadcast"/*.json; do
            [ -f "$msg_file" ] || continue
            if [ "$USE_JSON" = "true" ]; then
                cat "$msg_file"
            else
                local age=$(($(date +%s) - $(jq -r '.created' "$msg_file")))
                echo -e "  ${CYAN}broadcast${NC}: $(jq -r '.key' "$msg_file") [$(jq -r '.priority' "$msg_file")] age=${age}s"
            fi
            count=$((count + 1))
        done
    else
        local dir=$(target_dir "$target")
        for msg_file in "$dir"/*.json; do
            [ -f "$msg_file" ] || continue
            if [ "$USE_JSON" = "true" ]; then
                cat "$msg_file"
            else
                local age=$(($(date +%s) - $(jq -r '.created' "$msg_file")))
                echo -e "  ${CYAN}$target${NC}: $(jq -r '.key' "$msg_file") [$(jq -r '.priority' "$msg_file")] age=${age}s"
            fi
            count=$((count + 1))
        done
    fi

    if [ "$USE_JSON" != "true" ]; then
        echo -e "${GREEN}Total: $count message(s)${NC}"
    fi
}

# Clear messages for a target
cmd_clear() {
    local target="${1:-}"

    if [ -z "$target" ]; then
        echo -e "${RED}Error: clear requires <target>${NC}" >&2
        return 1
    fi

    local dir=$(target_dir "$target")
    local count=0

    for msg_file in "$dir"/*.json; do
        [ -f "$msg_file" ] || continue
        mv "$msg_file" "$MESSAGE_DIR/archive/$(basename "$msg_file")"
        count=$((count + 1))
    done

    echo -e "${GREEN}Cleared $count message(s) for $target${NC}"
}

# Purge expired messages
cmd_purge() {
    local now=$(date +%s)
    local count=0

    for dir in "$MESSAGE_DIR/inbox"/*/ "$MESSAGE_DIR/broadcast"/; do
        [ -d "$dir" ] || continue
        for msg_file in "$dir"/*.json; do
            [ -f "$msg_file" ] || continue
            local expires=$(jq -r '.expires // 0' "$msg_file" 2>/dev/null || echo 0)
            if [ "$expires" -gt 0 ] && [ "$now" -gt "$expires" ]; then
                mv "$msg_file" "$MESSAGE_DIR/archive/$(basename "$msg_file").expired"
                count=$((count + 1))
            fi
        done
    done

    # Also clean old archive entries (older than 7 days)
    local week_ago=$((now - 604800))
    for msg_file in "$MESSAGE_DIR/archive"/*.json*; do
        [ -f "$msg_file" ] || continue
        local mtime=$(stat -c %Y "$msg_file" 2>/dev/null || echo $now)
        if [ "$mtime" -lt "$week_ago" ]; then
            rm -f "$msg_file"
        fi
    done

    echo -e "${GREEN}Purged $count expired message(s)${NC}"
}

# Show statistics
cmd_stats() {
    local now=$(date +%s)
    local total=0
    local expired=0
    local by_priority=()
    local by_target=()

    echo -e "${BOLD}Message Statistics${NC}"
    echo "==================="

    for dir in "$MESSAGE_DIR/inbox"/*/; do
        [ -d "$dir" ] || continue
        local t=$(basename "$dir")
        local tcount=0
        for msg_file in "$dir"/*.json; do
            [ -f "$msg_file" ] || continue
            local expires=$(jq -r '.expires // 0' "$msg_file" 2>/dev/null || echo 0)
            local priority=$(jq -r '.priority // "normal"' "$msg_file" 2>/dev/null || echo "normal")
            if [ "$expires" -gt 0 ] && [ "$now" -gt "$expires" ]; then
                expired=$((expired + 1))
            fi
            total=$((total + 1))
            tcount=$((tcount + 1))
        done
        if [ $tcount -gt 0 ]; then
            echo -e "  ${CYAN}$t${NC}: $tcount"
        fi
    done

    for msg_file in "$MESSAGE_DIR/broadcast"/*.json; do
        [ -f "$msg_file" ] || continue
        local expires=$(jq -r '.expires // 0' "$msg_file" 2>/dev/null || echo 0)
        if [ "$expires" -gt 0 ] && [ "$now" -gt "$expires" ]; then
            expired=$((expired + 1))
        fi
        total=$((total + 1))
    done

    echo -e "  ${CYAN}broadcast${NC}: $(ls -1 "$MESSAGE_DIR/broadcast"/*.json 2>/dev/null | wc -l)"
    echo -e "  ${CYAN}archive${NC}: $(ls -1 "$MESSAGE_DIR/archive"/*.json* 2>/dev/null | wc -l)"
    echo -e "  ${CYAN}outbox${NC}: $(ls -1 "$MESSAGE_DIR/outbox"/*.json 2>/dev/null | wc -l)"
    echo -e "  ${BOLD}Total active${NC}: $total"
    echo -e "  ${RED}Expired${NC}: $expired"
}

# Parse command line - first pass: extract command
CMD=""
for arg in "$@"; do
    case "$arg" in
        plant|broadcast|harvest|list|clear|purge|stats)
            CMD="$arg"
            break
            ;;
    esac
done

if [ -z "$CMD" ]; then
    echo -e "${RED}Error: no command specified${NC}" >&2
    print_usage
    exit 1
fi

# Remove command from args
ARGS=()
CMD_FOUND=false
for arg in "$@"; do
    if [ "$CMD_FOUND" = "true" ]; then
        ARGS+=("$arg")
    elif [ "$arg" = "$CMD" ]; then
        CMD_FOUND=true
    fi
done

# Second pass: parse options from remaining args
TARGET=""
MESSAGE=""
TTL=3600
PRIORITY="normal"
SOURCE="$SCRIPT_NAME"
KEY=""
VALUE=""
USE_JSON=false

while [ ${#ARGS[@]} -gt 0 ]; do
    case "${ARGS[0]}" in
        -t|--ttl)
            TTL="${ARGS[1]}"
            ARGS=("${ARGS[@]:2}")
            ;;
        -p|--priority)
            PRIORITY="${ARGS[1]}"
            ARGS=("${ARGS[@]:2}")
            ;;
        -s|--source)
            SOURCE="${ARGS[1]}"
            ARGS=("${ARGS[@]:2}")
            ;;
        -k|--key)
            KEY="${ARGS[1]}"
            ARGS=("${ARGS[@]:2}")
            ;;
        -v|--value)
            VALUE="${ARGS[1]}"
            ARGS=("${ARGS[@]:2}")
            ;;
        -j|--json)
            USE_JSON=true
            ARGS=("${ARGS[@]:1}")
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            break
            ;;
    esac
done

# Remaining positional args
if [ "$CMD" = "plant" ]; then
    TARGET="${ARGS[0]:-}"
    MESSAGE="${ARGS[1]:-}"
elif [ "$CMD" = "broadcast" ]; then
    MESSAGE="${ARGS[0]:-}"
elif [ "$CMD" = "harvest" ] || [ "$CMD" = "list" ] || [ "$CMD" = "clear" ]; then
    TARGET="${ARGS[0]:-all}"
fi

# Validate priority
if ! validate_priority "$PRIORITY"; then
    echo -e "${RED}Error: invalid priority '$PRIORITY' (must be low|normal|high|critical)${NC}" >&2
    exit 1
fi

# Execute command
case "$CMD" in
    plant)
        cmd_plant "$TARGET" "$MESSAGE"
        ;;
    broadcast)
        cmd_broadcast "$MESSAGE"
        ;;
    harvest)
        cmd_harvest "$TARGET"
        ;;
    list)
        cmd_list "$TARGET"
        ;;
    clear)
        cmd_clear "$TARGET"
        ;;
    purge)
        cmd_purge
        ;;
    stats)
        cmd_stats
        ;;
    "")
        echo -e "${RED}Error: no command specified${NC}" >&2
        print_usage
        exit 1
        ;;
    *)
        echo -e "${RED}Error: unknown command '$CMD'${NC}" >&2
        print_usage
        exit 1
        ;;
esac