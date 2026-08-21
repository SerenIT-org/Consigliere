#!/usr/bin/env bash
# One-time setup for a new Mac: clones this repo, installs Ansible via
# Homebrew if needed, runs one immediate apply, then installs the launchd
# agent so future runs happen on schedule (macOS has no ansible-pull —
# this is the closest equivalent, see com.consigliere.pull.plist).
#
# Usage: CONSIGLIERE_REPO_URL=... ./bootstrap.sh
set -euo pipefail

: "${CONSIGLIERE_REPO_URL:?Set CONSIGLIERE_REPO_URL to this repo's git remote}"
CONSIGLIERE_REPO_DIR="${CONSIGLIERE_REPO_DIR:-$HOME/.consigliere}"

if ! command -v brew &>/dev/null; then
  echo "==> Homebrew not found — install it first: https://brew.sh"
  exit 1
fi

echo "==> Installing ansible"
brew install ansible git

echo "==> Cloning Consigliere repo to $CONSIGLIERE_REPO_DIR"
if [ -d "$CONSIGLIERE_REPO_DIR/.git" ]; then
  git -C "$CONSIGLIERE_REPO_DIR" pull --ff-only
else
  git clone "$CONSIGLIERE_REPO_URL" "$CONSIGLIERE_REPO_DIR"
fi

echo "==> Running first apply"
(cd "$CONSIGLIERE_REPO_DIR" && ansible-playbook -i localhost, macos/site.yml)

echo "==> Installing launchd agent for future reconciliation runs"
sed "s|%CONSIGLIERE_REPO_DIR%|$CONSIGLIERE_REPO_DIR|" \
  "$(dirname "$0")/com.consigliere.pull.plist" > "$HOME/Library/LaunchAgents/com.consigliere.pull.plist"

launchctl unload "$HOME/Library/LaunchAgents/com.consigliere.pull.plist" 2>/dev/null || true
launchctl load "$HOME/Library/LaunchAgents/com.consigliere.pull.plist"

echo "==> Done. Reconciliation now runs automatically every ~20min."
echo "    Logs: /tmp/consigliere-pull.log"
