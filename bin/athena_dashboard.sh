#!/bin/bash
# Athena Internal State Dashboard

clear
echo "================================================================================"
echo "                ATHENA COGNITIVE STATE DASHBOARD                                "
echo "                Date: $(date)                                                  "
echo "================================================================================"

echo -e "\n[1] HARDWARE TELEMETRY (Vera CPU)"
if [ -f /opt/athena/state/vera_cpu.json ]; then
    cat /opt/athena/state/vera_cpu.json | python3 -m json.tool
else
    echo "No telemetry available."
fi

echo -e "\n[2] COGNITIVE OUTPUTS"
for file in /opt/athena/state/*_output.json; do
    if [ -f "$file" ]; then
        echo "--- $file ---"
        tail -n 3 "$file"
    fi
done

echo -e "\n[3] DAEMON LOGS"
tail -n 5 /opt/athena/state/daemon.log

echo -e "\n================================================================================"
echo "Press Ctrl+C to exit"
