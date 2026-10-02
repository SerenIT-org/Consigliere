#!/usr/bin/env bash
# Makes sure THIS host can read the private fleet-config repo -- the framework
# is public, the repo it depends on is not, so every host must be granted
# access when it's deployed. Called by bootstrap.sh; safe to re-run.
#
# How: each host holds its own read-only deploy key (generated here, never
# transferred, private half never leaves the host). Then:
#   - if the host can already read the repo, done;
#   - else if FLEET_CONFIG_REGISTER_TOKEN is set and the repo is on GitHub,
#     register this host's public key as a READ-ONLY deploy key via the API
#     (the token is used once, from stdin, and never stored);
#   - else print the public key and wait for you to add it (prompt on a tty,
#     otherwise poll up to ACCESS_WAIT_SECONDS, default 600).
# One key per host (GitHub only allows a deploy key on one repo anyway, and a
# lost host then costs one revocation, not a re-key of the fleet).
#
# Env: FLEET_CONFIG_REPO_URL (required, SSH form), CRED_DIR (default
# /etc/fleet-reconcile), FLEET_CONFIG_REGISTER_TOKEN, ACCESS_WAIT_SECONDS.
set -euo pipefail

: "${FLEET_CONFIG_REPO_URL:?Set FLEET_CONFIG_REPO_URL to your PRIVATE fleet-config repo (SSH URL)}"
CRED_DIR="${CRED_DIR:-/etc/fleet-reconcile}"
KEY="$CRED_DIR/deploy_key"
WAIT="${ACCESS_WAIT_SECONDS:-600}"
TITLE="consigliere-$(hostname -s)"

case "$FLEET_CONFIG_REPO_URL" in
  git@*:*|ssh://*) ;;
  *) echo "ERROR: FLEET_CONFIG_REPO_URL must be an SSH URL (git@host:owner/repo.git); a deploy key can't authenticate an https URL." >&2; exit 1 ;;
esac

install -d -m 0700 "$CRED_DIR"
if [ ! -f "$KEY" ]; then
  echo "==> Generating this host's deploy key"
  ssh-keygen -q -t ed25519 -N "" -C "$TITLE" -f "$KEY"
fi

can_read() {
  GIT_SSH_COMMAND="ssh -i $KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o BatchMode=yes" \
    git ls-remote --exit-code "$FLEET_CONFIG_REPO_URL" HEAD >/dev/null 2>&1
}

if can_read; then
  echo "==> Access to the fleet-config repo already works"
  exit 0
fi

# owner/repo from the URL, GitHub only (anything else: manual).
path=""
case "$FLEET_CONFIG_REPO_URL" in
  git@github.com:*)          path="${FLEET_CONFIG_REPO_URL#git@github.com:}" ;;
  ssh://git@github.com/*)    path="${FLEET_CONFIG_REPO_URL#ssh://git@github.com/}" ;;
esac
path="${path%.git}"

if [ -n "${FLEET_CONFIG_REGISTER_TOKEN:-}" ] && [ -n "$path" ]; then
  echo "==> Registering this host's key as a read-only deploy key on $path"
  pub="$(cut -d' ' -f1,2 "$KEY.pub")"
  body="$(printf '{"title":"%s","key":"%s","read_only":true}' "$TITLE" "$pub")"
  # Token via stdin config so it never appears in the process list.
  printf 'header = "Authorization: Bearer %s"\n' "$FLEET_CONFIG_REGISTER_TOKEN" |
    curl -fsS -K - -X POST -H "Accept: application/vnd.github+json" \
      -d "$body" "https://api.github.com/repos/$path/keys" >/dev/null ||
    echo "WARN: automatic registration failed (token scope? key already registered?) -- falling back to manual" >&2
  sleep 2
fi

if ! can_read; then
  echo
  echo "This host cannot read $FLEET_CONFIG_REPO_URL yet."
  echo "Add this as a READ-ONLY deploy key on that repo (title: $TITLE):"
  echo
  cat "$KEY.pub"
  echo
  if [ -t 0 ]; then
    until can_read; do
      read -r -p "Press Enter once the key is added (Ctrl-C to abort)... " _
    done
  else
    waited=0
    until can_read; do
      if [ "$waited" -ge "$WAIT" ]; then
        echo "ERROR: still no access after ${WAIT}s. Add the key above, then re-run." >&2
        exit 1
      fi
      sleep 15; waited=$((waited + 15))
    done
  fi
fi
echo "==> Access to the fleet-config repo confirmed"
