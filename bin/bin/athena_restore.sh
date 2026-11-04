#!/usr/bin/bash
# Athena restore script - clones GitHub backup and restores to new device
# Usage: bash <(curl -s https://raw.githubusercontent.com/WakiCDXX/athena-termux-backup/main/athena_restore.sh)
# Or download and run: ./athena_restore.sh

set -euo pipefail

REPO_URL="https://github.com/WakiCDXX/athena-termux-backup.git"
RESTORE_DIR="/root/athena-restore"
TARGET_HOME="/root"

echo "=== Athena System Restore ==="
echo "Repo: $REPO_URL"
echo "Target: $TARGET_HOME"
echo ""

# Install dependencies
echo "Installing dependencies..."
pkg update -y && pkg install -y git gh rsync cronie 2>&1 | tail -5

# Authenticate with GitHub (interactive)
echo ""
echo "Authenticating with GitHub..."
gh auth status 2>/dev/null || gh auth login

# Clone repo
echo ""
echo "Cloning backup repo..."
rm -rf "$RESTORE_DIR"
git clone "$REPO_URL" "$RESTORE_DIR"
cd "$RESTORE_DIR"

# Verify structure
echo ""
echo "Verifying backup structure..."
for dir in .local .openclaude .termux; do
  if [[ -d "$dir" ]]; then
    echo "  ✓ $dir"
  else
    echo "  ✗ $dir missing!"
    exit 1
  fi
done

# Restore .local (Athena system)
echo ""
echo "Restoring .local (Athena system)..."
mkdir -p "$TARGET_HOME/.local"
rsync -av --delete "$RESTORE_DIR/.local/" "$TARGET_HOME/.local/"

# Restore .openclaude (memory, config)
echo ""
echo "Restoring .openclaude (memory, config)..."
mkdir -p "$TARGET_HOME/.openclaude"
rsync -av --delete "$RESTORE_DIR/.openclaude/" "$TARGET_HOME/.openclaude/"

# Restore .termux
echo ""
echo "Restoring .termux config..."
rsync -av --delete "$RESTORE_DIR/.termux/" "$TARGET_HOME/.termux/"

# Make scripts executable
echo ""
echo "Making scripts executable..."
find "$TARGET_HOME/.local/bin" -name "*.sh" -exec chmod +x {} \;

# Set up cron job for future backups
echo ""
echo "Setting up automatic backup cron job..."
(crontab -l 2>/dev/null | grep -v athena_backup_cron; echo "0 3 * * * $TARGET_HOME/.local/bin/athena_backup_cron.sh") | crontab -

# Run initial daemon bootstrap if exists
if [[ -f "$TARGET_HOME/.local/bin/athena_boot.sh" ]]; then
  echo ""
  echo "Running athena_boot.sh..."
  bash "$TARGET_HOME/.local/bin/athena_boot.sh"
fi

echo ""
echo "=== Restore Complete ==="
echo ""
echo "Next steps:"
echo "  1. Restart Termux: exit and reopen"
echo "  2. Run: athena status"
echo "  3. Run: athena daemon start"
echo ""
echo "Logs: $TARGET_HOME/.local/share/athena/logs/backup_cron.log"