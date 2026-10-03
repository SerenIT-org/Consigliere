#!/usr/bin/env python3
"""Ansible dynamic inventory: this host only, named by its own Tailscale
hostname. No API key, no network call, no taxonomy.

Each host reconciles itself (hosts/bootstrap/reconcile.sh), so the inventory
is just "me", with a few facts (addresses, and the Tailscale tags as the
informational `tailscale_node_tags`; nothing in the framework relies on tags).
Which groups a host belongs to is declared in the fleet-config repo's host
table (config/inventory/hosts.yml), keyed by this same hostname. If Tailscale
isn't installed or running yet (a brand-new host), the OS hostname is used.

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


def me():
    try:
        return status()["Self"]
    except Exception:  # tailscale missing / not logged in yet
        import socket
        return {"HostName": socket.gethostname().split(".")[0]}


def build():
    me_ = me()
    name = (me_.get("HostName") or "").strip() or "localhost"
    ips = me_.get("TailscaleIPs") or []
    return {
        "_meta": {"hostvars": {name: {
            "ansible_connection": "local",
            "tailscale_node_tags": me_.get("Tags") or [],
            "tailscale_ips": ips,
            "tailscale_ipv4": next((i for i in ips if ":" not in i), ""),
            "tailscale_dns_name": (me_.get("DNSName") or "").rstrip("."),
        }}},
        "all": {"hosts": [name]},
    }


if __name__ == "__main__":
    if "--name" in sys.argv:       # used by reconcile.sh to --limit the run to this host
        print(next(iter(build()["all"]["hosts"])))
    elif "--host" in sys.argv:
        print("{}")
    else:
        json.dump(build(), sys.stdout)
