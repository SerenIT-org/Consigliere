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
  unaffected by the cloud firewall.
- Tailscale admin: create tags `tag:server`, `tag:arkeep-server`,
  `tag:arcane-manager`, `tag:semaphore`; create an auth key (tagged
  `tag:server`) and an API key/OAuth client for the inventory.
- Private fleet-config repo created from `fleet-config.example/`, vault
  filled in and encrypted (arkeep_agent_secret, arkeep_secret_key,
  arcane_encryption_key, semaphore_admin_password,
  semaphore_access_key_encryption). Read-only deploy key added to it.
- A heartbeat check (healthchecks.io or Uptime Kuma push) for this host.

## 1. Bootstrap the host (Debian, as root)
Copy the deploy key and vault password to the host first (scp over
Tailscale or your provider console), then:

    FRAMEWORK_REPO_URL=https://github.com/almadon/consigliere.git \
    FLEET_CONFIG_REPO_URL=git@github.com:<you>/<fleet-config>.git \
    FLEET_CONFIG_DEPLOY_KEY_FILE=/root/deploy_key \
    VAULT_PASSWORD_FILE=/root/vault_pass \
    HEARTBEAT_URL=<your heartbeat url> \
    TAILSCALE_AUTHKEY=<auth key> TAILSCALE_API_KEY=<api key> \
    ./hosts/bootstrap/bootstrap.sh

(Fetch bootstrap.sh from the framework repo first; `shred` the key and
password copies afterwards.) The tailscale role reads TAILSCALE_AUTHKEY from
the environment on first run; the dynamic inventory needs TAILSCALE_API_KEY —
neither is persisted to /etc/fleet-reconcile.env yet, so scheduled runs will
lack them until that's wired up (known gap).

Tag the device in Tailscale (`tag:server`, `tag:arkeep-server`,
`tag:arcane-manager`, `tag:semaphore`) and re-run
`systemctl start fleet-reconcile.service`; watch `journalctl -u
fleet-reconcile -f`. Expect the first failures here.

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
hosts/roles/arkeep_server/README.md and close the direct ports.

## 5. Then node 2
Tag `tag:server` + `tag:arkeep-agent`, bootstrap the same way. Add
`tag:wazuh-agent` / `tag:arcane-agent` only once a Wazuh manager exists /
you've minted the Arcane token.

## Not built yet
Adoption view in the console, the token broker, scheduled check-mode drift
runs in Semaphore (needs project setup in its UI), Wazuh server rollout.
