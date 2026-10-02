#!/usr/bin/env bash
# One-time setup for a brand-new host: it has neither Ansible nor either
# repo yet, so reconcile.sh can't be the first step. Run this once, by hand
# or via cloud-init, then the systemd timer takes over (see reconcile.sh
# for what "either repo" means -- this framework repo + your own private
# fleet-config repo).
#
# Usage:
#   FRAMEWORK_REPO_URL=... FLEET_CONFIG_REPO_URL=git@github.com:you/fleet.git \
#   VAULT_PASSWORDS_DIR=/path/to/dir ./bootstrap.sh
#
# Access to the PRIVATE fleet-config repo is set up for you
# (ensure-access.sh): the host generates its own read-only deploy key and, if
# FLEET_CONFIG_REGISTER_TOKEN (a GitHub token allowed to manage that repo's
# deploy keys; used once, never stored) is set, registers it automatically --
# otherwise it prints the public key and waits for you to add it. To use a key
# you already have instead, pass FLEET_CONFIG_DEPLOY_KEY_FILE.
#
# Vault passwords can't be generated, so supply them: VAULT_PASSWORDS_DIR is a
# directory with one file per vault id, named for the id (`base`, plus one per
# scoped group this host belongs to, e.g. `server_traefik`). Give a host ONLY the
# passwords for the scopes it should be able to read. They are installed to
# /etc/fleet-reconcile/vault.d/ (0600); delete the source copies afterwards.
set -euo pipefail

: "${FRAMEWORK_REPO_URL:?Set FRAMEWORK_REPO_URL to the git remote for this repo}"
FRAMEWORK_REPO_BRANCH="${FRAMEWORK_REPO_BRANCH:-}"   # empty = the remote default branch

: "${FLEET_CONFIG_REPO_URL:?Set FLEET_CONFIG_REPO_URL to your PRIVATE fleet-config repo}"
FLEET_CONFIG_REPO_BRANCH="${FLEET_CONFIG_REPO_BRANCH:-}"   # empty = the remote default branch

WORKDIR="/opt/fleet-reconcile"
CRED_DIR="/etc/fleet-reconcile"

# Paths (on this host, already copied over out-of-band) to the read-only
# deploy key for the fleet-config repo and the ansible-vault password.
# Both get moved into $CRED_DIR with tight permissions; reconcile.sh reads
# them from there on every run.
FLEET_CONFIG_DEPLOY_KEY_FILE="${FLEET_CONFIG_DEPLOY_KEY_FILE:-}"
VAULT_PASSWORDS_DIR="${VAULT_PASSWORDS_DIR:-}"

echo "==> Installing git + ansible"
apt-get update
apt-get install -y git ansible curl

echo "==> Installing host-local credentials"
install -d -m 0700 "$CRED_DIR"
if [ -n "$FLEET_CONFIG_DEPLOY_KEY_FILE" ]; then
  install -m 0600 "$FLEET_CONFIG_DEPLOY_KEY_FILE" "$CRED_DIR/deploy_key"
fi
if [ -n "$VAULT_PASSWORDS_DIR" ]; then
  install -d -m 0700 "$CRED_DIR/vault.d"
  for f in "$VAULT_PASSWORDS_DIR"/*; do
    [ -f "$f" ] && install -m 0600 "$f" "$CRED_DIR/vault.d/$(basename "$f")"
  done
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
git clone ${FRAMEWORK_REPO_BRANCH:+--branch "$FRAMEWORK_REPO_BRANCH"} "$FRAMEWORK_REPO_URL" "$WORKDIR/framework"

echo "==> Making sure this host can read the private fleet-config repo"
CRED_DIR="$CRED_DIR" FLEET_CONFIG_REPO_URL="$FLEET_CONFIG_REPO_URL" \
  "$WORKDIR/framework/hosts/bootstrap/ensure-access.sh"

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
