#!/usr/bin/bash
# rish.sh - Shizuku privileged shell for Termux
# Requires: Shizuku app authorization for com.termux
# Usage: cd storage/rish && bash rish.sh <command>
#   OR: bash rish.sh <command> (from anywhere)

RISHDIR="/root/storage/rish"
DEX="$RISHDIR/rish_shizuku.dex"

if [ ! -d "$RISHDIR" ]; then
    echo "ERROR: rish directory not found at $RISHDIR"
    exit 1
fi

export RISH_APPLICATION_ID="com.termux"
export ANDROID_CACHE="/data/data/com.termux/files/cache/dalvik-cache"

# Android 14+ requires DEX to be non-writable
if [ $(getprop ro.build.version.sdk) -ge 34 ]; then
    chmod 400 "$DEX" 2>/dev/null
fi

if [ $# -eq 0 ]; then
    # Interactive mode — launch rish shell
    cd "$RISHDIR" && exec bash rish
else
    # Command mode — pass command via heredoc to preserve stdout
    cd "$RISHDIR" && bash rish <<EOF
$*
exit
EOF
fi
