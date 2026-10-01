#!/usr/bin/env bash
# Replaces a bare `ansible-pull` with a two-repo reconciliation:
#
#   1. This framework repo (public, generic -- roles, playbook, the
#      tag-based Tailscale inventory plugin config). No secrets, no
#      site-specific values live here, ever -- this repo is meant to be
#      usable by anyone running their own fleet.
#   2. A private "fleet-config" repo (yours, not this one) holding
#      group_vars/, host_vars/, and vault-encrypted secrets -- everything
#      specific to *your* actual hosts. See fleet-config.example/ in this
#      repo for the expected shape.
#
# This script clones/updates both, symlinks the private repos group_vars/
# host_vars into the framework checkout (gitignored there, see
# hosts/.gitignore), and runs the playbook. Run on a schedule via
# fleet-reconcile.timer (see fleet-reconcile.service/.timer in this
# directory) -- installed by bootstrap.sh.
set -euo pipefail

: "${FRAMEWORK_REPO_URL:?Set FRAMEWORK_REPO_URL to the git remote for this repo}"
FRAMEWORK_REPO_BRANCH="${FRAMEWORK_REPO_BRANCH:-main}"

: "${FLEET_CONFIG_REPO_URL:?Set FLEET_CONFIG_REPO_URL to your PRIVATE fleet-config repo}"
FLEET_CONFIG_REPO_BRANCH="${FLEET_CONFIG_REPO_BRANCH:-main}"

WORKDIR="${RECONCILE_WORKDIR:-/opt/fleet-reconcile}"
FRAMEWORK_DIR="$WORKDIR/framework"
FLEET_CONFIG_DIR="$WORKDIR/fleet-config"

mkdir -p "$WORKDIR"

sync_repo() {
  local url="$1" branch="$2" dir="$3"
  if [ -d "$dir/.git" ]; then
    git -C "$dir" fetch origin "$branch"
    git -C "$dir" checkout "$branch"
    git -C "$dir" reset --hard "origin/$branch"
  else
    git clone --branch "$branch" "$url" "$dir"
  fi
}

echo "==> Syncing framework repo"
sync_repo "$FRAMEWORK_REPO_URL" "$FRAMEWORK_REPO_BRANCH" "$FRAMEWORK_DIR"

echo "==> Syncing private fleet-config repo"
# NOTE: this needs its own read access to a private repo -- an SSH deploy
# key or credential helper already set up on this host. Provisioning that
# key is a one-time, out-of-band step (cloud-init, or manual) -- not
# handled here. See README.md.
sync_repo "$FLEET_CONFIG_REPO_URL" "$FLEET_CONFIG_REPO_BRANCH" "$FLEET_CONFIG_DIR"

echo "==> Linking fleet-config into the framework checkout"
ln -sfn "$FLEET_CONFIG_DIR/group_vars" "$FRAMEWORK_DIR/hosts/group_vars"
ln -sfn "$FLEET_CONFIG_DIR/host_vars" "$FRAMEWORK_DIR/hosts/host_vars"

VAULT_ARGS=()
if [ -f "$FLEET_CONFIG_DIR/.vault_pass" ]; then
  VAULT_ARGS=(--vault-password-file "$FLEET_CONFIG_DIR/.vault_pass")
fi

echo "==> Running playbook"
cd "$FRAMEWORK_DIR/hosts"
ansible-playbook -i inventory/tailscale.yml "${VAULT_ARGS[@]}" site.yml
