#!/usr/bin/bash
# Athena periodic checkpoint - runs every 5 minutes via cron
# Add to crontab: */5 * * * * /root/.local/bin/athena_checkpoint_cron.sh

set -euo pipefail

LOG_FILE="/root/.local/share/athena/logs/checkpoint_cron.log"
mkdir -p "$(dirname "$LOG_FILE")"

exec >>"$LOG_FILE" 2>&1
echo "=== Checkpoint cron $(date -Iseconds) ==="

# Only save if we have an active session (OPENCLAUDE_SESSION_ID or CLAUDE_SESSION_ID)
if [[ -n "${OPENCLAUDE_SESSION_ID:-}" || -n "${CLAUDE_SESSION_ID:-}" ]]; then
    ~/.local/bin/athena_checkpoint.sh save
    echo "Checkpoint saved for session: ${OPENCLAUDE_SESSION_ID:-${CLAUDE_SESSION_ID}}"
else
    echo "No active OpenClaude session, skipping"
fi

echo "=== Checkpoint cron done $(date -Iseconds) ==="