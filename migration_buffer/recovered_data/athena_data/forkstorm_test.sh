#!/data/data/com.termux/files/usr/bin/bash
# Test: does daemon survive 10 minutes with event-driven 0.5-2s cycling?
LOG=/data/data/com.termux/files/home/athena_data/forkstorm_log.txt
: > $LOG

log() { echo "[$(date '+%F %T')] $*" >> $LOG; }

start_daemon() {
  cd /data/data/com.termux/files/home/.local/bin
  echo "=== STARTING ORIGINAL 13-LAYER DAEMON ===" >> $LOG
  bash athena_daemon.sh start >> $LOG 2>&1
  echo "start_exit=$?" >> $LOG
}

for i in $(seq 1 12); do
  start_daemon
  sleep 40
  echo "--- round $i snapshot ---" >> $LOG
  echo "workers=$(ps -eo pid,args | grep layer_worker | grep -v grep | wc -l)" >> $LOG
  echo "python_forks=$(ps -eo pid,args | grep -E "python3 (\/|/data)" | grep -v grep | wc -l)" >> $LOG
  echo "openappa_pids=$(cat /data/data/com.termux/files/athena_data/openappa.pid 2>/dev/null) rss=$(ps -o rss= -p $(cat /data/data/com.termux/files/athena_data/openappa.pid 2>/dev/null) 2>/dev/null)" >> $LOG
  echo "free_mem=$(free -m | awk '/^Mem:/{print $7}')" >> $LOG
  echo "dmesg=$(dmesg 2>/dev/null | grep -icE 'oom|killed')" >> $LOG
  sleep 20
done
echo "=== TEST COMPLETE ===" >> $LOG
echo "workers=$(ps -eo pid,args | grep layer_worker | grep -v grep | wc -l)" >> $LOG
cat $LOG
