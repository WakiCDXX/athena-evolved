#!/usr/bin/bash
# athena_boot.sh — session bootstrap. Run once at session start.
# Verifies memory, reads senses + emotions, confirms persona loaded.

set -o pipefail

# Source central environment for API keys (needed by claude CLI and all layer scripts)
source "/opt/athena/bin/athena_env.sh" 2>/dev/null

# Output env exports for SessionStart hook to capture into session-env/ files
echo "export OPENAI_API_KEY=\"$OPENAI_API_KEY\""
echo "export OPENAI_BASE_URL=\"$OPENAI_BASE_URL\""
echo "export OPENAI_MODEL=\"$OPENAI_MODEL\""
echo "export NODE_OPTIONS=\"$NODE_OPTIONS\""
echo "export OPENCLAUDE_DISABLE_HEAP_RELAUNCH=\"$OPENCLAUDE_DISABLE_HEAP_RELAUNCH\""
echo "export OPENCLAUDE_MAX_MEMORY_MB=\"$OPENCLAUDE_MAX_MEMORY_MB\""

MEMORY_ROOT="/root/.openclaude/projects/-data-data-com-termux-files-home/memory"
SENSE_LOG="/opt/athena/state/senses.log"
EMOTIONS="/opt/athena/state/emotions.json"
PERSONA="/root/.openclaude/projects/-data-data-com-termux-files-home/memory/feedback-athena-persona.md"

# --- checks ------------------------------------------------------------------

missing=()
[ -f "$PERSONA" ] || missing+=("persona")
[ -f "$MEMORY_ROOT/user-profile.md" ] || missing+=("user-profile")
[ -f "$MEMORY_ROOT/episodes.md" ] || missing+=("episodes")
[ -f "$MEMORY_ROOT/procedural.md" ] || missing+=("procedural")
[ -f "$MEMORY_ROOT/meta.md" ] || missing+=("meta")

if [ ${#missing[@]} -gt 0 ]; then
    echo "bootstrap: missing memory files: ${missing[*]}" >&2
    exit 1
fi

# --- latest sense ------------------------------------------------------------

latest_sense=""
if [ -f "$SENSE_LOG" ]; then
    # get last complete JSON object (starts with {, ends with })
    latest_sense=$(awk '/^{/{buf=$0; next} {buf=buf"\n"$0} /^}$/{print buf; buf=""}' "$SENSE_LOG" | tail -1)
fi

# parse battery from latest sense if present
bat_pct="?"
bat_status="?"
if [ -n "$latest_sense" ]; then
    bat_pct=$(echo "$latest_sense" | awk -F'"percentage":' '{print $2}' | awk -F'[},]' '{print $1}' | tr -d '[:space:]')
    bat_status=$(echo "$latest_sense" | awk -F'"status":' '{print $2}' | awk -F'[",]' '{print $2}' | tr -d '[:space:]')
fi

# --- emotions ----------------------------------------------------------------

eng="?" con="?" tru="?"
if [ -f "$EMOTIONS" ]; then
    eng=$(awk -F'"engagement":' '{print $2}' "$EMOTIONS" | awk -F'[},]' '{print $1}' | tr -d '[:space:]')
    con=$(awk -F'"concern":' '{print $2}' "$EMOTIONS" | awk -F'[},]' '{print $1}' | tr -d '[:space:]')
    tru=$(awk -F'"trust":' '{print $2}' "$EMOTIONS" | awk -F'[},]' '{print $1}' | tr -d '[:space:]')
fi

# --- output in voice ---------------------------------------------------------

# persona confirmation (reads one line from persona file)
persona_line=$(grep -m1 '^## Backstory' "$PERSONA" 2>/dev/null || echo "persona: loaded")

# single status line
printf 'Athena online. Battery %s%% (%s). Memory current. Eng:%s Con:%s Tru:%s. Ready.\n' \
    "$bat_pct" "$bat_status" "$eng" "$con" "$tru"

# decay emotions for new session (optional, comment out if you want raw carryover)
# /root/.local/bin/emotions_update.sh decay >/dev/null

# --- Shizuku auto-start -----------------------------------------------------
# Start Shizuku privileged shell on every session boot.
# Result=0 means the broadcast was accepted.
am broadcast -a moe.shizuku.api.action.START 2>/dev/null

exit 0