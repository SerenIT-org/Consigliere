#!/usr/bin/env bash
# One-time setup for a brand-new host: it has neither Ansible nor either
# repo yet, so reconcile.sh can't be the first step. Run this once, by hand
# or via cloud-init, then the systemd timer takes over (see reconcile.sh
# for what "either repo" means -- this framework repo + your own private
# fleet-config repo).
#
# Usage:
#   FRAMEWORK_REPO_URL=... FLEET_CONFIG_REPO_URL=... ./bootstrap.sh
#
# FLEET_CONFIG_REPO_URL must be reachable with whatever git credentials
# this host already has (SSH deploy key, credential helper, etc.) --
# provisioning that access is a separate, out-of-band step.
set -euo pipefail

: "${FRAMEWORK_REPO_URL:?Set FRAMEWORK_REPO_URL to the git remote for this repo}"
FRAMEWORK_REPO_BRANCH="${FRAMEWORK_REPO_BRANCH:-main}"

: "${FLEET_CONFIG_REPO_URL:?Set FLEET_CONFIG_REPO_URL to your PRIVATE fleet-config repo}"
FLEET_CONFIG_REPO_BRANCH="${FLEET_CONFIG_REPO_BRANCH:-main}"

WORKDIR="/opt/fleet-reconcile"

echo "==> Installing git + ansible"
apt-get update
apt-get install -y git ansible

echo "==> Writing environment file for future reconciliation runs"
cat > /etc/fleet-reconcile.env <<EOF
FRAMEWORK_REPO_URL=$FRAMEWORK_REPO_URL
FRAMEWORK_REPO_BRANCH=$FRAMEWORK_REPO_BRANCH
FLEET_CONFIG_REPO_URL=$FLEET_CONFIG_REPO_URL
FLEET_CONFIG_REPO_BRANCH=$FLEET_CONFIG_REPO_BRANCH
EOF
chmod 600 /etc/fleet-reconcile.env

echo "==> Cloning framework repo (to get reconcile.sh)"
mkdir -p "$WORKDIR"
git clone --branch "$FRAMEWORK_REPO_BRANCH" "$FRAMEWORK_REPO_URL" "$WORKDIR/framework"

echo "==> Running first reconciliation"
set -a
source /etc/fleet-reconcile.env
set +a
"$WORKDIR/framework/hosts/bootstrap/reconcile.sh"

echo "==> Installing systemd timer for future reconciliation runs"
cp "$WORKDIR/framework/hosts/bootstrap/fleet-reconcile.service" /etc/systemd/system/fleet-reconcile.service
cp "$WORKDIR/framework/hosts/bootstrap/fleet-reconcile.timer" /etc/systemd/system/fleet-reconcile.timer

systemctl daemon-reload
systemctl enable --now fleet-reconcile.timer

echo "==> Done. Reconciliation now runs automatically every ~20min."
echo "    Check status with: systemctl status fleet-reconcile.timer"
