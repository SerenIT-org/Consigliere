# Consigliere

GitOps-based baseline setup and continuous maintenance for a homelab cluster
(Linux servers today, macOS hosts eventually), networked over Tailscale.
Formerly named ATC (Air Traffic Control), then Kuzka.

See [VISION.md](VISION.md) for what this project actually is, how its
modules relate to each other and to the sibling `novak`/`flashCtrl`
projects, and what's deliberately out of scope.

## Architecture

Two layers, each with its own reconciliation loop. Git is the source of
truth for both — nothing gets applied by hand.

### 1. Host OS layer — `hosts/` (Ansible)

Packages, Tailscale enrollment, Docker engine install, security posture
checks. Applied via **`reconcile.sh`** on a systemd timer running on every
host (see `hosts/bootstrap/`) — each host reconciles itself against this
repo (plus your private fleet-config repo, see below) on a schedule, so
drift gets corrected automatically without anyone running a playbook by
hand.

[Semaphore UI](https://github.com/semaphoreui/semaphore) sits alongside for
visibility (run history, dashboard) and on-demand/webhook-triggered runs —
it is not the primary execution path, `ansible-pull` is.

Roles:
- `baseline` — users, SSH hardening, unattended-upgrades
- `tailscale` — install + join (tags-based, see inventory below)
- `docker` — Docker CE install; `docker_mode: standalone|swarm` toggles swarm-specific tasks
- `security_posture` — enrolls a Wazuh agent against `security_posture_wazuh_manager_addr`
  (see [stacks/wazuh/](stacks/wazuh/)); replaced an earlier Lynis+maldet
  approach, see VISION.md
- `wazuh_host` — applied only to `tag:wazuh-manager`, sets the
  `vm.max_map_count` sysctl the Wazuh indexer requires
- `arkeep_server` / `arkeep_agent` — centralized backups via
  [Arkeep](https://github.com/arkeep-io/arkeep): one host runs the server
  (`tag:arkeep-server`), every backed-up host runs the agent
  (`tag:arkeep-agent`), connecting outbound over gRPC
- `arcane_manager` / `arcane_agent` — deploys
  [Arcane](https://github.com/getarcaneapp/arcane) itself (one manager,
  agents elsewhere) — Ansible's job is getting Arcane running at all;
  everything in `stacks/` below is then Arcane's job, not Ansible's

### 2. Application/stack layer — `stacks/` (Arcane)

Docker Compose / Swarm stack definitions, one directory per service, once
Arcane itself is running (see `arcane_manager`/`arcane_agent` above — a
bootstrapping step, since Arcane can't GitOps-deploy itself). Arcane then
watches this tree directly and handles sync, drift detection, and
redeploys — it owns this layer, Ansible does not touch running containers
beyond the Docker engine itself and Arcane's own containers.

Scaffolded so far: `console/` (below) and `wazuh/` — the manager/indexer/
dashboard for fleet security monitoring, vendored as a git submodule
rather than hand-copied (see [stacks/wazuh/README.md](stacks/wazuh/README.md)).

### 3. macOS — `macos/`

Same philosophy (git is source of truth, self-reconciling), but Homebrew
instead of apt, and a launchd agent instead of a systemd timer since macOS
has no systemd. Security posture role is skipped for now — XProtect is
already native; revisit if that ever feels insufficient.

### 4. Fleet console — `console/` (Next.js)

A bespoke webUI, deployed as its own stack (`stacks/console/`) and gated
behind OIDC login via [Pocket ID](https://github.com/pocket-id/pocket-id).
One tile per machine — KVM link, SSH launch, dashboard links, live
reachability — sourced from a pluggable machine-data provider
(`console/src/lib/providers/`); the only implementation today reads one
Outline doc per machine and can regenerate a fleet-wide overview table
from those docs on demand, so nothing has to be hand-copied between pages.
See [console/README.md](console/README.md) for the per-doc convention and
setup. Status: scaffold builds and typechecks clean, not yet run against
real Outline/Pocket ID/Tailscale accounts.

### 5. Provisioning — not yet built

Terraform, for standing up new Debian servers themselves (not just
configuring ones that already exist) — the provisioning substrate is a mix
of hypervisor/cloud/bare-metal and not yet settled, so this hasn't been
scaffolded. `hosts/bootstrap/` + cloud-init covers "a box already exists,
get it self-reconciling" in the meantime.

## Inventory

No static inventory file — `hosts/inventory/tailscale.yml` uses the
`community.general.tailscale` dynamic inventory plugin, grouping hosts by
Tailscale ACL tags (`tag:server`, `tag:mac`, `tag:swarm-manager`, ...) so
new hosts join their group automatically as the tailnet grows.

## Public framework, private fleet config

This repo is meant to be public and generic — roles, the playbook, and a
tag-based Tailscale inventory config, with no site-specific values or
secrets anywhere in it. Everything specific to *your* actual fleet
(group_vars, host_vars, ansible-vault secrets) lives in a **separate,
private repo** you create from the template in
[fleet-config.example/](fleet-config.example/). See its README for setup.

## Bootstrapping a brand-new host

A fresh host has neither repo nor Ansible yet, so reconciliation can't be
the *first* step — see `hosts/bootstrap/bootstrap.sh`, which:

1. Installs `git` + `ansible`
2. Clones this framework repo
3. Runs `hosts/bootstrap/reconcile.sh` once, which also clones your private
   fleet-config repo, symlinks its `group_vars`/`host_vars` into place, and
   runs the playbook
4. Installs + enables `fleet-reconcile.service`/`.timer` so future runs
   happen on schedule without intervention — each run re-syncs both repos
   from scratch, so drift in either gets corrected automatically

## Secrets

Nothing sensitive is committed in this repo, ever — Tailscale auth keys,
Swarm join tokens, backup credentials, etc. all live in your private
fleet-config repo's ansible-vault-encrypted `group_vars/all/vault.yml`.
See [fleet-config.example/](fleet-config.example/) for the convention.

## CI

`.github/workflows/lint.yml` runs `ansible-lint` + `yamllint` on every
push/PR. Since pushes to `main` are what reconciliation actually applies
to live hosts, this lint gate is effectively the change-approval step —
review PRs like it. (Your private fleet-config repo should have its own
equivalent gate — this one only covers the framework.)

## Open decisions (not yet settled)

- Naming — "serenIT" vs "Consigliere" vs something else (conformIT was
  raised too). Internal docs still say "Consigliere"; infra-level names
  (env vars, systemd units) were deliberately made name-agnostic so this
  doesn't need a second mass-rename once it's settled.
- Where this framework repo itself is hosted — currently GitHub
  (`github.com/almadon/consigliere`), presumably staying there.
- Whether `tag:swarm-manager` join tokens get regenerated/rotated, and how.
- Provisioning substrate for Terraform (hypervisor/cloud/bare-metal mix) —
  needed before the provisioning layer can be scaffolded.
- Outline API field names in `console/src/lib/outline/client.ts` are
  unverified against a live instance — check on first real run.
- Wazuh's stable tag (submodule pinned to `v4.14.7` as of 2026-08-21) —
  reverify before deploying, since `main` already tracks an unreleased 5.x
  line.
- Nothing in `stacks/wazuh/` or the Wazuh-related roles has been run
  against a live host yet.
