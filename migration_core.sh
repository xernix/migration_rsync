#!/bin/bash
# migration_core.sh
# Migration + verification using rsync with --partial --append-verify --itemize-changes
# Logs are written per top-level folder for clarity
# Summary report parses all logs

SRC_DIR="$1"
DST_DIR="$2"
LOG_DIR="$3"

if [ -z "$SRC_DIR" ] || [ -z "$DST_DIR" ] || [ -z "$LOG_DIR" ]; then
  echo "Usage: $0 <SRC_DIR> <DST_DIR> <LOG_DIR>"
  exit 2
fi

mkdir -p "$LOG_DIR"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
VERIFY_LOG="$LOG_DIR/verify_$TIMESTAMP.log"
SAMPLE_LOG="$LOG_DIR/sample_hash_$TIMESTAMP.log"
SUMMARY_LOG="$LOG_DIR/summary_$TIMESTAMP.log"

PARALLEL_JOBS=4
SAMPLE_COUNT=20

echo "===== Step 1: Rsync by top-level directories ====="

# Array to track all per-folder logs
folder_logs=()

# Sync each top-level directory separately with GNU parallel
find "$SRC_DIR" -mindepth 1 -maxdepth 1 -type d | \
  parallel -j "$PARALLEL_JOBS" '
    dir_name=$(basename {})
    dir_log="'"$LOG_DIR"'/rsync_${dir_name}_'"$TIMESTAMP"'.log"
    echo ">> Syncing directory: $dir_name (log: $dir_log)"
    rsync -a --partial --append-verify --itemize-changes \
      --log-file="$dir_log" {} "'"$DST_DIR"'/"
    echo "$dir_log"
  ' | while read -r log; do folder_logs+=("$log"); done

# Sync root-level files
root_log="$LOG_DIR/rsync_root_$TIMESTAMP.log"
folder_logs+=("$root_log")
echo ">> Syncing root-level files (log: $root_log)"
rsync -a --partial --append-verify --itemize-changes \
  --log-file="$root_log" "$SRC_DIR"/ "$DST_DIR"/ \
  --exclude='*/'

echo "===== Step 2: Verification with rsync checksums ====="

rsync -a --dry-run --checksum --itemize-changes \
  "$SRC_DIR"/ "$DST_DIR"/ \
  --log-file="$VERIFY_LOG"

echo "===== Step 3: Optional sample hash verification ====="

sample_files=$(find "$SRC_DIR" -type f | shuf -n "$SAMPLE_COUNT")
mismatch_count=0
missing_count=0
ok_count=0

for f in $sample_files; do
    rel_path="${f#$SRC_DIR/}"
    src_hash=$(sha256sum "$f" | awk '{print $1}')
    if [ -f "$DST_DIR/$rel_path" ]; then
        dst_hash=$(sha256sum "$DST_DIR/$rel_path" | awk '{print $1}')
        if [ "$src_hash" = "$dst_hash" ]; then
            echo "[OK] $rel_path" | tee -a "$SAMPLE_LOG"
            ((ok_count++))
        else
            echo "[MISMATCH] $rel_path" | tee -a "$SAMPLE_LOG"
            ((mismatch_count++))
        fi
    else
        echo "[MISSING] $rel_path not found in destination" | tee -a "$SAMPLE_LOG"
        ((missing_count++))
    fi
done

echo "===== Step 4: Generate Summary Report =====" | tee "$SUMMARY_LOG"

verify_mismatches=$(grep -c "^deleting " "$VERIFY_LOG")
verify_diffs=$(grep -c "^[><c]" "$VERIFY_LOG")

{
  echo "===== Migration Summary ($TIMESTAMP) ====="
  echo "Source: $SRC_DIR"
  echo "Destination: $DST_DIR"
  echo ""
  echo "---- Per-folder rsync results ----"
  for log in "${folder_logs[@]}"; do
    folder_name=$(basename "$log" | sed -E "s/^rsync_(.+)_$TIMESTAMP\.log/\1/")
    total_changes=$(grep -c "^[><c]" "$log")
    echo "Folder [$folder_name]: $total_changes changes (see $log)"
  done
  echo ""
  echo "---- Rsync Verify Results ----"
  echo "Files flagged for re-sync (differences): $verify_diffs"
  echo "Files flagged as deleted:                $verify_mismatches"
  echo ""
  echo "---- Sample Hash Check ----"
  echo "OK files:        $ok_count"
  echo "Mismatched:      $mismatch_count"
  echo "Missing:         $missing_count"
  echo ""
  if [ "$verify_diffs" -eq 0 ] && [ "$verify_mismatches" -eq 0 ] && \
     [ "$mismatch_count" -eq 0 ] && [ "$missing_count" -eq 0 ]; then
      echo "Migration Status: SUCCESS - No issues detected"
      exit_code=0
  else
      echo "Migration Status: WARNING - Some issues detected"
      exit_code=1
  fi
} | tee -a "$SUMMARY_LOG"

echo "$SUMMARY_LOG"   # Path for wrapper to capture
exit $exit_code
