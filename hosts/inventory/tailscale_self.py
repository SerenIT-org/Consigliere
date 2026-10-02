#!/usr/bin/env python3
"""Ansible dynamic inventory: this host only, described by its own Tailscale
identity. No API key, no network call, no taxonomy.

Each host reconciles itself (hosts/bootstrap/reconcile.sh), so the inventory
is just "me" -- with my Tailscale tags exposed as the `tailscale_tags` host
variable. Mapping those tags to the framework's group names is the admin's
job and lives in their private fleet-config repo (config/inventory/groups.yml,
an ansible.builtin.constructed inventory), so tag names stay private and
custom. See consigliere-fleet-template/config/inventory/groups.yml.

Test hook: TAILSCALE_STATUS_JSON=<file> reads that file instead of running
`tailscale status --json`.
"""
import json
import os
import subprocess
import sys


def status():
    path = os.environ.get("TAILSCALE_STATUS_JSON")
    if path:
        with open(path) as fh:
            return json.load(fh)
    out = subprocess.run(
        [os.environ.get("TAILSCALE_BIN", "tailscale"), "status", "--json"],
        check=True, capture_output=True, text=True,
    ).stdout
    return json.loads(out)


def build():
    me = status()["Self"]
    name = (me.get("HostName") or "").strip() or "localhost"
    ips = me.get("TailscaleIPs") or []
    return {
        "_meta": {"hostvars": {name: {
            "ansible_connection": "local",
            "tailscale_tags": me.get("Tags") or [],
            "tailscale_ips": ips,
            "tailscale_ipv4": next((i for i in ips if ":" not in i), ""),
            "tailscale_dns_name": (me.get("DNSName") or "").rstrip("."),
        }}},
        "all": {"hosts": [name]},
    }


if __name__ == "__main__":
    if "--host" in sys.argv:
        print("{}")
    else:
        json.dump(build(), sys.stdout)
