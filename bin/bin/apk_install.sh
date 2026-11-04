#!/usr/bin/bash
# apk_install.sh — Install APKs via adb (bypasses Termux sandbox)
#
# Works when adb wireless debugging is enabled on the device.
# From a host machine: adb connect <device-ip>:5555 && adb install <apk>
# From Termux: adb shell pm install -r -g /data/local/tmp/<apk>
#
# Usage:
#   apk_install.sh <path-to-apk>
#   apk_install.sh --remote <device-ip> <path-to-apk>  (install from host)

APK_PATH="${2:-/storage/emulated/0/shizuku.apk}"
DEVICE="${1:-}"

# Check if adb is available
ADB="/data/data/com.termux/files/usr/bin/adb"
if [ ! -x "$ADB" ]; then
    echo "ERROR: adb not found"
    exit 1
fi

# Start adb daemon
$ADB start-server 2>/dev/null

# Check for connected device
DEVICES=$($ADB devices 2>/dev/null | grep -v "List of" | grep -v "^$" | head -1)

if [ -n "$DEVICE" ]; then
    # Remote install: push APK to device, then install
    echo "Installing to device at $DEVICE..."
    $ADB -s "$DEVICE" push "$APK_PATH" /data/local/tmp/ 2>&1 && \
    $ADB -s "$DEVICE" shell "pm install -r -g /data/local/tmp/$(basename $APK_PATH)" 2>&1
else
    # Local install via adb (device is this same device)
    # Need to copy to /data/local/tmp/ first - but we can't write there
    # Instead: use am start as fallback
    echo "No adb device connected. Using am start fallback..."
    am start -a android.intent.action.VIEW \
        -d "file://$APK_PATH" \
        -t "application/vnd.android.package-archive" 2>&1
fi
