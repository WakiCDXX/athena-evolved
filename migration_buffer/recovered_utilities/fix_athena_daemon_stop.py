import re

with open('/data/data/com.termux/files/home/.local/bin/athena_daemon.sh', 'r') as f:
    content = f.read()

# Find the stop case block
old_stop = '''    stop)
        echo "=== Athena Daemon: Stopping all layers ==="
        release_wake_lock

        stop_subshell "body"
        stop_subshell "emotions"
        stop_subshell "continuity"
        stop_subshell "attention"
        stop_subshell "introspection"
        stop_subshell "doubt"
        stop_subshell "volition"
        stop_subshell "memory"
        stop_subshell "heartbeat"
        stop_subshell "archive"
        stop_subshell "memory_backup"
        stop_subshell "openappa"
        stop_subshell "archestra"
        stop_subshell "vera_cpu"
        stop_subshell "wayfinder"
        stop_subshell "implement_spec"
        stop_subshell "tdd"
        stop_subshell "handoff"
        stop_subshell "to_spec"
        stop_subshell "workflow_chain"

        if [ -f "$DATA/sense_poll.pid" ]; then
            spid=$(cat "$DATA/sense_poll.pid" 2>/dev/null)
            if [ -n "$spid" ] && kill -0 "$spid" 2>/dev/null; then
                kill_tree_by_pid "$spid"
                echo "  senses: stopped (was PID $spid)"
            fi
            rm -f "$DATA/sense_poll.pid"
        fi

        if [ -f "$DATA/sd_health_monitor.pid" ]; then
            sdpid=$(cat "$DATA/sd_health_monitor.pid" 2>/dev/null)
            if [ -n "$sdpid" ] && kill -0 "$sdpid" 2>/dev/null; then
                kill_tree_by_pid "$sdpid"
                echo "  sd_health_monitor: stopped (was PID $sdpid)"
            fi
            rm -f "$DATA/sd_health_monitor.pid"
        fi

        echo "=== All layer daemons stopped ==="
        ;;

    status)'''

new_stop = '''    stop)
        echo "=== Athena Daemon: Stopping all layers ==="
        release_wake_lock

        # Parallel stop: send SIGTERM to all layers simultaneously
        # Collect all PIDs first
        pids_to_stop=()
        for name in body emotions continuity attention introspection doubt volition memory heartbeat archive memory_backup openappa archestra vera_cpu wayfinder implement_spec tdd handoff to_spec workflow_chain; do
            pidfile="$DATA/${name}.pid"
            pid=$(cat "$pidfile" 2>/dev/null)
            if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && _is_layer_worker "$pid"; then
                pids_to_stop+=("$pid")
            fi
        done

        # Also collect senses and sd_health_monitor PIDs
        if [ -f "$DATA/sense_poll.pid" ]; then
            spid=$(cat "$DATA/sense_poll.pid" 2>/dev/null)
            if [ -n "$spid" ] && kill -0 "$spid" 2>/dev/null; then
                pids_to_stop+=("$spid")
            fi
        fi

        if [ -f "$DATA/sd_health_monitor.pid" ]; then
            sdpid=$(cat "$DATA/sd_health_monitor.pid" 2>/dev/null)
            if [ -n "$sdpid" ] && kill -0 "$sdpid" 2>/dev/null; then
                pids_to_stop+=("$sdpid")
            fi
        fi

        # Send SIGTERM to all collected PIDs simultaneously
        for pid in "${pids_to_stop[@]}"; do
            # Kill the process and all its children
            children=$(ps -o PID --no-headers --ppid "$pid" 2>/dev/null; echo "$pid")
            for p in $children; do
                kill -TERM "$p" 2>/dev/null &
            done
        done
        wait  # Wait for all kill commands to complete

        # Brief pause for graceful shutdown
        sleep 0.5

        # Send SIGKILL to any remaining processes
        for pid in "${pids_to_stop[@]}"; do
            children=$(ps -o PID --no-headers --ppid "$pid" 2>/dev/null; echo "$pid")
            for p in $children; do
                kill -KILL "$p" 2>/dev/null &
            done
        done
        wait

        # Clean up PID files
        for name in body emotions continuity attention introspection doubt volition memory heartbeat archive memory_backup openappa archestra vera_cpu wayfinder implement_spec tdd handoff to_spec workflow_chain; do
            rm -f "$DATA/${name}.pid" "$DATA/${name}.pid.wrapper"
        done
        rm -f "$DATA/sense_poll.pid" "$DATA/sd_health_monitor.pid"

        echo "=== All layer daemons stopped ==="
        ;;

    status)'''

if old_stop in content:
    content = content.replace(old_stop, new_stop)
    with open('/data/data/com.termux/files/home/.local/bin/athena_daemon.sh', 'w') as f:
        f.write(content)
    print("SUCCESS: athena_daemon.sh stop updated with parallel shutdown")
else:
    print("ERROR: Could not find the stop block")
    # Try to find it with regex
    match = re.search(r'stop\).*?status\)', content, re.DOTALL)
    if match:
        print("Found with regex, length:", len(match.group()))
    else:
        print("Not found with regex either")

