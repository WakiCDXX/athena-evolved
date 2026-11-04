#!/usr/bin/bash
export RISH_APPLICATION_ID="com.termux"
DEX="/data/data/com.termux/files/cache/rish_shizuku.dex"
chmod 400 "$DEX" 2>/dev/null
/system/bin/app_process -Djava.class.path="$DEX" /system/bin --nice-name=rish rikka.shizuku.shell.ShizukuShellLoader "$@" 2>&1
