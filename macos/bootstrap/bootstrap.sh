#!/usr/bin/env bash
# One-time setup for a new Mac: clones this repo, installs Ansible via
# Homebrew if needed, runs one immediate apply, then installs the launchd
# agent so future runs happen on schedule (macOS has no ansible-pull —
# this is the closest equivalent, see com.kuzka.pull.plist).
#
# Usage: KUZKA_REPO_URL=... ./bootstrap.sh
set -euo pipefail

: "${KUZKA_REPO_URL:?Set KUZKA_REPO_URL to this repo's git remote}"
KUZKA_REPO_DIR="${KUZKA_REPO_DIR:-$HOME/.kuzka}"

if ! command -v brew &>/dev/null; then
  echo "==> Homebrew not found — install it first: https://brew.sh"
  exit 1
fi

echo "==> Installing ansible"
brew install ansible git

echo "==> Cloning Kuzka repo to $KUZKA_REPO_DIR"
if [ -d "$KUZKA_REPO_DIR/.git" ]; then
  git -C "$KUZKA_REPO_DIR" pull --ff-only
else
  git clone "$KUZKA_REPO_URL" "$KUZKA_REPO_DIR"
fi

echo "==> Running first apply"
(cd "$KUZKA_REPO_DIR" && ansible-playbook -i localhost, macos/site.yml)

echo "==> Installing launchd agent for future reconciliation runs"
sed "s|%KUZKA_REPO_DIR%|$KUZKA_REPO_DIR|" \
  "$(dirname "$0")/com.kuzka.pull.plist" > "$HOME/Library/LaunchAgents/com.kuzka.pull.plist"

launchctl unload "$HOME/Library/LaunchAgents/com.kuzka.pull.plist" 2>/dev/null || true
launchctl load "$HOME/Library/LaunchAgents/com.kuzka.pull.plist"

echo "==> Done. Reconciliation now runs automatically every ~20min."
echo "    Logs: /tmp/kuzka-pull.log"
