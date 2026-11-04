#!/usr/bin/bash
# athena_speak.sh — Jarvis-style audio narration for OpenClaude responses.
#
# Usage:
#   athena_speak.sh                           — auto-narrate last exchange
#   athena_speak.sh "custom text"             — speak custom text (en-US)
#   athena_speak.sh "custom text" en-gb       — British accent
#   athena_speak.sh "custom text" slow        — slow deep voice
#   athena_speak.sh quick "status"            — quick narration
#   athena_speak.sh --voice en-gb "text"      — explicit voice flag
#   athena_speak.sh rate 0.5 "text"           — speech rate (0.1–2.0)
#   athena_speak.sh pitch 1.5 "text"          — pitch modifier

source "/opt/athena/bin/athena_env.sh"

DATA_DIR="/opt/athena/state"
SOUND_DIR="$DATA_DIR/sounds"
MP3_FILE="$SOUND_DIR/jarvis_response.mp3"
HISTORY_FILE="/root/.openclaude/history.jsonl"

export ATHENA_HISTORY_FILE="$HISTORY_FILE"
export ATHENA_USER_NAME="${ATHENA_USER_NAME:-user}"

mkdir -p "$SOUND_DIR"

# Parse args
LANG_ARG="en"
SLOW=False
RATE=""
PITCH=""
CUSTOM_TEXT=""
QUICK=false

while [ $# -gt 0 ]; do
    case "$1" in
        --voice)
            LANG_ARG="${2:-en}"
            shift 2
            ;;
        slow)
            SLOW="True"
            shift
            ;;
        quick)
            QUICK=true
            shift
            CUSTOM_TEXT="${1:-}"
            break
            ;;
        rate)
            RATE="${2:-}"
            shift 2
            ;;
        pitch)
            PITCH="${2:-}"
            shift 2
            ;;
        *)
            CUSTOM_TEXT="$*"
            break
            ;;
    esac
done

# --- jarvis phrasing engine -------------------------------------------------

generate_jarvis() {
    export ATHENA_HISTORY_FILE="$HISTORY_FILE"
    export ATHENA_USER_NAME="${ATHENA_USER_NAME:-user}"
    python3 "$PYTHON_LIB/athena/generate_jarvis.py" 2>/dev/null
}

# --- main -------------------------------------------------------------------

if [ $# -eq 0 ] && [ "$QUICK" = false ]; then
    # Auto-mode: generate Jarvis narration from last exchange
    TEXT=$(generate_jarvis)
elif [ -n "$CUSTOM_TEXT" ]; then
    TEXT="$CUSTOM_TEXT"
fi

echo "Jarvis: $TEXT" >&2

# Build python kwargs
PY_KWARGS="text='$TEXT', lang='$LANG_ARG', slow=$SLOW"
if [ -n "$RATE" ]; then
    PY_KWARGS="$PY_KWARGS, lang='$LANG_ARG', slow=$SLOW, tld=True"
    # rate/pitch passed via env to Python
fi

# Generate audio via a temp script to avoid shell→Python interpolation issues
PY_SCRIPT="${TMPDIR:-/root/.local/share}/athena_speak_$$.py"
mkdir -p "$(dirname "$PY_SCRIPT")"
trap "rm -f $PY_SCRIPT" EXIT

cat > "$PY_SCRIPT" << 'PYEOF'
import os, sys, json
from gtts import gTTS

TEXT = os.environ.get("ATHENA_TEXT", "")
LANG = os.environ.get("ATHENA_LANG", "en")
SLOW = os.environ.get("ATHENA_SLOW", "False") == "True"
RATE = os.environ.get("ATHENA_RATE", "")
PITCH = os.environ.get("ATHENA_PITCH", "")
OUT = os.environ.get("ATHENA_OUT", "")

try:
    tts = gTTS(text=TEXT, lang=LANG, slow=SLOW)
    tts.save(OUT)
    print(OUT)
except Exception as e:
    print(f"gTTS error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

export ATHENA_TEXT="$TEXT"
export ATHENA_LANG="$LANG_ARG"
export ATHENA_SLOW="$SLOW"
export ATHENA_RATE="$RATE"
export ATHENA_PITCH="$PITCH"
export ATHENA_OUT="$MP3_FILE"

python3 "$PY_SCRIPT" 2>/dev/null

if [ -f "$MP3_FILE" ]; then
    termux-media-player play "$MP3_FILE" 2>/dev/null >/dev/null &
fi
