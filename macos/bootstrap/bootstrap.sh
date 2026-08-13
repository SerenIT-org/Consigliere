#!/usr/bin/env bash
# One-time setup for a new Mac: clones this repo, installs Ansible via
# Homebrew if needed, runs one immediate apply, then installs the launchd
# agent so future runs happen on schedule (macOS has no ansible-pull —
# this is the closest equivalent, see com.atc.pull.plist).
#
# Usage: ATC_REPO_URL=... ./bootstrap.sh
set -euo pipefail

: "${ATC_REPO_URL:?Set ATC_REPO_URL to this repo's git remote}"
ATC_REPO_DIR="${ATC_REPO_DIR:-$HOME/.atc}"

if ! command -v brew &>/dev/null; then
  echo "==> Homebrew not found — install it first: https://brew.sh"
  exit 1
fi

echo "==> Installing ansible"
brew install ansible git

echo "==> Cloning ATC repo to $ATC_REPO_DIR"
if [ -d "$ATC_REPO_DIR/.git" ]; then
  git -C "$ATC_REPO_DIR" pull --ff-only
else
  git clone "$ATC_REPO_URL" "$ATC_REPO_DIR"
fi

echo "==> Running first apply"
(cd "$ATC_REPO_DIR" && ansible-playbook -i localhost, macos/site.yml)

echo "==> Installing launchd agent for future reconciliation runs"
sed "s|%ATC_REPO_DIR%|$ATC_REPO_DIR|" \
  "$(dirname "$0")/com.atc.pull.plist" > "$HOME/Library/LaunchAgents/com.atc.pull.plist"

launchctl unload "$HOME/Library/LaunchAgents/com.atc.pull.plist" 2>/dev/null || true
launchctl load "$HOME/Library/LaunchAgents/com.atc.pull.plist"

echo "==> Done. Reconciliation now runs automatically every ~20min."
echo "    Logs: /tmp/atc-pull.log"
