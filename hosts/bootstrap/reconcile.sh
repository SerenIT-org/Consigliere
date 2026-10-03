#!/usr/bin/env bash
# Replaces a bare `ansible-pull` with a two-repo reconciliation:
#
#   1. This framework repo (public, generic): the role library, a default
#      playbook, and a one-host inventory script. No secrets, no taxonomy,
#      nothing site-specific -- usable by anyone running their own fleet.
#   2. A private "fleet-config" repo (yours) that says what *you* want out of
#      the framework and holds your secrets. Under config/ it provides:
#        inventory/hosts.yml    REQUIRED  your host table: each host (by its
#                                         Tailscale hostname) and its values
#        inventory/groups.yml   REQUIRED  turns those values into groups
#        tags/<dim>/<value>.yml optional  what each util:/feat: tag runs (roles,
#                                         task files); overrides hosts/tags/
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
FRAMEWORK_REPO_BRANCH="${FRAMEWORK_REPO_BRANCH:-}"   # empty = the remote default branch

: "${FLEET_CONFIG_REPO_URL:?Set FLEET_CONFIG_REPO_URL to your PRIVATE fleet-config repo}"
FLEET_CONFIG_REPO_BRANCH="${FLEET_CONFIG_REPO_BRANCH:-}"   # empty = the remote default branch

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
# only; each file in vault.d/ is the password for the vault id of the same name.
CRED_DIR="${RECONCILE_CRED_DIR:-/etc/fleet-reconcile}"
DEPLOY_KEY="$CRED_DIR/deploy_key"
VAULT_DIR="$CRED_DIR/vault.d"   # one password file per vault id (see below)

mkdir -p "$WORKDIR"

# An empty branch means "whatever the remote's default branch is", so a repo
# whose default is master or main works without configuration.
sync_repo() {
  local url="$1" branch="$2" dir="$3"
  if [ -d "$dir/.git" ]; then
    git -C "$dir" fetch origin
    if [ -n "$branch" ]; then
      git -C "$dir" checkout "$branch"
      git -C "$dir" reset --hard "origin/$branch"
    else
      git -C "$dir" remote set-head origin --auto >/dev/null
      git -C "$dir" reset --hard origin/HEAD
    fi
  elif [ -n "$branch" ]; then
    git clone --branch "$branch" "$url" "$dir"
  else
    git clone "$url" "$dir"
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
[ -f "$CONF/inventory/hosts.yml" ] || fail "$CONF/inventory/hosts.yml not found -- the host table is required, otherwise no role beyond the baseline would ever match"
[ -f "$CONF/inventory/groups.yml" ] || fail "$CONF/inventory/groups.yml not found -- it turns the host table's values into groups and is required"
# Group vars are required (without them every role would run with no config).
# Per-host vars are optional: git can't track an empty directory, and a fleet
# with no per-host overrides is perfectly valid.
[ -d "$CONF/vars/group" ] || fail "$CONF/vars/group not found in the fleet-config repo"

echo "==> Assembling run directory"
RUN_DIR="$WORKDIR/run"
rm -rf "$RUN_DIR"
mkdir -p "$RUN_DIR"
ln -s "$CONF/vars/group" "$RUN_DIR/group_vars"
if [ -d "$CONF/vars/host" ]; then ln -s "$CONF/vars/host" "$RUN_DIR/host_vars"; fi
# Per-host secrets (e.g. secrets/cw/<certificate>.yml): not loaded automatically;
# roles read only the files a host asked for, each with its own vault id.
EXTRA_VARS=()
if [ -d "$CONF/secrets" ]; then
  ln -s "$CONF/secrets" "$RUN_DIR/secrets"
  EXTRA_VARS=(-e "fleet_secrets_dir=$RUN_DIR/secrets")
fi
# Tag manifests (what each util:/feat: tag runs): your config/tags/ first, then the
# framework's hosts/tags/.
EXTRA_VARS+=(-e "{\"fleet_tags_dirs\": [\"$CONF/tags\", \"$FRAMEWORK_DIR/hosts/tags\"]}")
if [ -f "$CONF/site.yml" ]; then
  cp "$CONF/site.yml" "$RUN_DIR/site.yml"
else
  cp "$FRAMEWORK_DIR/hosts/site.yml" "$RUN_DIR/site.yml"
fi

# Framework roles first; the fleet's own roles (if any) are also available.
export ANSIBLE_ROLES_PATH="$FRAMEWORK_DIR/hosts/roles${CONF:+:$CONF/roles}"
export ANSIBLE_CONFIG="$FRAMEWORK_DIR/hosts/ansible.cfg"

# Secrets are split by scope: config/vars/group/<group>/vault.yml is encrypted
# with a vault id named after the group (`base` for group/all). A host holds a
# password file in vault.d/ ONLY for the scopes it should read, and Ansible
# only loads a group's files for hosts in that group -- so a host never
# decrypts (or can decrypt) secrets outside its scopes. Per-host secrets in
# config/secrets/<kind>/<name>.yml use the vault id <kind>.<name> (kind cw =
# Cert Warden certificates) and are read only by hosts that request them.
VAULT_ARGS=()
if [ -d "$VAULT_DIR" ]; then
  for f in "$VAULT_DIR"/*; do
    [ -f "$f" ] && VAULT_ARGS+=(--vault-id "$(basename "$f")@$f")
  done
fi

# Inventory: this host (Tailscale name), the fleet's host table, then the rules
# that turn table values into groups. The table lists every host but the run is
# limited to this one.
SELF="$(python3 "$FRAMEWORK_DIR/hosts/inventory/tailscale_self.py" --name)"
INV_ARGS=(
  -i "$FRAMEWORK_DIR/hosts/inventory/tailscale_self.py"
  -i "$CONF/inventory/hosts.yml"
  -i "$CONF/inventory/groups.yml"
)
SELF_VARS="$(ansible-inventory "${INV_ARGS[@]}" --host "$SELF" 2>/dev/null || true)"
if ! grep -qE '"(util|feat)"' <<<"$SELF_VARS"; then
  echo "WARNING: '$SELF' has no entry (with util: or feat:) in inventory/hosts.yml -- only the baseline will run. The key must equal this host's Tailscale hostname." >&2
fi

echo "==> Running playbook"
cd "$RUN_DIR"
# shellcheck disable=SC2086  # ANSIBLE_EXTRA_ARGS is intentionally word-split
ansible-playbook \
  "${INV_ARGS[@]}" --limit "$SELF" \
  ${VAULT_ARGS[@]+"${VAULT_ARGS[@]}"} \
  ${EXTRA_VARS[@]+"${EXTRA_VARS[@]}"} \
  ${ANSIBLE_EXTRA_ARGS:-} \
  site.yml
