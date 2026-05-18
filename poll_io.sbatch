#!/bin/bash
#SBATCH --job-name=io_poll
#SBATCH --partition=normal
#SBATCH --time=00:10:00
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G
#SBATCH --output=/oak/stanford/groups/brianhie/changdan/issherlockslow/logs/slurm-%j.out
#SBATCH --dependency=singleton
#SBATCH --requeue

# Run ONE probe + push, then schedule the next invocation 15 min later.
# Each job is short (~10 s); no sleep, so Sherlock's sleeper-job detector
# is happy. The --dependency=singleton ensures we never run two at once.
#
# Submit once with:  sbatch poll_io.sbatch
# Stop with:         scancel -n io_poll -u $USER

set -u

BASE_DIR="/oak/stanford/groups/brianhie/changdan/issherlockslow"
SCRIPT_PATH="$BASE_DIR/poll_io.sbatch"
PROBE="$BASE_DIR/test_io3.sh"
PUSH="$BASE_DIR/push_to_gh.sh"
INTERVAL_MIN=15

echo "[$(date -u +%FT%TZ)] io_poll run on $(hostname -s)"

bash "$PROBE" || echo "[$(date -u +%FT%TZ)] probe exited $?"
bash "$PUSH"  || echo "[$(date -u +%FT%TZ)] push exited $?"

# Schedule the next run.
if NEW_ID=$(sbatch --parsable --begin="now+${INTERVAL_MIN}minutes" "$SCRIPT_PATH" 2>&1); then
    echo "[$(date -u +%FT%TZ)] next run queued: $NEW_ID (begins +${INTERVAL_MIN}m)"
else
    echo "[$(date -u +%FT%TZ)] ERROR: sbatch failed, chain BROKEN: $NEW_ID"
    echo "[$(date -u +%FT%TZ)] you'll need to manually re-submit poll_io.sbatch"
fi
