#!/usr/bin/bash
# Athena backup cron job - pushes to GitHub
# Add to crontab: 0 3 * * * /root/.local/bin/athena_backup_cron.sh

set -euo pipefail

STAGING_DIR="/root/athena-backup-staging"
LOG_FILE="/root/.local/share/athena/logs/backup_cron.log"

mkdir -p "$(dirname "$LOG_FILE")"

exec >>"$LOG_FILE" 2>&1
echo "=== Backup started $(date -Iseconds) ==="

cd "$STAGING_DIR" || { echo "Staging dir missing"; exit 1; }

# Sync .local (Athena system)
rsync -av --delete \
  --exclude='tmp/' \
  --exclude='.local/tmp/' \
  --exclude='*.apk' \
  --exclude='*.png' \
  /root/.local/ "$STAGING_DIR/.local/"

# Sync .openclaude (memory, config)
rsync -av --delete \
  --exclude='plugins/marketplaces/' \
  --exclude='projects/*/*/tool-results/' \
  --exclude='projects/*/*/subagents/' \
  --exclude='projects/*/*.replay.json' \
  --exclude='projects/*/*.jsonl' \
  --exclude='projects/*/*/b*.txt' \
  /root/.openclaude/ "$STAGING_DIR/.openclaude/"

# Sync .termux
rsync -av --delete /root/.termux/ "$STAGING_DIR/.termux/"

# Git commit & push
git add -A
if git diff --cached --quiet; then
  echo "No changes to commit"
else
  git commit -m "Auto backup $(date -Iseconds)"
  git push origin main
  echo "Pushed to GitHub"
fi

echo "=== Backup completed $(date -Iseconds) ==="