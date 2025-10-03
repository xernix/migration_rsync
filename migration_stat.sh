#!/bin/bash
# migration_stats.sh
# Parse rsync logs (per top-level folder + root-level) to generate per-folder and grand total stats
# Exit codes:
#   0 = no files transferred
#   1 = some files transferred
#   2 = invalid usage
#   3 = no logs found
#
# USAGE:
# ./migration_stats.sh /root/migration/log
# ./migration_stats.sh /root/migration/log 20251003_000101

LOG_DIR="$1"
TIMESTAMP="$2"   # optional

if [ -z "$LOG_DIR" ]; then
  echo "Usage: $0 <LOG_DIR> [TIMESTAMP]"
  exit 2
fi

# Determine timestamp
if [ -z "$TIMESTAMP" ]; then
  TIMESTAMP=$(ls "$LOG_DIR"/rsync_*.log 2>/dev/null | \
    sed -E 's/.*_([0-9]{8}_[0-9]{6})\.log/\1/' | sort -u | tail -n 1)
fi

if [ -z "$TIMESTAMP" ]; then
  echo "No rsync logs found in $LOG_DIR"
  exit 3
fi

SUMMARY_LOG="$LOG_DIR/stats_${TIMESTAMP}.log"

echo "==== Source directory tree ====" | tee "$SUMMARY_LOG"
tree -L 1 /mnt/suppdoc/hrmis >> "$SUMMARY_LOG"

echo "==== Destination directory tree ====" | tee -a "$SUMMARY_LOG"
tree -L 1 /data/suppdoc/hrmis >> "$SUMMARY_LOG"

echo "===== Per-folder and Grand Total Stats =====" | tee -a "$SUMMARY_LOG"
echo "Processing logs for timestamp: $TIMESTAMP" | tee -a "$SUMMARY_LOG"

total_new=0
total_updated=0
total_deleted=0
total_files=0
total_bytes=0

for log in "$LOG_DIR"/rsync_*_"$TIMESTAMP".log; do
  [ -f "$log" ] || continue

  # Handle folder name extraction, including root-level log
  if [[ "$log" =~ rsync_root_${TIMESTAMP}\.log$ ]]; then
    folder_name="ROOT_FILES"
  else
    folder_name=$(basename "$log" | sed -E "s/^rsync_(.+)_${TIMESTAMP}\.log/\1/")
  fi

  # Parse counts
  new_count=$(grep -c '] >f+++++++++' "$log")
  updated_count=$(grep -c '] >f' "$log")
  deleted_count=$(grep -c '\*deleting' "$log")

  # Adjust updated count (exclude new files)
  updated_count=$((updated_count - new_count))

  file_count=$((new_count + updated_count + deleted_count))

  # Parse bytes sent
  bytes=$(grep -Eo 'sent [0-9]+ bytes' "$log" | awk '{sum+=$2} END {print sum+0}')
  human_bytes=$(numfmt --to=iec --suffix=B "$bytes" 2>/dev/null || echo "${bytes}B")


  if [ "$file_count" -gt 0 ] && [ "$bytes" -eq 0 ]; then
    # Interrupted case
    echo "Folder [$folder_name]: $file_count files (New: $new_count, Updated: $updated_count, Deleted: $deleted_count), INTERRUPTED (UNKNOWN bytes actually transferred)" | tee -a "$SUMMARY_LOG"
  else
    echo "Folder [$folder_name]: $file_count files (New: $new_count, Updated: $updated_count, Deleted: $deleted_count), $human_bytes transferred" | tee -a "$SUMMARY_LOG"
  fi

#  echo "Folder [$folder_name]: $file_count files (New: $new_count, Updated: $updated_count, Deleted: $deleted_count), $human_bytes transferred" | tee -a "$SUMMARY_LOG"

  total_new=$((total_new + new_count))
  total_updated=$((total_updated + updated_count))
  total_deleted=$((total_deleted + deleted_count))
  total_files=$((total_files + file_count))
  total_bytes=$((total_bytes + bytes))
done

human_total=$(numfmt --to=iec --suffix=B "$total_bytes" 2>/dev/null || echo "${total_bytes}B")

echo "" | tee -a "$SUMMARY_LOG"
echo "Grand Total: $total_files files (New: $total_new, Updated: $total_updated, Deleted: $total_deleted), $human_total + UNKNOWN bytes transferred" | tee -a "$SUMMARY_LOG"

echo "Summary written to: $SUMMARY_LOG"

# Exit status
if [ "$total_files" -eq 0 ]; then
  exit 0
else
  exit 1
fi
