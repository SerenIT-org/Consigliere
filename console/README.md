# Kuzka console

The bespoke fleet webUI — a tile grid, one tile per machine, with
per-machine widgets (KVM link, SSH launch, dashboard links, live
reachability). Login is OIDC via Pocket ID. Deployed as its own stack
(`stacks/console/docker-compose.yml`), managed by Arcane like everything
else in `stacks/`.

## How it gets its data

Machine data comes from a pluggable provider (`src/lib/providers/`) —
today `OutlineProvider` is the only implementation, reading one Outline
document per machine. Swapping in a different backend later (NetBox, flat
YAML, whatever) means implementing `MachineProvider` and switching
`MACHINE_PROVIDER` — the UI and widgets don't change.

### Per-machine Outline doc convention

Each machine's doc needs a plain markdown table near the top — everything
else in the doc is free-form notes and is ignored:

```markdown
| Field      | Value                                       |
|------------|----------------------------------------------|
| Hostname   | server01                                      |
| Tailscale  | 100.x.x.x, tag:server, tag:swarm-manager      |
| KVM        | https://pikvm.example.ts.net                  |
| Dashboards | Grafana\|https://grafana..., Uptime\|https://... |
| Role       | swarm-manager                                 |
```

- `Tailscale`: comma-separated addresses and `tag:` entries, mixed freely.
- `Dashboards`: comma-separated `Label|https://url` pairs; the label can be
  omitted (falls back to the URL's hostname).
- Any other field in the table just passes through as extra metadata
  (`machine.raw`) — not rendered by default, but available if a future
  widget wants it.

### Overview sync (solves the copy-paste-between-docs problem)

Rather than hand-maintaining a separate "all machines" table in Outline,
point `OUTLINE_OVERVIEW_DOC_ID` at a doc containing:

```
<!-- kuzka:overview:start -->
<!-- kuzka:overview:end -->
```

anywhere in it. Hitting "Sync overview" in the console (or `POST
/api/sync`) regenerates the table between those markers from every machine
doc's own fields — the per-machine doc stays the only thing you actually
edit by hand. Everything outside the markers in that doc is left alone.

## Setup

1. Copy `.env.example` to `.env.local` (local dev) or `stacks/console/.env`
   (deployed), fill in:
   - Pocket ID: register Kuzka as an OIDC client, redirect URI
     `${NEXTAUTH_URL}/api/auth/callback/pocket-id`.
   - Outline: an API token (Settings → API), the collection id holding the
     per-machine docs, and optionally an overview doc id (see above).
   - Tailscale API key is optional — omitting it just means tiles render
     without an online/offline dot.
2. `npm install`
3. `npm run dev` (or `docker compose -f stacks/console/docker-compose.yml up --build`)

## Status

Scaffold stage — the Outline API field names in `src/lib/outline/client.ts`
are written from general knowledge of Outline's API shape and are flagged
inline as unverified against a live instance. Everything else (parsing,
widgets, auth wiring, overview sync) is implemented, not stubbed, but
hasn't been run against real Outline/Pocket ID/Tailscale accounts yet.
