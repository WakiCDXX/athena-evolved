#!/bin/bash
# athena_handoff.sh - Progress tracking and handoff management for Athena
# Implements Matt Pocock's /handoff skill with Athena-specific enhancements

# Source Athena environment configuration
source "/opt/athena/bin/athena_env.sh"

# Security and validation functions

# Safe path validation - restrict to allowed directories
validate_and_sanitize_path() {
    local input_path="$1"
    local base_path="/root"

    # Convert to absolute path
    local abs_path
    if [[ "$input_path" = /* ]]; then
        abs_path="$input_path"
    else
        abs_path="$(realpath -m "$base_path/$input_path" 2>/dev/null || echo "$base_path")"
    fi

    # Resolve to canonical path
    local canonical_path
    canonical_path=$(realpath "$abs_path" 2>/dev/null || echo "$abs_path")

    # Ensure path is within allowed base directory
    if [[ "$canonical_path" != "$base_path"* ]]; then
        echo "Security violation: Path $input_path resolves outside allowed directory" >&2
        return 1
    fi

    echo "$canonical_path"
    return 0
}

# Safe command execution with timeout and validation
safe_execute() {
    local command="$1"
    local timeout_seconds="$2"

    # Basic command validation - check for dangerous patterns
    local semicolon=";"
    if [[ "$command" =~ ${semicolon}(\s*rm\s+-rf|${semicolon}\s*rm\s+-rf\s*) ]]; then
        echo "Security violation: Dangerous command detected" >&2
        return 1
    fi

    # Enhanced validation - prevent command injection
    if [[ "$command" =~ [\`\|\&\;] ]]; then
        echo "Security violation: Invalid command characters detected" >&2
        return 1
    fi

    # Validate command length
    if [[ ${#command} -gt 1000 ]]; then
        echo "Security violation: Command too long" >&2
        return 1
    fi

    # Execute with timeout
    timeout "$timeout_seconds" bash -c "$command" 2>/dev/null
    return $?
}

# Initialize handoff variables with validation
HANDOFF_MODE="${1:-track}"
TARGET_PROGRESS="${2:-}"
HANDOFF_TYPE="${3:-task}"
TARGET_AGENT="${4:-}"
PROGRESS_THRESHOLD="${5:-80}"
TRANSITION_TYPE="${6:-smooth}"
OUTPUT_DIR="${7:-/root/.local/share/athena_handoffs}"
AWARENESS_LEVEL="${8:-full}"

# Security rate limiting
RATE_LIMIT_DURATION=60
RATE_LIMIT_COUNT=10
declare -A RATE_LIMIT_COUNTER

# Validate mode
if [[ ! "$HANDOFF_MODE" =~ ^(track|transition|report|sync|export|lifecycle|full)$ ]]; then
    echo "Error: Invalid mode. Use: track, transition, report, sync, export, lifecycle, or full" >&2
    exit 1
fi

# Validate handoff type (only for modes that use it)
if [[ "$HANDOFF_MODE" != "track" && "$HANDOFF_MODE" != "report" && "$HANDOFF_MODE" != "full" && "$HANDOFF_MODE" != "sync" && "$HANDOFF_MODE" != "lifecycle" ]]; then
    if [[ ! "$HANDOFF_TYPE" =~ ^(task|agent|session|state)$ ]]; then
        echo "Error: Invalid handoff type. Use: task, agent, session, or state" >&2
        exit 1
    fi
fi

# Validate transition type
if [[ ! "$TRANSITION_TYPE" =~ ^(smooth|abrupt|conditional)$ ]]; then
    echo "Error: Invalid transition type. Use: smooth, abrupt, or conditional" >&2
    exit 1
fi

# Validate awareness level
if [[ ! "$AWARENESS_LEVEL" =~ ^(full|summary|minimal)$ ]]; then
    echo "Error: Invalid awareness level. Use: full, summary, or minimal" >&2
    exit 1
fi

# Performance optimization with safe limits
MAX_TRACKING_SESSIONS=100
TIMEOUT_SECONDS=180

# Rate limiting security
RATE_LIMIT_WINDOW=60

# Initialize handoff tracking with size limits
HANDOFF_SESSIONS=()
TRANSITION_LOG=()
PROGRESS_REPORTS=()
AWARENESS_STATE=()

# Create output directories with validation
mkdir -p "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/sessions"
mkdir -p "$OUTPUT_DIR/transitions"
mkdir -p "$OUTPUT_DIR/reports"

# Validate output directories
if [[ ! -d "$OUTPUT_DIR" ]] || [[ ! -w "$OUTPUT_DIR" ]]; then
    echo "Error: Output directory not accessible: $OUTPUT_DIR" >&2
    exit 1
fi

# Validate session directory
if [[ ! -d "$OUTPUT_DIR/sessions" ]] || [[ ! -w "$OUTPUT_DIR/sessions" ]]; then
    echo "Error: Sessions directory not accessible" >&2
    exit 1
fi

# Validate transition directory
if [[ ! -d "$OUTPUT_DIR/transitions" ]] || [[ ! -w "$OUTPUT_DIR/transitions" ]]; then
    echo "Error: Transitions directory not accessible" >&2
    exit 1
fi

# Validate reports directory
if [[ ! -d "$OUTPUT_DIR/reports" ]] || [[ ! -w "$OUTPUT_DIR/reports" ]]; then
    echo "Error: Reports directory not accessible" >&2
    exit 1
fi

# Security: Validate output directories are safe (no symlinks, proper ownership)
if [[ -L "$OUTPUT_DIR" ]]; then
    echo "Security violation: Output directory is a symlink" >&2
    exit 1
fi

if [[ -L "$OUTPUT_DIR/sessions" ]] || [[ -L "$OUTPUT_DIR/transitions" ]] || [[ -L "$OUTPUT_DIR/reports" ]]; then
    echo "Security violation: Subdirectories contain symlinks" >&2
    exit 1
fi

# Function to track progress with rate limiting
track_progress() {
    local session_id="${1:-SESSION_$(date +%s)}"
    local progress_value="${2:-0}"
    local description="${3:-}"
    local agent_name="${4:-}"

    # Rate limiting check
    local client_ip="$(echo $SSH_CLIENT | awk '{print $1}')"
    if [[ -n "$client_ip" ]]; then
        local current_time=$(date +%s)
        local rate_key="$client_ip:$session_id"

        if [[ -n "${RATE_LIMIT_COUNTER[$rate_key]}" ]]; then
            local last_call_time="${RATE_LIMIT_COUNTER[$rate_key]%:*}"
            local call_count="${RATE_LIMIT_COUNTER[$rate_key]#*:}"

            if (( current_time - last_call_time < RATE_LIMIT_WINDOW )); then
                if (( call_count >= RATE_LIMIT_COUNT )); then
                    echo "Security violation: Rate limit exceeded for client $client_ip" >&2
                    return 1
                fi
                RATE_LIMIT_COUNTER["$rate_key"]=$((last_call_time + RATE_LIMIT_WINDOW)): $((call_count + 1))
            else
                RATE_LIMIT_COUNTER["$rate_key"]="$current_time:1"
            fi
        else
            RATE_LIMIT_COUNTER["$rate_key"]="$current_time:1"
        fi
    fi

    echo "=== Athena Handoff Progress Tracking ===" >&2
    echo "Session ID: $session_id" >&2
    echo "Progress: $progress_value%" >&2
    echo "Description: $description" >&2
    echo "Agent: $agent_name" >&2
    echo "---" >&2

    local session_entry="Session: $session_id\n"
    session_entry="${session_entry}Progress: $progress_value%\n"
    session_entry="${session_entry}Description: $description\n"
    session_entry="${session_entry}Agent: $agent_name\n"
    session_entry="${session_entry}Timestamp: $(date -Iseconds)\n"
    session_entry="${session_entry}Threshold: $PROGRESS_THRESHOLD%\n"

    # Calculate status
    local status=""
    if [[ $progress_value -eq 0 ]]; then
        status="NOT_STARTED"
    elif [[ $progress_value -lt $PROGRESS_THRESHOLD ]]; then
        status="IN_PROGRESS"
    elif [[ $progress_value -eq $PROGRESS_THRESHOLD ]]; then
        status="THRESHOLD_REACHED"
    elif [[ $progress_value -gt $PROGRESS_THRESHOLD && $progress_value -lt 100 ]]; then
        status="OVER_THRESHOLD"
    elif [[ $progress_value -eq 100 ]]; then
        status="COMPLETED"
    else
        status="UNKNOWN"
    fi

    session_entry="${session_entry}Status: $status\n"

    # Add awareness to state
    add_awareness_state "session" "$session_entry"

    # Add to sessions
    HANDOFF_SESSIONS+=("$session_entry")

    # Display based on awareness level
    case "$AWARENESS_LEVEL" in
        "full")
            echo "$session_entry"
            ;;
        "summary")
            echo "Session $session_id: $progress_value% - $status"
            ;;
        "minimal")
            echo "Progress update: $session_id -> $progress_value%"
            ;;
    esac

    return 0
}

# Function to manage transitions with security validation
manage_transition() {
    local from_state="${1:-}"
    local to_state="${2:-}"
    local transition_context="${3:-}"
    local transition_agent="${4:-}"

    # Validate transition states
    if [[ -z "$from_state" || -z "$to_state" ]]; then
        echo "Error: Both source and destination states must be specified" >&2
        return 1
    fi

    # Validate states contain only safe characters
    if [[ "$from_state" =~ [^[:alnum:]_-] ]] || [[ "$to_state" =~ [^[:alnum:]_-] ]]; then
        echo "Security violation: Invalid state names" >&2
        return 1
    fi

    # Input sanitization for transition context
    if [[ -n "$transition_context" ]]; then
        # Remove potentially dangerous characters
        transition_context=${transition_context//\;/ }
        transition_context=${transition_context//\&/ }
        transition_context=${transition_context//\|/ }
        transition_context=${transition_context//\`/ }
        transition_context=${transition_context//\"/ }
        transition_context=${transition_context//\'/ }
        # Limit context length
        if [[ ${#transition_context} -gt 500 ]]; then
            echo "Security warning: Transition context too long, truncating" >&2
            transition_context="${transition_context:0:500}"
        fi
    fi

    echo "=== Athena Handoff Transition Management ===" >&2
    echo "From State: $from_state" >&2
    echo "To State: $to_state" >&2
    echo "Context: $transition_context" >&2
    echo "Agent: $transition_agent" >&2
    echo "---" >&2

    local transition_entry="Transition: $(date -Iseconds)\n"
    transition_entry="${transition_entry}From: $from_state\n"
    transition_entry="${transition_entry}To: $to_state\n"
    transition_entry="${transition_entry}Context: $transition_context\n"
    transition_entry="${transition_entry}Agent: $transition_agent\n"
    transition_entry="${transition_entry}Type: $TRANSITION_TYPE\n"

    # Determine transition status
    local transition_status=""
    case "$TRANSITION_TYPE" in
        "smooth")
            transition_status="SMOOTH"
            ;;
        "forced")
            transition_status="FORCED"
            ;;
        "gradual")
            transition_status="GRADUAL"
            ;;
        "abrupt")
            transition_status="ABRUPT"
            ;;
        *)
            transition_status="UNKNOWN"
            ;;
    esac

    transition_entry="${transition_entry}Status: $transition_status\n"

    # Log transition
    TRANSITION_LOG+=("$transition_entry")

    # Add awareness to state
    add_awareness_state "transition" "$transition_entry"

    # Display transition
    echo "$transition_entry"
    echo "Transition completed: $from_state -> $to_state ($transition_status)" >&2

    return 0
}

# Function to generate progress report
generate_progress_report() {
    local session_filter="${1:-}"
    local report_type="${2:-comprehensive}"
    local report_file="${3:-$OUTPUT_DIR/reports/progress_report_$(date +%Y%m%d_%H%M%S).txt}"

    echo "=== Athena Handoff Progress Report ===" >&2
    echo "Session Filter: $session_filter" >&2
    echo "Report Type: $report_type" >&2
    echo "Report File: $report_file" >&2
    echo "---" >&2

    # Create report
    cat > "$report_file" << EOF
Athena Handoff Progress Report
===============================
Generated: $(date -Iseconds)
Session Filter: $session_filter
Report Type: $report_type

Session Summary:
EOF

    # Filter and display sessions
    local filtered_sessions=()
    for session in "${HANDOFF_SESSIONS[@]}"; do
        if [[ -n "$session_filter" ]] && [[ "$session" == *"$session_filter"* ]]; then
            filtered_sessions+=("$session")
        elif [[ -z "$session_filter" ]]; then
            filtered_sessions+=("$session")
        fi
    done

    # Add sessions to report
    for session in "${filtered_sessions[@]}"; do
        echo "  - $session" >> "$report_file"
    done

    cat >> "$report_file" << EOF

Transition Summary:
EOF

    for transition in "${TRANSITION_LOG[@]}"; do
        echo "  - $transition" >> "$report_file"
    done

    cat >> "$report_file" << EOF

Awareness State:
EOF

    for awareness in "${AWARENESS_STATE[@]}"; do
        echo "  - $awareness" >> "$report_file"
    done

    cat >> "$report_file" << EOF

Report Metadata:
Timestamp: $(date -Iseconds)
Max Sessions: $MAX_TRACKING_SESSIONS
Timeout Seconds: $TIMEOUT_SECONDS
AWARENESS_LEVEL: $AWARENESS_LEVEL

Generated by: Athena Handoff System
EOF

    echo "Progress report saved to: $report_file" >&2
    PROGRESS_REPORTS+=("$report_file")

    return 0
}

# Function to add awareness state
add_awareness_state() {
    local state_type="$1"
    local state_data="$2"

    local awareness_entry=""
    awareness_entry="$(date -Iseconds): $state_type: $state_data\n"

    # Check if state is within consciousness layers
    case "$state_type" in
        "session")
            # Check if session exists in memory layer
            local session_count=$(find "$OUTPUT_DIR/sessions" -name "*.json" 2>/dev/null | wc -l)
            if [[ $session_count -eq 0 ]]; then
                # Create memory layer structure
                mkdir -p "$OUTPUT_DIR/sessions"
            fi
            ;;

        "transition")
            # Check if transition is in continuity layer
            local transition_count=$(find "$OUTPUT_DIR/transitions" -name "*.json" 2>/dev/null | wc -l)
            if [[ $transition_count -eq 0 ]]; then
                mkdir -p "$OUTPUT_DIR/transitions"
            fi
            ;;

        "awareness")
            # Check if awareness is in attention layer
            local awareness_count=$(find "$OUTPUT_DIR/awareness" -name "*.json" 2>/dev/null | wc -l)
            if [[ $awareness_count -eq 0 ]]; then
                mkdir -p "$OUTPUT_DIR/awareness"
            fi
            ;;
    esac

    # Add to awareness state
    AWARENESS_STATE+=("$awareness_entry")

    return 0
}

# Function to sync with target agent with security validation
sync_with_agent() {
    local target_agent="${1:-}"
    local sync_data="${2:-}"
    local sync_mode="${3:-bidirectional}"

    # Validate target agent name
    if [[ -z "$target_agent" ]]; then
        echo "Error: Target agent cannot be empty" >&2
        return 1
    fi

    if [[ "$target_agent" =~ [^[:alnum:]_-] ]]; then
        echo "Security violation: Invalid agent name" >&2
        return 1
    fi

    # Input sanitization for sync data
    if [[ -n "$sync_data" ]]; then
        sync_data=${sync_data//\;/ }
        sync_data=${sync_data//\&/ }
        sync_data=${sync_data//\|/ }
        if [[ ${#sync_data} -gt 1000 ]]; then
            echo "Security warning: Sync data too long, truncating" >&2
            sync_data="${sync_data:0:1000}"
        fi
    fi

    echo "=== Athena Agent Synchronization ===" >&2
    echo "Target Agent: $target_agent" >&2
    echo "Sync Data: $sync_data" >&2
    echo "Sync Mode: $sync_mode" >&2
    echo "---" >&2

    local sync_entry=""
    sync_entry="Sync: $(date -Iseconds)\n"
    sync_entry+="Target Agent: $target_agent\n"
    sync_entry+="Data: $sync_data\n"
    sync_entry+="Mode: $sync_mode\n"

    # Simulate agent synchronization
    local sync_status=""
    case "$sync_mode" in
        "bidirectional")
            sync_status="SUCCESS"
            ;;
        "push")
            sync_status="PUSHED"
            ;;
        "pull")
            sync_status="PULLED"
            ;;
        "overwrite")
            sync_status="OVERWRITTEN"
            ;;
        *)
            sync_status="UNKNOWN"
            ;;
    esac

    sync_entry+="Status: $sync_status\n"

    # Add to awareness state
    add_awareness_state "sync" "$sync_entry"

    # Display sync
    echo "$sync_entry"
    echo "Sync completed with agent $target_agent: $sync_status" >&2

    return 0
}

# Function to export handoff data with security validation
export_handoff_data() {
    local output_file="${1:-handoff_data.json}"
    local export_format="${2:-detailed}"

    # Validate output file path
    if [[ -n "$output_file" ]]; then
        output_file=$(validate_and_sanitize_path "$output_file")
        if [[ $? -ne 0 ]]; then
            echo "Error: Invalid output file path" >&2
            return 1
        fi
    fi

    # Validate export format
    if [[ ! "$export_format" =~ ^(detailed|simple|csv)$ ]]; then
        echo "Error: Invalid export format. Use: detailed, simple, or csv" >&2
        return 1
    fi

    echo "=== Exporting Handoff Data ===" >&2
    echo "Output file: $output_file" >&2
    echo "Export format: $export_format" >&2

    case "$export_format" in
        "detailed")
            # JSON format with full details
            cat > "$output_file" << EOF
{
  "metadata": {
    "handoff_mode": "$HANDOFF_MODE",
    "target_progress": "$TARGET_PROGRESS",
    "handoff_type": "$HANDOFF_TYPE",
    "target_agent": "$TARGET_AGENT",
    "progress_threshold": $PROGRESS_THRESHOLD,
    "transition_type": "$TRANSITION_TYPE",
    "output_dir": "$OUTPUT_DIR",
    "awareness_level": "$AWARENESS_LEVEL",
    "timestamp": "$(date -Iseconds)",
    "timeout_seconds": $TIMEOUT_SECONDS
  },
  "handoff_sessions": [
EOF

            local first=true
            for session in "${HANDOFF_SESSIONS[@]}"; do
                if [[ "$first" == true ]]; then
                    first=false
                else
                    echo "    ," >> "$output_file"
                fi
                local escaped_session=$(echo "$session" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
                echo "    \"$escaped_session\"" >> "$output_file"
            done

            cat >> "$output_file" << EOF
  ],
  "transition_log": [
EOF

            for transition in "${TRANSITION_LOG[@]}"; do
                echo "    \"$transition\"," >> "$output_file"
            done

            cat >> "$output_file" << EOF
  ],
  "progress_reports": [
EOF

            for report in "${PROGRESS_REPORTS[@]}"; do
                echo "    \"$report\"," >> "$output_file"
            done

            cat >> "$output_file" << EOF
  ],
  "awareness_state": [
EOF

            for awareness in "${AWARENESS_STATE[@]}"; do
                echo "    \"$awareness\"," >> "$output_file"
            done

            cat >> "$output_file" << EOF
  ],
  "performance": {
    "max_tracking_sessions": $MAX_TRACKING_SESSIONS,
    "timeout_seconds": "$TIMEOUT_SECONDS"
  }
}
EOF
            ;;

        "simple")
            # Simple text format
            cat > "$output_file" << EOF
Athena Handoff Data
===================
Handoff Mode: $HANDOFF_MODE
Target Progress: $TARGET_PROGRESS
Handoff Type: $HANDOFF_TYPE
Target Agent: $TARGET_AGENT
Progress Threshold: $PROGRESS_THRESHOLD%
Transition Type: $TRANSITION_TYPE
Awareness Level: $AWARENESS_LEVEL

Generated: $(date -Iseconds)

Handoff Sessions:
$(printf '%s\n' "${HANDOFF_SESSIONS[@]}")

Transition Log:
$(printf '%s\n' "${TRANSITION_LOG[@]}")

Progress Reports:
$(printf '%s\n' "${PROGRESS_REPORTS[@]}")

Awareness State:
$(printf '%s\n' "${AWARENESS_STATE[@]}")

Generated by: Athena Handoff System
EOF
            ;;

        "csv")
            # CSV format
            cat > "$output_file" << EOF
mode,target,type,agent,threshold,transition_level,timestamp
"$HANDOFF_MODE","$TARGET_PROGRESS","$HANDOFF_TYPE","$TARGET_AGENT","$PROGRESS_THRESHOLD","$TRANSITION_TYPE","$(date -Iseconds)"
EOF
            ;;
    esac

    echo "Handoff data exported to: $output_file" >&2
}

# Function to manage handoff lifecycle with security validation
manage_handoff_lifecycle() {
    local lifecycle_action="${1:-create}"
    local session_id="${2:-}"
    local lifecycle_data="${3:-}"

    # Validate lifecycle action
    if [[ ! "$lifecycle_action" =~ ^(create|start|pause|resume|complete|cleanup)$ ]]; then
        echo "Error: Invalid lifecycle action. Use: create, start, pause, resume, complete, or cleanup" >&2
        return 1
    fi

    # Input sanitization for lifecycle data
    if [[ -n "$lifecycle_data" ]]; then
        lifecycle_data=${lifecycle_data//\;/ }
        lifecycle_data=${lifecycle_data//\&/ }
        lifecycle_data=${lifecycle_data//\|/ }
        if [[ ${#lifecycle_data} -gt 500 ]]; then
            echo "Security warning: Lifecycle data too long, truncating" >&2
            lifecycle_data="${lifecycle_data:0:500}"
        fi
    fi

    echo "=== Athena Handoff Lifecycle Management ===" >&2
    echo "Action: $lifecycle_action" >&2
    echo "Session ID: $session_id" >&2
    echo "Lifecycle Data: $lifecycle_data" >&2
    echo "---" >&2

    local lifecycle_entry=""
    lifecycle_entry="Lifecycle: $(date -Iseconds)\n"
    lifecycle_entry+="Action: $lifecycle_action\n"
    lifecycle_entry+="Session ID: $session_id\n"
    lifecycle_entry+="Lifecycle Data: $lifecycle_data\n"

    # Determine lifecycle stage
    local lifecycle_stage=""
    case "$lifecycle_action" in
        "create")
            lifecycle_stage="INITIALIZATION"
            ;;
        "start")
            lifecycle_stage="EXECUTION"
            ;;
        "pause")
            lifecycle_stage="SUSPENSION"
            ;;
        "resume")
            lifecycle_stage="RESUMPTION"
            ;;
        "complete")
            lifecycle_stage="COMPLETION"
            ;;
        "cleanup")
            lifecycle_stage="FINALIZATION"
            ;;
        *)
            lifecycle_stage="UNKNOWN"
            ;;
    esac

    lifecycle_entry+="Stage: $lifecycle_stage\n"

    # Add to awareness state
    add_awareness_state "lifecycle" "$lifecycle_entry"

    # Display lifecycle
    echo "$lifecycle_entry"
    echo "Handoff lifecycle managed: $lifecycle_action -> $lifecycle_stage" >&2

    return 0
}

# Main execution logic
main() {
    case "$HANDOFF_MODE" in
        "track")
            if [[ -n "$TARGET_PROGRESS" ]]; then
                # track_progress(session_id, progress_value, description, agent_name)
                # Called as: handoff.sh track <progress_value> [description] [agent_name]
                # So: session_id = $3 (HANDOFF_TYPE/description), progress_value = $2 (TARGET_PROGRESS), description = $3 (HANDOFF_TYPE), agent_name = $4 (TARGET_AGENT)
                track_progress "${TARGET_AGENT:-SESSION_$(date +%s)}" "$TARGET_PROGRESS" "${HANDOFF_TYPE:-}" "${TARGET_AGENT:-}"
            else
                echo "Error: No target progress specified for tracking" >&2
                echo "Usage: $0 track <progress_value> [description] [agent_name]" >&2
                exit 1
            fi
            ;;

        "transition")
            if [[ -n "$TARGET_PROGRESS" ]]; then
                manage_transition "$TARGET_PROGRESS" "$TARGET_AGENT"
            else
                echo "Error: No target specified for transition" >&2
                echo "Usage: $0 transition <from_state> <to_state> [context] [agent_name]" >&2
                exit 1
            fi
            ;;

        "report")
            generate_progress_report "$TARGET_PROGRESS"
            ;;

        "sync")
            if [[ -n "$TARGET_PROGRESS" ]]; then
                # sync_with_agent(target_agent, sync_data, sync_mode)
                # Called as: handoff.sh sync <agent_name> [data] [mode]
                # TARGET_PROGRESS=$2 (agent_name), HANDOFF_TYPE=$3 (data), TARGET_AGENT=$4 (mode)
                sync_with_agent "$TARGET_PROGRESS" "${HANDOFF_TYPE:-}" "${TARGET_AGENT:-bidirectional}"
            else
                echo "Error: No target agent specified for sync" >&2
                echo "Usage: $0 sync <agent_name> [data] [mode]" >&2
                exit 1
            fi
            ;;

        "export")
            export_handoff_data "$TARGET_PROGRESS"
            ;;

        "lifecycle")
            # manage_handoff_lifecycle(lifecycle_action, session_id, lifecycle_data)
            # Called as: handoff.sh lifecycle <action> <session_id> [lifecycle_data]
            # TARGET_PROGRESS=$2 (action), HANDOFF_TYPE=$3 (session_id), TARGET_AGENT=$4 (lifecycle_data)
            manage_handoff_lifecycle "$TARGET_PROGRESS" "${HANDOFF_TYPE:-SESSION_$(date +%s)}" "${TARGET_AGENT:-}"
            ;;

        "full")
            echo "=== Full Athena Handoff Process ===" >&2
            if [[ -n "$TARGET_PROGRESS" ]]; then
                track_progress "$TARGET_PROGRESS" "$TARGET_AGENT"
                generate_progress_report "$TARGET_PROGRESS"
                export_handoff_data "$TARGET_PROGRESS"
                echo "Full handoff process completed successfully" >&2
            else
                echo "Error: No target progress specified for full analysis" >&2
                exit 1
            fi
            ;;

        *)
            echo "Usage: $0 [track|transition|report|sync|export|lifecycle|full] [arguments...]" >&2
            echo "" >&2
            echo "Modes:" >&2
            echo "  track      - Track progress of handoff" >&2
            echo "  transition - Manage state transitions" >&2
            echo "  report     - Generate progress report" >&2
            echo "  sync       - Synchronize with target agent" >&2
            echo "  export     - Export handoff data" >&2
            echo "  lifecycle  - Manage handoff lifecycle" >&2
            echo "  full       - Complete handoff process" >&2
            echo "" >&2
            echo "Example usages:" >&2
            echo "  $0 track 75 \"Processing data\" \"Agent1\"" >&2
            echo "  $0 transition \"analysis\" \"implementation\" \"Ready to implement\" \"Agent2\"" >&2
            echo "  $0 report \"SESSION_123\" detailed" >&2
            echo "  $0 sync \"Agent3\" \"New data\" bidirectional" >&2
            echo "  $0 export handoff_data.json" >&2
            echo "  $0 lifecycle create \"SESSION_123\" \"Initial handoff\"" >&2
            exit 1
            ;;
    esac
}

# Execute main function
main