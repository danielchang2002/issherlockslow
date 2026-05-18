#!/bin/bash
# One-time setup. Initialises a git repo here, wires up GitHub auth,
# and makes the first push so GitHub Pages goes live.
#
# Prerequisites you must have done in a browser first:
#   1. Create a public GitHub repo named  issherlockslow  under your account
#      (leave it EMPTY — no README, no .gitignore, no license)
#   2. Repo settings → Pages → Source = "Deploy from a branch",
#      Branch = main, Folder = /docs
#   3. Create a fine-grained PAT at https://github.com/settings/tokens?type=beta
#        - Repository access: only that one repo
#        - Permissions: Contents = Read and write
#      Copy the token. You'll paste it below.
#
# Then run:  bash setup.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOKEN_FILE="$HOME/.gh_iomonitor_token"

read -rp "GitHub username: " GH_USER
[[ -z "$GH_USER" ]] && { echo "username required"; exit 1; }

if [[ -s "$TOKEN_FILE" ]]; then
    echo "using existing token at $TOKEN_FILE"
else
    read -rsp "Paste your fine-grained PAT (input hidden): " GH_TOKEN
    echo
    [[ -z "$GH_TOKEN" ]] && { echo "token required"; exit 1; }
    umask 077
    printf "%s\n" "$GH_TOKEN" > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE"
    echo "saved token to $TOKEN_FILE (chmod 600)"
fi

GH_TOKEN="$(cat "$TOKEN_FILE")"
CLEAN_URL="https://github.com/${GH_USER}/issherlockslow.git"
CREDENTIALS_FILE="$HOME/.gh_iomonitor_credentials"

# Write a git-credentials file so the token isn't embedded in the URL
# (URL-embedded tokens leak into git output and .git/config)
umask 077
printf "https://%s:%s@github.com\n" "$GH_USER" "$GH_TOKEN" > "$CREDENTIALS_FILE"
chmod 600 "$CREDENTIALS_FILE"

cd "$SCRIPT_DIR"

if [[ -d .git ]]; then
    echo "git repo already initialised here"
else
    git init -q
    # Point HEAD at refs/heads/main before first commit
    # (works on older git that lacks `init -b`)
    git symbolic-ref HEAD refs/heads/main
    git config user.email "${USER}@sherlock.stanford.edu"
    git config user.name "${USER} (sherlock io poller)"
    git remote add origin "$CLEAN_URL"
fi

# Ensure remote URL is clean (no embedded credentials) and credential helper points at our file
git remote set-url origin "$CLEAN_URL"
git config credential.helper "store --file=$CREDENTIALS_FILE"

# Generate initial dashboard JSON
python3 "$SCRIPT_DIR/aggregator.py" || true

if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
    git add .
    git commit -q -m "initial: poller + dashboard"
    echo "pushing initial commit to origin/main..."
    git push -u origin main
    echo
    echo "Done. Dashboard will be live at:"
    echo "  https://${GH_USER}.github.io/issherlockslow/"
    echo "(first deploy can take ~1 minute)"
else
    echo "repo already has commits — leaving as is"
fi

echo
echo "Next: submit the poller:"
echo "  sbatch $SCRIPT_DIR/poll_io.sbatch"
