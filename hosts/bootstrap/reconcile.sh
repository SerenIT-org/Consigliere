#!/usr/bin/env bash
# Replaces a bare `ansible-pull` with a two-repo reconciliation:
#
#   1. This framework repo (public, generic): the role library, a default
#      playbook, and a one-host inventory script. No secrets, no taxonomy,
#      nothing site-specific -- usable by anyone running their own fleet.
#   2. A private "fleet-config" repo (yours) that says what *you* want out of
#      the framework and holds your secrets. Under config/ it provides:
#        inventory/groups.yml   REQUIRED  your Tailscale tag taxonomy -> the
#                                         framework's group names
#        vars/group/, vars/host/ REQUIRED  variables + vault-encrypted secrets
#        site.yml               optional  which roles run where (default: the
#                                         framework's hosts/site.yml)
#        roles/                 optional  your own site-specific roles/apps
#      (runbooks, stacks and the like also live there, but need no logic here.)
#      See consigliere-fleet-template/ for the expected shape.
#
# This script clones/updates both, assembles a throwaway run directory from
# them, and runs the playbook against *this host only* (each host reconciles
# itself). Run on a schedule via fleet-reconcile.timer, installed by
# bootstrap.sh. Extra ansible-playbook flags can be passed through
# ANSIBLE_EXTRA_ARGS, e.g. "--check --diff" for a read-only drift report.
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
# Where, inside the private repo, the vars live: <subdir>/vars/group and
# <subdir>/vars/host (see consigliere-fleet-template/).
FLEET_CONFIG_SUBDIR="${FLEET_CONFIG_SUBDIR:-config}"

# Host-local credentials, installed once by bootstrap.sh -- never inside
# either repo. The deploy key is read-only access to the fleet-config repo
# only; the vault password decrypts config/vars/group/all/vault.yml.
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

CONF="$FLEET_CONFIG_DIR/$FLEET_CONFIG_SUBDIR"
fail() { echo "ERROR: $1 (see consigliere-fleet-template/)" >&2; exit 1; }
[ -f "$CONF/inventory/groups.yml" ] || fail "$CONF/inventory/groups.yml not found -- the tag-to-group mapping is required, otherwise no role beyond the baseline would ever match"
for d in group host; do
  # Fail loudly: a missing dir would silently run every role with no vars.
  [ -d "$CONF/vars/$d" ] || fail "$CONF/vars/$d not found in the fleet-config repo"
done

echo "==> Assembling run directory"
RUN_DIR="$WORKDIR/run"
rm -rf "$RUN_DIR"
mkdir -p "$RUN_DIR"
ln -s "$CONF/vars/group" "$RUN_DIR/group_vars"
ln -s "$CONF/vars/host" "$RUN_DIR/host_vars"
if [ -f "$CONF/site.yml" ]; then
  cp "$CONF/site.yml" "$RUN_DIR/site.yml"
else
  cp "$FRAMEWORK_DIR/hosts/site.yml" "$RUN_DIR/site.yml"
fi

# Framework roles first; the fleet's own roles (if any) are also available.
export ANSIBLE_ROLES_PATH="$FRAMEWORK_DIR/hosts/roles${CONF:+:$CONF/roles}"
export ANSIBLE_CONFIG="$FRAMEWORK_DIR/hosts/ansible.cfg"

VAULT_ARGS=()
if [ -f "$VAULT_PASS_FILE" ]; then
  VAULT_ARGS=(--vault-password-file "$VAULT_PASS_FILE")
fi

echo "==> Running playbook"
cd "$RUN_DIR"
# shellcheck disable=SC2086  # ANSIBLE_EXTRA_ARGS is intentionally word-split
ansible-playbook \
  -i "$FRAMEWORK_DIR/hosts/inventory/tailscale_self.py" \
  -i "$CONF/inventory/groups.yml" \
  ${VAULT_ARGS[@]+"${VAULT_ARGS[@]}"} \
  ${ANSIBLE_EXTRA_ARGS:-} \
  site.yml
