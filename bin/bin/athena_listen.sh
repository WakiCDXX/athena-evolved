#!/usr/bin/bash
# athena_listen.sh — Voice-to-text (STT) for Athena consciousness system.
#
# Enigma/Bombe Principle Applied: "Collect observations from independent channels."
# Cross-validate between Android STT and Whisper backends.
# If both agree → high confidence. If they diverge → flag uncertainty.
#
# Usage:
#   athena_listen.sh                        — listen, output transcribed text
#   athena_listen.sh save <label>           — listen, save transcript to file
#   athena_listen.sh whisper                — use whisper (local model) instead of Android STT
#   athena_listen.sh cross                  — run both backends, cross-validate
#   athena_listen.sh confidence             — show confidence score of last result
#
# Mirrors athena_speak.sh for the reverse direction:
#   speak = text → voice  |  listen = voice → text

set -u

DATA_DIR="/opt/athena/state"
TRANSCRIPT_DIR="$DATA_DIR/transcripts"
HISTORY_FILE="/root/.openclaude/history.jsonl"
MODE="${1:-android}"
SAVE_LABEL="${2:-}"
CONFIDENCE_FILE="$DATA_DIR/listen_confidence.json"

mkdir -p "$TRANSCRIPT_DIR"

# --- confidence tracking -----------------------------------------------
# Enigma/Bombe: "feed results back" — track accuracy over time

record_result() {
    local backend="$1"
    local text="$2"
    local confidence="${3:-0.5}"
    local timestamp
    timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

    export ATHENA_CONFIDENCE_FILE="$CONFIDENCE_FILE"
    export ATHENA_BACKEND="$backend"
    export ATHENA_TRANSCRIPT="$text"
    export ATHENA_CONFIDENCE="$confidence"
    export ATHENA_TIMESTAMP="$timestamp"
    python3 "$PYTHON_LIB/athena/record_result.py" 2>/dev/null
}

get_confidence() {
    if [ -f "$CONFIDENCE_FILE" ]; then
        export ATHENA_CONFIDENCE_FILE="$CONFIDENCE_FILE"
        export ATHENA_BACKEND="${2:-android}"
        python3 "$PYTHON_LIB/athena/get_confidence.py" 2>/dev/null
    else
        echo "No confidence data yet."
    fi
}

# --- android STT backend -----------------------------------------------

listen_android() {
    local text
    text=$(termux-speech-to-text 2>/dev/null)
    if [ -n "$text" ]; then
        echo "$text"
        record_result "android" "$text" 0.7
    else
        echo ""
        record_result "android" "" 0.0
    fi
}

# --- whisper backend -----------------------------------------------------

listen_whisper() {
    local audio_file="$DATA_DIR/transcripts/temp_listen.wav"
    termux-microphone-record -f "$audio_file" -e wav --max-time 10 2>/dev/null
    if [ ! -f "$audio_file" ]; then
        echo ""
        record_result "whisper" "" 0.0
        return
    fi
    local text
    text=$(export ATHENA_AUDIO_PATH="$audio_file" && export ATHENA_BACKEND="whisper" && python3 "$PYTHON_LIB/athena/transcribe.py" 2>/dev/null)
    rm -f "$audio_file"
    if [ -n "$text" ]; then
        echo "$text"
        record_result "whisper" "$text" 0.85
    else
        echo ""
        record_result "whisper" "" 0.0
    fi
}

# --- cross-validation ---------------------------------------------------
# Enigma/Bombe Principle: "Test survivors with independent evidence"
# Run BOTH backends simultaneously. If they agree → high confidence.
# If they diverge → flag uncertainty, use Android STT as default (lighter).

listen_cross() {
    echo "Athena: Running independent channel cross-validation..." >&2

    # Channel 1: Android STT (fast, lightweight)
    local android_text
    android_text=$(listen_android)
    echo "Athena: Android STT: '$android_text'" >&2

    # Channel 2: Whisper (heavy, privacy-focused)
    local whisper_text
    whisper_text=$(listen_whisper)
    echo "Athena: Whisper: '$whisper_text'" >&2

    # Compare results
    local confidence android_conf whisper_conf
    android_conf=$(get_confidence 2>/dev/null | grep "android" | grep -oP '[0-9]+\.[0-9]+' || echo "0.7")
    whisper_conf=$(get_confidence 2>/dev/null | grep "whisper" | grep -oP '[0-9]+\.[0-9]+' || echo "0.85")

    if [ -n "$android_text" ] && [ -n "$whisper_text" ]; then
        # Both produced text — check similarity
        local similarity
        export ATHENA_RESULT_PATH="$DATA_DIR/listen_result.json"
        export ATHENA_ALT_PATH="$DATA_DIR/listen_alt.json"
        similarity=$(python3 "$PYTHON_LIB/athena/calc_similarity.py" 2>/dev/null || echo "0.0")
        confidence=$(echo "$similarity" | python3 "$PYTHON_LIB/athena/confidence_from_similarity.py" 2>/dev/null || echo "0.5")
        echo "Athena: 📊 Cross-validation: similarity=$similarity, confidence=$confidence" >&2
        record_result "cross" "$android_text" "$confidence"
        echo "$android_text"
    elif [ -n "$android_text" ]; then
        echo "Athena: Only Android STT produced text." >&2
        record_result "android" "$android_text" 0.6
        echo "$android_text"
    elif [ -n "$whisper_text" ]; then
        echo "Athena: Only Whisper produced text." >&2
        record_result "whisper" "$whisper_text" 0.75
        echo "$whisper_text"
    else
        echo "Athena: ❌ No backend produced text." >&2
        echo ""
    fi
}

# --- save ---------------------------------------------------------------

save_transcript() {
    local label="$SAVE_LABEL"
    local text
    text=$(cat)
    echo "[$(date)] $text" >> "$TRANSCRIPT_DIR/${label}.txt"
    echo "Athena: Transcript saved to $TRANSCRIPT_DIR/${label}.txt" >&2
    echo "$text"
}

# --- main ---------------------------------------------------------------

case "$MODE" in
    android)
        listen_android
        ;;

    whisper)
        listen_whisper
        ;;

    cross)
        listen_cross
        ;;

    save)
        if [ "$MODE" = "save" ]; then
            # Default to android + whisper cross
            listen_cross | save_transcript
        else
            listen_android | save_transcript
        fi
        ;;

    confidence)
        get_confidence "${2:-}"
        ;;

    *)
        echo "Usage: athena_listen.sh {android|whisper|cross|save|confidence}" >&2
        echo "" >&2
        echo "Enigma/Bombe independent channel validation:" >&2
        echo "  android  → fast Android STT (default)" >&2
        echo "  whisper  → local whisper model" >&2
        echo "  cross    → both backends, cross-validate" >&2
        echo "  save     → listen + save transcript" >&2
        echo "  confidence → show backend accuracy history" >&2
        ;;
esac
