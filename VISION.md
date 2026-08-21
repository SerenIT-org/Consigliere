# What Consigliere is

(Renamed from ATC, then Kuzka, to Consigliere on 2026-08-21.)

Consigliere is a single pane of glass for a fleet of hosts: baseline config,
provisioning, updates, security posture, and out-of-band hardware access
(KVM/DRAC/IPMI/AMT/SSH), all declared in git and continuously checked
against what's actually true — not just applied once and forgotten.

## The core discipline: declare, apply, and separately check for drift

This isn't a new idea invented for Consigliere — it's the same pattern already
proven out in [`novak`](../novak/novak), stated plainly in that project's
own decision log:

> "The shape: declarative input, dumb applier, fail loudly. That drift
> check is the more valuable half." — `novak/docs/decisions.md`

`novak status` compares the registry in git against what oMLX and Open
WebUI actually hold, and catches the failure that actually happens: someone
edits the live copy instead of the source, and it silently stops matching.
Consigliere applies the identical discipline to a fleet of machines instead of
one app's config:

- **Declare** in git (Ansible roles, Terraform, stack definitions).
- **Apply** via a dumb, idempotent pusher — `ansible-pull`, Arcane's sync,
  Terraform.
- **Check for drift** separately and continuously — this is the piece that
  makes the rest trustworthy instead of "ran once, hope it held."

Every module below is either a *declare-and-apply* half or a *drift-check*
half of this same loop. Naming a future `consigliere drift`/`consigliere status`
surface — the console view that says "here's everywhere reality has
diverged from git" across *all* modules, not just OS packages — is the
throughline that ties them into one project rather than a pile of
unrelated integrations.

## Modules

### Declared config — `hosts/` (Ansible + `ansible-pull`)
OS baseline, Tailscale, Docker engine. See [README.md](README.md).

### Provisioning — Terraform (not yet built)
Stands servers up, doesn't just configure ones that exist. Blocked on
settling the substrate (hypervisor/cloud/bare-metal — currently a mix).

### Containers — `stacks/` (Arcane)
Adopted, not built — Arcane already does compose/swarm GitOps sync well.

### Out-of-band hardware — flashctrl-sdk (sibling project, no code yet)
IP KVM, DRAC, IPMI, AMT, and plain SSH are four-plus different protocols
for the same two things: "show me the console" and "power/reset this."
[`flashCtrl`](https://github.com/tmeuze/flashCtrl) is meant to be the
single abstraction over that, so Consigliere's console consumes one SDK for
hardware actions instead of hand-rolling a protocol client per vendor.
Nothing exists there yet (empty repo, no commits) — the console's KVM
widget is a static link today and becomes a real action once flashctrl-sdk
has something to call.

### Update intelligence (new — not yet built)
Applying updates (already covered: `unattended-upgrades` in `baseline`,
Watchtower/Shepherd for containers) isn't the same as *knowing what
changed*. This module is reporting, not another updater:
- **OS packages**: [`apt-listchanges`](https://packages.debian.org/apt-listchanges)
  — mature, Debian-native, surfaces each package's actual changelog on
  upgrade. Adopt, don't rebuild.
- **Container images**: [Diun](https://crazymax.dev/diun/) or
  [Renovate](https://docs.renovatebot.com/) for tag/digest diffs with
  links to release notes.
- **Breaking-change flagging**: a real heuristic Consigliere can own — semver
  major-bump detection across both of the above, surfaced in the console
  as "these updates likely need a look before they land," rather than
  trying to parse changelog prose for risk.

### Security posture / malware detection — Wazuh
The `security_posture` role now enrolls a **Wazuh agent** rather than
running Lynis + maldet — fleet-wide file-integrity monitoring,
rootkit/malware detection, and log analysis with a real single-pane
dashboard, instead of Consigliere hand-rolling posture reporting on top of two
separate CLI tools. Same "adopt, don't reinvent" call as Arcane for
containers. The manager/indexer/dashboard stack lives in `stacks/wazuh/`
(vendored as a git submodule, see its README); `wazuh_host` (a new,
manager-only role) handles the one host-level prerequisite (OpenSearch's
`vm.max_map_count` sysctl). Scaffolded, not yet run against a live host.

### Fleet console — `console/` (Next.js)
Ties the modules together: OIDC via Pocket ID, per-machine metadata from
Outline, links/actions per host (KVM, SSH, dashboards), and — as the other
modules land — the place `consigliere drift` gets surfaced as one view instead
of five separate tools' separate dashboards. See
[console/README.md](console/README.md).

## What sets it apart from adopting something off the shelf

Every module above was picked *after* asking "does a robust existing tool
already do this" — most of them are adopted tools (Arcane, Wazuh, and
eventually apt-listchanges/Diun), not reinventions. What's actually
custom is small and deliberate:

- **Not a bookmark dashboard** (Homepage/Homarr): the console drives real
  actions — hardware control via flashctrl-sdk, config enforcement via
  Ansible/Terraform — not just curated links. (Homepage is still fine to
  keep running separately for general household links; Consigliere isn't trying
  to replace that use case.)
- **Not a second inventory database** (NetBox): metadata lives in Outline,
  which was already in daily use, via a documented per-machine convention
  — one source of truth instead of two.
- **Not a general enterprise platform** (Foreman/Fleet): scoped tightly to
  this actual stack — Tailscale-first, Ansible/Terraform, Arcane, Pocket
  ID — rather than a platform with its own opinions to work around.
- **Shares its philosophy with `novak` on purpose.** The declare/apply/
  drift-check discipline isn't a coincidence between the two projects —
  it's the same lesson (decision 18: "the drift check is the more valuable
  half") applied to a second domain, hardware fleets instead of one app.
- **Deliberately industrial, unlike `novak-konzol`.** Novak's console is
  built to look like "a kitchen appliance you happen to trust" — warm,
  calm, non-industrial, on purpose, because it holds things told to it in
  confidence. Consigliere's console is the opposite on purpose: it *is*
  infrastructure control, so it should look like one — legible status,
  clear risk levels, no pretending otherwise.

## Explicitly out of scope for now: Android TV / device MDM

Raised as a future need (wiping personal data on checkout) but deliberately
not folded into any module above. It's a different protocol (Android
Enterprise / Android Management API, not SSH/IPMI/KVM) and a different
trust model. If it happens, it's its own integration hanging off the same
console — not evidence that Consigliere needs to become a universal device
manager.

## Open threads (tracked so they don't get re-derived)

- Naming — not landed on one yet.
- Terraform's provisioning substrate — hypervisor/cloud/bare-metal mix,
  unresolved.
- flashctrl-sdk has no code yet — the console's hardware actions are
  aspirational until it does.
- Outline vs. WikiJS — under consideration, doesn't block anything (the
  provider abstraction isolates it).
- Where secrets live (Vault vs. external store) and where git is hosted
  (Gitea vs. GitHub) — both still open, see README.md.
- Wazuh's default credentials need rotating before `stacks/wazuh/` touches
  anything but localhost — see its README's procedure.
- Update intelligence module (apt-listchanges, Diun/Renovate, breaking-
  change flagging) is named but not yet built.
