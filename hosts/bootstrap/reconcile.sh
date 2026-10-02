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

# Optional heartbeat so a host that fails or silently stops reconciling is
# noticed. HEARTBEAT_URL is pinged on success; HEARTBEAT_FAIL_URL on failure
# (defaults to "$HEARTBEAT_URL/fail", the healthchecks.io convention; for
# Uptime Kuma push monitors set both explicitly, e.g. ...?status=up and
# ...?status=down). Failures to ping never fail the run itself.
HEARTBEAT_URL="${HEARTBEAT_URL:-}"
HEARTBEAT_FAIL_URL="${HEARTBEAT_FAIL_URL:-${HEARTBEAT_URL:+$HEARTBEAT_URL/fail}}"
heartbeat() {
  [ -n "$1" ] || return 0
  curl -fsS -m 10 --retry 2 -o /dev/null "$1" || true
}
trap 'rc=$?; if [ "$rc" -eq 0 ]; then heartbeat "$HEARTBEAT_URL"; else heartbeat "$HEARTBEAT_FAIL_URL"; fi' EXIT

WORKDIR="${RECONCILE_WORKDIR:-/opt/fleet-reconcile}"
FRAMEWORK_DIR="$WORKDIR/framework"
FLEET_CONFIG_DIR="$WORKDIR/fleet-config"

# Host-local credentials, installed once by bootstrap.sh -- never inside
# either repo. The deploy key is read-only access to the fleet-config repo
# only; the vault password decrypts group_vars/all/vault.yml.
CRED_DIR="${RECONCILE_CRED_DIR:-/etc/fleet-reconcile}"
DEPLOY_KEY="$CRED_DIR/deploy_key"
VAULT_PASS_FILE="$CRED_DIR/vault_pass"

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
# Uses the host-local deploy key if present (see bootstrap.sh); otherwise
# falls back to whatever git credentials the host already has.
if [ -f "$DEPLOY_KEY" ]; then
  # IdentitiesOnly so this key is used for nothing but this clone/fetch.
  export GIT_SSH_COMMAND="ssh -i $DEPLOY_KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
fi
sync_repo "$FLEET_CONFIG_REPO_URL" "$FLEET_CONFIG_REPO_BRANCH" "$FLEET_CONFIG_DIR"
unset GIT_SSH_COMMAND

echo "==> Linking fleet-config into the framework checkout"
ln -sfn "$FLEET_CONFIG_DIR/group_vars" "$FRAMEWORK_DIR/hosts/group_vars"
ln -sfn "$FLEET_CONFIG_DIR/host_vars" "$FRAMEWORK_DIR/hosts/host_vars"

VAULT_ARGS=()
if [ -f "$VAULT_PASS_FILE" ]; then
  VAULT_ARGS=(--vault-password-file "$VAULT_PASS_FILE")
fi

echo "==> Running playbook"
cd "$FRAMEWORK_DIR/hosts"
ansible-playbook -i inventory/tailscale.yml "${VAULT_ARGS[@]}" site.yml
