#!/usr/bin/env bash
# Installs the pinned sops release (secrets decryption) to /usr/local/bin/sops,
# verified against a pinned SHA-256. Idempotent: does nothing if that version is
# already installed. Linux only; used by bootstrap.sh and the `sops` role.
# To upgrade: change SOPS_VERSION and the two checksums (from the release's
# sops-vX.Y.Z.checksums.txt) together.
set -euo pipefail

SOPS_VERSION="3.13.3"
SHA256_LINUX_AMD64="e5bec3346a873ae91d871550f3e698c1aad962aff462a080e40f25fde17fef6b"
SHA256_LINUX_ARM64="53b0abacd38ef1b12a66d6c100956691b9cefce018d91f81e73ddf7438b94d77"

if command -v sops >/dev/null 2>&1 && sops --version 2>/dev/null | grep -q "$SOPS_VERSION"; then
  echo "OK sops $SOPS_VERSION already installed"
  exit 0
fi

case "$(uname -m)" in
  x86_64|amd64)  arch=amd64; want="$SHA256_LINUX_AMD64" ;;
  aarch64|arm64) arch=arm64; want="$SHA256_LINUX_ARM64" ;;
  *) echo "ERROR: no pinned sops build for $(uname -m)" >&2; exit 1 ;;
esac

tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
curl -fsSL -o "$tmp" "https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.linux.${arch}"
got="$(sha256sum "$tmp" | cut -d' ' -f1)"
[ "$got" = "$want" ] || { echo "ERROR: sops checksum mismatch (got $got)" >&2; exit 1; }
install -m 0755 "$tmp" /usr/local/bin/sops
echo "INSTALLED sops $SOPS_VERSION"
