#!/bin/bash
#SBATCH --job-name=io_poll
#SBATCH --partition=normal
#SBATCH --time=7-00:00:00
#SBATCH --cpus-per-task=1
#SBATCH --mem=2G
#SBATCH --output=/oak/stanford/groups/brianhie/changdan/issherlockslow/logs/slurm-%j.out
#SBATCH --signal=B:TERM@120
#SBATCH --dependency=singleton
#SBATCH --requeue

# Polls every $INTERVAL seconds on a SLURM compute node. Self-resubmits
# ~2 min before walltime expires, so the loop runs indefinitely without
# manual intervention. --dependency=singleton prevents two copies from
# ever running simultaneously.
#
# Submit once with:  sbatch poll_io.sbatch
# Stop with:         scancel <jobid>   (then also kill the queued successor
#                                       with squeue -u $USER -n io_poll)

set -u

BASE_DIR="/oak/stanford/groups/brianhie/changdan/issherlockslow"
SCRIPT_PATH="$BASE_DIR/poll_io.sbatch"
PROBE="$BASE_DIR/test_io3.sh"
PUSH="$BASE_DIR/push_to_gh.sh"
INTERVAL=900

resubmit_and_exit() {
    echo "[$(date -u +%FT%TZ)] caught TERM (walltime imminent or signal)"
    if NEW_ID=$(sbatch --parsable "$SCRIPT_PATH" 2>&1); then
        echo "[$(date -u +%FT%TZ)] queued successor job: $NEW_ID"
    else
        echo "[$(date -u +%FT%TZ)] ERROR: sbatch failed, no successor queued: $NEW_ID"
    fi
    exit 0
}
trap resubmit_and_exit TERM INT

echo "[$(date -u +%FT%TZ)] io_poll started on $(hostname -s), interval=${INTERVAL}s, walltime=7d"

while :; do
    bash "$PROBE" || echo "[$(date -u +%FT%TZ)] probe exited $?"
    bash "$PUSH"  || echo "[$(date -u +%FT%TZ)] push exited $?"
    # sleep in background + wait, so SIGTERM interrupts immediately
    sleep "$INTERVAL" &
    wait $!
done
