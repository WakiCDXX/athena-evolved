#!/usr/bin/bash
# shizuku_install.sh — Install APKs via Android's system installer UI.
# Usage: shizuku_install.sh <path-to-apk>
APK_PATH="${1:-/storage/emulated/0/shizuku.apk}"
if [ ! -f "$APK_PATH" ]; then
    echo "ERROR: APK not found at $APK_PATH"
    exit 1
fi
echo "Launching system installer for: $APK_PATH"
echo "You should see an install prompt on your device."
echo "---"
am start -a android.intent.action.VIEW \
    -d "file://$APK_PATH" \
    -t "application/vnd.android.package-archive" \
    --ez "android.intent.extra.INSTALLER_PACKAGE" true 2>&1
if [ $? -eq 0 ]; then
    echo "SUCCESS: Installer launched. Complete the install on your device."
else
    echo "FAILED: Could not launch installer."
    exit 1
fi
