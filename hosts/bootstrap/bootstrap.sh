#!/usr/bin/env bash
# One-time setup for a brand-new host: it has neither Ansible nor either
# repo yet, so reconcile.sh can't be the first step. Run this once, by hand
# or via cloud-init, then the systemd timer takes over (see reconcile.sh
# for what "either repo" means -- this framework repo + your own private
# fleet-config repo).
#
# Usage:
#   FRAMEWORK_REPO_URL=... FLEET_CONFIG_REPO_URL=... \
#   FLEET_CONFIG_DEPLOY_KEY_FILE=/path/to/key VAULT_PASSWORD_FILE=/path/to/pw \
#   ./bootstrap.sh
#
# The deploy key and vault password must already be on this host (scp over
# Tailscale SSH, cloud-init, etc.) -- they can't come from the private repo
# they unlock. After this runs, delete the source copies.
set -euo pipefail

: "${FRAMEWORK_REPO_URL:?Set FRAMEWORK_REPO_URL to the git remote for this repo}"
FRAMEWORK_REPO_BRANCH="${FRAMEWORK_REPO_BRANCH:-main}"

: "${FLEET_CONFIG_REPO_URL:?Set FLEET_CONFIG_REPO_URL to your PRIVATE fleet-config repo}"
FLEET_CONFIG_REPO_BRANCH="${FLEET_CONFIG_REPO_BRANCH:-main}"

WORKDIR="/opt/fleet-reconcile"
CRED_DIR="/etc/fleet-reconcile"

# Paths (on this host, already copied over out-of-band) to the read-only
# deploy key for the fleet-config repo and the ansible-vault password.
# Both get moved into $CRED_DIR with tight permissions; reconcile.sh reads
# them from there on every run.
FLEET_CONFIG_DEPLOY_KEY_FILE="${FLEET_CONFIG_DEPLOY_KEY_FILE:-}"
VAULT_PASSWORD_FILE="${VAULT_PASSWORD_FILE:-}"

echo "==> Installing git + ansible"
apt-get update
apt-get install -y git ansible curl

echo "==> Installing host-local credentials"
install -d -m 0700 "$CRED_DIR"
if [ -n "$FLEET_CONFIG_DEPLOY_KEY_FILE" ]; then
  install -m 0600 "$FLEET_CONFIG_DEPLOY_KEY_FILE" "$CRED_DIR/deploy_key"
fi
if [ -n "$VAULT_PASSWORD_FILE" ]; then
  install -m 0600 "$VAULT_PASSWORD_FILE" "$CRED_DIR/vault_pass"
fi

echo "==> Writing environment file for future reconciliation runs"
cat > /etc/fleet-reconcile.env <<EOF
FRAMEWORK_REPO_URL=$FRAMEWORK_REPO_URL
FRAMEWORK_REPO_BRANCH=$FRAMEWORK_REPO_BRANCH
FLEET_CONFIG_REPO_URL=$FLEET_CONFIG_REPO_URL
FLEET_CONFIG_REPO_BRANCH=$FLEET_CONFIG_REPO_BRANCH
HEARTBEAT_URL="${HEARTBEAT_URL:-}"
HEARTBEAT_FAIL_URL="${HEARTBEAT_FAIL_URL:-}"
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
