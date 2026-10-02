# Deploying the coordination server (node 1)

One host runs: Arkeep server, Arcane manager, Semaphore, the console, and
(from the separate geotraefik repo) Traefik. Nothing here has run on a real
host yet — expect to fix things. What *has* been tested: the console
(mock Outline, forged session; see commit 441d837), shell syntax, template
rendering, lint. **Not** tested: real Outline/Pocket ID/Tailscale, the
Docker image build, any role on a real host.

## 0. Before touching the host
- Cloud firewall: allow inbound 80/443 (Traefik) and nothing else public.
  **Docker-published ports bypass ufw**, so ufw alone will not protect
  Arkeep (9090/8080), Arcane (3552), Semaphore (3000). Tailscale traffic is
  unaffected by the cloud firewall. Where you can, bind to the Tailscale IP
  (`server_arkeep_bind_address`).
- Your private fleet repo, created from `consigliere-fleet-template` (private),
  with `config/inventory/groups.yml` mapping *your* Tailscale tags to the
  framework's group names, `config/vars/` filled in, and the vault created and
  encrypted. Run `scripts/preflight.sh --strict` in it: it must pass. The vault
  needs `agent_arkeep_secret`, `server_arkeep_secret_key`, `server_arcane_encryption_key`,
  `server_semaphore_admin_password`, `server_semaphore_access_key_encryption` for the roles
  this host runs.
- Tag the host in Tailscale with the tags your `groups.yml` maps to the roles it
  should run (e.g. the tag you mapped to `server_arkeep`). Hosts already on the
  tailnet need no auth key; a brand-new host needs one (put `tailscale_authkey`
  in the vault, or export `TAILSCALE_AUTHKEY` for the first run).
- A GitHub token that may manage the fleet repo's deploy keys (optional; it
  lets bootstrap register the host's key automatically, otherwise you'll paste
  the key it prints).
- In Pocket ID: two user groups (viewer, admin) with you in the admin one, and
  an OIDC client allowed the `groups` scope.
- A heartbeat check (healthchecks.io or Uptime Kuma push) for this host.

## 1. Bootstrap the host (Debian, as root)
Get `hosts/bootstrap/bootstrap.sh` onto the host (it's in the framework repo),
copy the vault password over (the one secret that can't be generated), then:

    FRAMEWORK_REPO_URL=https://github.com/almadon/consigliere.git \
    FLEET_CONFIG_REPO_URL=git@github.com:<you>/<fleet-repo>.git \
    FLEET_CONFIG_REGISTER_TOKEN=<token, optional> \
    VAULT_PASSWORD_FILE=/root/vault_pass \
    HEARTBEAT_URL=<your heartbeat url> \
    ./hosts/bootstrap/bootstrap.sh

The host generates its own read-only deploy key and has it registered (or
prints it for you to add and waits), then does the first reconcile and
installs the timer. `shred` the vault password copy afterwards. Watch
`journalctl -u fleet-reconcile -f`; expect the first failures here.

## 2. Verify each service (over Tailscale, not the public IP)
- Arcane   http://<tailscale-ip>:3552 — create the admin account.
- Arkeep   http://<tailscale-ip>:8080 — create the admin account; note the
  gRPC address <tailscale-ip>:9090 for agents.
- Semaphore http://<tailscale-ip>:3000 — log in with the vault admin password.
- Heartbeat check turns green after a successful reconcile.

## 3. Deploy the console (manual for now)
    cd /opt/fleet-reconcile/framework/stacks/console
    cp ../../console/.env.example .env      # fill in; git-ignored, survives reconciles
    echo CONSOLE_BIND=<tailscale-ip> >> .env
    # also set in .env: POCKET_ID_URL=<your Pocket ID base URL, i.e. the OIDC
    # issuer>, CONSOLE_VIEWER_GROUP=<viewer group>, CONSOLE_ADMIN_GROUP=<admin
    # group>. Unset groups = nobody can sign in (fail closed).
    docker compose up -d --build
In Pocket ID register an OIDC client with redirect URI
`<NEXTAUTH_URL>/api/auth/callback/pocket-id`. In Outline: create the
machines collection (one doc per machine, table convention in
console/README.md), an API token, and optionally the overview doc with its
markers. Then open the console and check, in order: login works → tiles
render → "Edit in Outline" links open the right doc → Sync overview works.
Likely failure points: Pocket ID claim names (flagged in auth.ts) and
Outline response shapes (flagged in outline/client.ts).

## 4. Traefik (geotraefik repo) — last
Only after 2–3 work. Then wire Arkeep/Arcane/console through it per
hosts/roles/server_arkeep/README.md and close the direct ports.

## 5. Then node 2
Tag it with the tags your `groups.yml` maps to `agent_arkeep` (and the
others it should run), bootstrap the same way. Leave the `agent_wazuh` and
`agent_arcane` tags off until a Wazuh manager exists / you've generated the
Arcane agent token.

## Not built yet
Adoption view in the console, the token broker, scheduled check-mode drift
runs in Semaphore (needs project setup in its UI), Wazuh server rollout.
