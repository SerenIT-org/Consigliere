# backup

Restic-based backups to an offsite S3-compatible bucket, applied to
`tag:backup-client` hosts. All real values live in your private
fleet-config repo, never here — see `fleet-config.example/` at the repo
root for the expected `group_vars/backup_clients.yml` and
`group_vars/all/vault.yml` shape.

## What's decided vs. open

- **Decided**: restic is the engine. The bucket must be genuinely offsite —
  sharing a failure domain with what it backs up defeats the point.
- **Decided**: secrets and site-specific values live in a separate private
  fleet-config repo, not in this framework.
- **Open**: whether Arkeep (restic+rclone, central server + gRPC/mTLS
  agents) or Zerobyte (restic web UI with OIDC SSO, no documented remote
  agents) fronts this with a central console/agent architecture later.
  This role only sets up restic itself.

## Tagging a host in

Tag it `tag:backup-client` in the Tailscale admin console (or
`tag:backup-server` for whichever host runs a central console, once one is
chosen) — see `hosts/inventory/tailscale.yml`.

## Status

Scaffolded, not deployed. No real restic repo/bucket exists yet.
