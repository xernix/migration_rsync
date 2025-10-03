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
# Run on latest logs
# ./migration_stats.sh /root/migration/log
#
# Run on specific timestamp
# ./migration_stats.sh /root/migration/log 20251003_000101
#
# Check exit status
# ./migration_stats.sh /root/migration/log || echo "Some files transferred"

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

echo "===== Per-folder and Grand Total Stats =====" | tee "$SUMMARY_LOG"
echo "Processing logs for timestamp: $TIMESTAMP" | tee -a "$SUMMARY_LOG"

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

  file_count=$(grep -c '>f' "$log")
  bytes=$(grep -Eo 'sent [0-9]+ bytes' "$log" | awk '{sum+=$2} END {print sum+0}')
  human_bytes=$(numfmt --to=iec --suffix=B "$bytes" 2>/dev/null || echo "${bytes}B")

  echo "Folder [$folder_name]: $file_count files, $human_bytes transferred" | tee -a "$SUMMARY_LOG"

  total_files=$((total_files + file_count))
  total_bytes=$((total_bytes + bytes))
done

human_total=$(numfmt --to=iec --suffix=B "$total_bytes" 2>/dev/null || echo "${total_bytes}B")

echo "" | tee -a "$SUMMARY_LOG"
echo "Grand Total: $total_files files, $human_total transferred" | tee -a "$SUMMARY_LOG"

echo "Summary written to: $SUMMARY_LOG"

# Exit status
if [ "$total_files" -eq 0 ]; then
  exit 0
else
  exit 1
fi
