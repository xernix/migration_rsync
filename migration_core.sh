#!/bin/bash
# migration_core.sh
# Migration + verification using rsync with --partial --append-verify

SRC_DIR="$1"
DST_DIR="$2"
LOG_DIR="$3"

if [ -z "$SRC_DIR" ] || [ -z "$DST_DIR" ] || [ -z "$LOG_DIR" ]; then
  echo "Usage: $0 <SRC_DIR> <DST_DIR> <LOG_DIR>"
  exit 2
fi

mkdir -p "$LOG_DIR"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RSYNC_LOG="$LOG_DIR/rsync_$TIMESTAMP.log"
VERIFY_LOG="$LOG_DIR/verify_$TIMESTAMP.log"
SAMPLE_LOG="$LOG_DIR/sample_hash_$TIMESTAMP.log"
SUMMARY_LOG="$LOG_DIR/summary_$TIMESTAMP.log"

PARALLEL_JOBS=4
SAMPLE_COUNT=20

echo "===== Step 1: Rsync by top-level directories =====" | tee "$RSYNC_LOG"

# Sync directories in parallel
find "$SRC_DIR" -mindepth 1 -maxdepth 1 -type d | \
  parallel -j "$PARALLEL_JOBS" rsync -a --partial --append-verify {} "$DST_DIR" 2>&1 | tee -a "$RSYNC_LOG"

# Sync root-level files
find "$SRC_DIR" -maxdepth 1 -type f | \
  parallel -j "$PARALLEL_JOBS" rsync -a --partial --append-verify {} "$DST_DIR" 2>&1 | tee -a "$RSYNC_LOG"

echo "===== Step 2: Verification with rsync checksums =====" | tee "$VERIFY_LOG"

rsync -a --dry-run --checksum "$SRC_DIR"/ "$DST_DIR"/ 2>&1 | tee -a "$VERIFY_LOG"

echo "===== Step 3: Optional sample hash verification =====" | tee "$SAMPLE_LOG"

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
verify_diffs=$(grep -c "^>" "$VERIFY_LOG")

{
  echo "===== Migration Summary ($TIMESTAMP) ====="
  echo "Source: $SRC_DIR"
  echo "Destination: $DST_DIR"
  echo ""
  echo "Rsync Transfer Log:   $RSYNC_LOG"
  echo "Rsync Verify Log:     $VERIFY_LOG"
  echo "Sample Hash Log:      $SAMPLE_LOG"
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
