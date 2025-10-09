#!/bin/bash
# weekend_migration.sh
# Wrapper for migration_core.sh with Friday 10PM to Saturday 8PM scheduling

SRC_DIR="/mnt/suppdoc/hrmis"
DST_DIR="/data/suppdoc/hrmis"
LOG_DIR="/root/migration/log"
CORE_SCRIPT="/root/migration/migration_core.sh"

ADMIN_EMAIL="admin@example.com"
RETENTION_DAYS=90

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
WRAPPER_LOG="$LOG_DIR/wrapper_$TIMESTAMP.log"

mkdir -p "$LOG_DIR"

echo "===== Weekend Migration Started: $TIMESTAMP =====" | tee "$WRAPPER_LOG"

# --- Calculate time left until Saturday 8PM cutoff ---
now=$(date +%s)
# Calculate the Unix timestamp for the next Saturday at 20:00 (8 PM)
# Assuming this script is scheduled to start on Friday at 10 PM.
# If the current day is already Saturday and past 8 PM, it will pick next week's Saturday 8 PM.
end=$(date -d "this Saturday 20:00" +%s)

# Check if the calculated end time is in the past (only needed if the script isn't run by cron at the exact start time)
if [ "$now" -gt "$end" ]; then
    end=$(date -d "next Saturday 20:00" +%s)
fi

seconds_left=$((end - now))

# Safety check: If for some reason the time left is less than 5 minutes (300 seconds), we may exit early.
if [ "$seconds_left" -lt 300 ]; then
    echo "WARNING: Less than 5 minutes until cutoff. Exiting." | tee -a "$WRAPPER_LOG"
    exit 0
fi

echo "Time left until Saturday 8PM cutoff: $seconds_left seconds" | tee -a "$WRAPPER_LOG"

# --- Run migration core with timeout ---
# Use the calculated seconds_left as the maximum runtime for the core script
summary_log=$(timeout "$seconds_left"s "$CORE_SCRIPT" "$SRC_DIR" "$DST_DIR" "$LOG_DIR" 2>&1)
status=$?

if [ $status -eq 124 ]; then
    echo "Migration stopped at Saturday 8PM cutoff by timeout (Max runtime: $seconds_left seconds)" | tee -a "$WRAPPER_LOG"
    status=1
fi

echo "Migration core exit status: $status" | tee -a "$WRAPPER_LOG"
echo "Summary log reported: $summary_log" | tee -a "$WRAPPER_LOG"

# --- Email alert ---
# ... (Email section remains commented out or as is)

# --- Rotate old logs ---
find "$LOG_DIR" -type f -mtime +$RETENTION_DAYS -exec rm -f {} \;

echo "Old logs older than $RETENTION_DAYS days cleaned up" | tee -a "$WRAPPER_LOG"
echo "===== Weekend Migration Completed ====="
