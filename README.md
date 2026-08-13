# Kuzka

GitOps-based baseline setup and continuous maintenance for a homelab cluster
(Linux servers today, macOS hosts eventually), networked over Tailscale.
Formerly named ATC (Air Traffic Control).

## Architecture

Two layers, each with its own reconciliation loop. Git is the source of
truth for both — nothing gets applied by hand.

### 1. Host OS layer — `hosts/` (Ansible)

Packages, Tailscale enrollment, Docker engine install, security posture
checks. Applied via **`ansible-pull`** on a systemd timer running on every
host (see `hosts/bootstrap/`) — each host reconciles itself against this
repo on a schedule, so drift gets corrected automatically without anyone
running a playbook by hand.

[Semaphore UI](https://github.com/semaphoreui/semaphore) sits alongside for
visibility (run history, dashboard) and on-demand/webhook-triggered runs —
it is not the primary execution path, `ansible-pull` is.

Roles:
- `baseline` — users, SSH hardening, unattended-upgrades
- `tailscale` — install + join (tags-based, see inventory below)
- `docker` — Docker CE install; `docker_mode: standalone|swarm` toggles swarm-specific tasks
- `security-posture` — Lynis (general audit) + Linux Malware Detect / maldet

### 2. Application/stack layer — `stacks/` (Arcane)

Docker Compose / Swarm stack definitions, one directory per service.
[Arcane](https://github.com/ofkm/arcane) watches this tree directly and
handles sync, drift detection, and redeploys — it owns this layer, Ansible
does not touch running containers beyond the Docker engine itself.

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

## Bootstrapping a brand-new host

A fresh host has neither Ansible nor this repo yet, so `ansible-pull`
can't be the *first* step — see `hosts/bootstrap/bootstrap.sh`, which:

1. Installs `git` + `ansible`
2. Runs one immediate `ansible-pull` against this repo
3. Installs + enables the `kuzka-pull.service`/`.timer` systemd units so
   future runs happen on schedule without intervention

## Secrets

Nothing sensitive is committed in plaintext — Tailscale auth keys, Swarm
join tokens, etc. are expected via Ansible Vault or an external secret
source (TODO: pick one — see open decisions below).

## CI

`.github/workflows/lint.yml` runs `ansible-lint` + `yamllint` on every
push/PR. Since pushes to `main` are what `ansible-pull` actually applies
to live hosts, this lint gate is effectively the change-approval step —
review PRs like it.

## Open decisions (not yet settled)

- Where secrets (Tailscale authkeys, swarm join tokens) actually live —
  Ansible Vault committed to the repo, or pulled from an external store?
- Where git is hosted — self-hosted Gitea on the tailnet vs GitHub.
- Whether `tag:swarm-manager` join tokens get regenerated/rotated, and how.
- Provisioning substrate for Terraform (hypervisor/cloud/bare-metal mix) —
  needed before the provisioning layer can be scaffolded.
- Outline API field names in `console/src/lib/outline/client.ts` are
  unverified against a live instance — check on first real run.
