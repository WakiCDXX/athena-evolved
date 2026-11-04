#!/data/data/com.termux/files/usr/bin/bash
# Monitor msafe daemon: RSS stability + SIGKILL detection
LOG=/data/data/com.termux/files/home/athena_data/msafe_rss_log.txt
echo "=== RSS snapshot at $(date) ===" >> $LOG
ps -eo pid,ppid,rss,vsz,%cpu,%mem,stat,args | grep -iE "layer_worker|sd_health" | grep -v grep >> $LOG 2>/dev/null
echo "--- free ---" >> $LOG
free -m >> $LOG 2>/dev/null
tail -1 /data/data/com.termux/files/home/msafe_start.log >> $LOG 2>/dev/null
dmesg 2>/dev/null | tail -1 | sed 's/^/dmesg: /' >> $LOG
wc -l < /proc/loadavg >> $LOG 2>/dev/null
