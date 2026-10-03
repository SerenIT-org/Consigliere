#!/usr/bin/env bash
# Gives this host its own age key, the identity its secrets are encrypted to.
# The private half never leaves the host (/etc/fleet-reconcile/age.key, 0600).
# Prints the public half so the admin can grant this host its secrets.
#
# Env: CRED_DIR (default /etc/fleet-reconcile), FRAMEWORK_DIR (to name the host).
set -euo pipefail
CRED_DIR="${CRED_DIR:-/etc/fleet-reconcile}"
KEY="$CRED_DIR/age.key"

command -v age-keygen >/dev/null || { echo "ERROR: age-keygen not found (apt install age)" >&2; exit 1; }
install -d -m 0700 "$CRED_DIR"
if [ ! -f "$KEY" ]; then
  echo "==> Generating this host's age key"
  ( umask 077; age-keygen -o "$KEY" 2>/dev/null )
fi
pub="$(age-keygen -y "$KEY")"
name="$(python3 "${FRAMEWORK_DIR:-/opt/fleet-reconcile/framework}/hosts/inventory/tailscale_self.py" --name 2>/dev/null || hostname -s)"

echo
echo "This host's secrets recipient (public key; safe to share):"
echo "  $pub"
echo
echo "On your admin machine, in your fleet repo, grant it its secrets:"
echo "  scripts/access.sh add-host $name $pub"
echo "  scripts/access.sh sync"
echo "  git add -A && git commit -m 'Add $name' && git push"
echo
if [ -t 0 ]; then
  read -r -p "Press Enter once that is pushed (Ctrl-C to abort)... " _
fi
