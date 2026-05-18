#!/bin/bash
# Regenerate dashboard JSON and push to GitHub.
# Called by poll_io.sbatch after each probe. Failures (e.g. transient network)
# are logged and ignored — the next poll will catch up.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGG="$SCRIPT_DIR/aggregator.py"

log() { echo "[$(date -u +%FT%TZ)] push_to_gh: $*"; }

if [[ ! -d "$SCRIPT_DIR/.git" ]]; then
    log "ERROR: $SCRIPT_DIR is not a git repo — run setup.sh first"
    exit 0
fi

if ! python3 "$AGG"; then
    log "ERROR: aggregator failed; skipping push"
    exit 0
fi

cd "$SCRIPT_DIR" || { log "ERROR: cannot cd to $SCRIPT_DIR"; exit 0; }

if git diff --quiet --exit-code -- docs/data/latest.json; then
    log "no data change, skipping commit"
    exit 0
fi

git add docs/data/latest.json
if ! git commit -q -m "data: $(date -u +%FT%TZ)"; then
    log "ERROR: commit failed"
    exit 0
fi

if ! git push -q; then
    log "ERROR: push failed (will retry next poll)"
    exit 0
fi

log "pushed at $(date -u +%FT%TZ)"
