#!/usr/bin/env bash
# One-time setup for a brand-new host: it has neither Ansible nor this repo
# yet, so ansible-pull can't be the first step. Run this once, by hand or
# via cloud-init, then the systemd timer takes over.
#
# Usage: ATC_REPO_URL=... ATC_REPO_BRANCH=main ./bootstrap.sh
set -euo pipefail

: "${ATC_REPO_URL:?Set ATC_REPO_URL to this repo's git remote}"
ATC_REPO_BRANCH="${ATC_REPO_BRANCH:-main}"

echo "==> Installing git + ansible"
apt-get update
apt-get install -y git ansible

echo "==> Running first ansible-pull"
ansible-pull \
  -U "$ATC_REPO_URL" \
  -C "$ATC_REPO_BRANCH" \
  -i inventory/tailscale.yml \
  hosts/site.yml

echo "==> Installing systemd timer for future reconciliation runs"
sed -e "s|%ATC_REPO_URL%|$ATC_REPO_URL|" \
    -e "s|%ATC_REPO_BRANCH%|$ATC_REPO_BRANCH|" \
    "$(dirname "$0")/atc-pull.service" > /etc/systemd/system/atc-pull.service
cp "$(dirname "$0")/atc-pull.timer" /etc/systemd/system/atc-pull.timer

systemctl daemon-reload
systemctl enable --now atc-pull.timer

echo "==> Done. Reconciliation now runs automatically every ~20min."
echo "    Check status with: systemctl status atc-pull.timer"
