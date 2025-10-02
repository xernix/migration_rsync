#!/bin/bash
# nightly_migration.sh
# Wrapper for migration_core.sh with scheduling + 6AM cutoff

SRC_DIR="/mnt/suppdoc/hrmis"
DST_DIR="/data/suppdoc/hrmis"
LOG_DIR="root/migration/log"
CORE_SCRIPT="/root/migration/migration_core.sh"

ADMIN_EMAIL="admin@example.com"
RETENTION_DAYS=90

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
WRAPPER_LOG="$LOG_DIR/wrapper_$TIMESTAMP.log"

mkdir -p "$LOG_DIR"

echo "===== Nightly Migration Started: $TIMESTAMP =====" | tee "$WRAPPER_LOG"

# --- Calculate time left until 6AM ---
now=$(date +%s)
end=$(date -d "06:00" +%s)
if [ $now -gt $end ]; then
  end=$(date -d "tomorrow 06:00" +%s)
fi
seconds_left=$((end - now))
echo "Time left until 6AM cutoff: $seconds_left seconds" | tee -a "$WRAPPER_LOG"

# --- Run migration core with timeout ---
summary_log=$(timeout "$seconds_left"s $CORE_SCRIPT "$SRC_DIR" "$DST_DIR" "$LOG_DIR" 2>&1)
status=$?

if [ $status -eq 124 ]; then
    echo "Migration stopped at 6AM cutoff by timeout" | tee -a "$WRAPPER_LOG"
    status=1
fi

echo "Migration core exit status: $status" | tee -a "$WRAPPER_LOG"
echo "Summary log reported: $summary_log" | tee -a "$WRAPPER_LOG"

# --- Email alert ---
#subject="Migration Report [$TIMESTAMP]"
#if [ $status -eq 0 ]; then
#    subject="[SUCCESS] $subject"
#elif [ $status -eq 1 ]; then
#    subject="[WARNING] $subject"
#else
#    subject="[ERROR] $subject"
#fi
#
#{
#  echo "Nightly Migration Job - $TIMESTAMP"
#  echo "Source: $SRC_DIR"
#  echo "Destination: $DST_DIR"
#  echo "Exit Status: $status"
#  echo ""
#  echo "Summary Report (inline):"
#  echo "-------------------------------------"
#  if [ -f "$summary_log" ]; then
#      cat "$summary_log"
#  else
#      echo "No summary log found (job may have been interrupted early)"
#  fi
#} | mailx -s "$subject" "$ADMIN_EMAIL"
#
#echo "Email sent to $ADMIN_EMAIL" | tee -a "$WRAPPER_LOG"

# --- Rotate old logs ---
find "$LOG_DIR" -type f -mtime +$RETENTION_DAYS -exec rm -f {} \;

echo "Old logs older than $RETENTION_DAYS days cleaned up" | tee -a "$WRAPPER_LOG"
echo "===== Nightly Migration Completed ====="
