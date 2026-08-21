#!/usr/bin/env bash
# One-time setup for a brand-new host: it has neither Ansible nor this repo
# yet, so ansible-pull can't be the first step. Run this once, by hand or
# via cloud-init, then the systemd timer takes over.
#
# Usage: CONSIGLIERE_REPO_URL=... CONSIGLIERE_REPO_BRANCH=main ./bootstrap.sh
set -euo pipefail

: "${CONSIGLIERE_REPO_URL:?Set CONSIGLIERE_REPO_URL to this repo's git remote}"
CONSIGLIERE_REPO_BRANCH="${CONSIGLIERE_REPO_BRANCH:-main}"

echo "==> Installing git + ansible"
apt-get update
apt-get install -y git ansible

echo "==> Running first ansible-pull"
ansible-pull \
  -U "$CONSIGLIERE_REPO_URL" \
  -C "$CONSIGLIERE_REPO_BRANCH" \
  -i inventory/tailscale.yml \
  hosts/site.yml

echo "==> Installing systemd timer for future reconciliation runs"
sed -e "s|%CONSIGLIERE_REPO_URL%|$CONSIGLIERE_REPO_URL|" \
    -e "s|%CONSIGLIERE_REPO_BRANCH%|$CONSIGLIERE_REPO_BRANCH|" \
    "$(dirname "$0")/consigliere-pull.service" > /etc/systemd/system/consigliere-pull.service
cp "$(dirname "$0")/consigliere-pull.timer" /etc/systemd/system/consigliere-pull.timer

systemctl daemon-reload
systemctl enable --now consigliere-pull.timer

echo "==> Done. Reconciliation now runs automatically every ~20min."
echo "    Check status with: systemctl status consigliere-pull.timer"
