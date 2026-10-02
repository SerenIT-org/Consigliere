# server_traefik

Prepares a host to run the Traefik edge stack from the separate
geotraefik repo: writes `/opt/traefik/.env`
(mode 0600) holding `BUNNY_API_KEY`, and creates the shared proxy network.
It does not deploy Traefik itself.

Point the stack at the file, in geotraefik's `compose.yaml`:

    services:
      traefik:
        env_file: [/opt/traefik/.env]

(an absolute path, resolved on the host). If Arcane's edge agent runs the
compose from inside its own container, that host path may not be visible to
it: not verified. In that case run `docker compose up -d` on the host.

The key itself lives in the fleet repo at
`config/vars/group/server_traefik/vault.yml`, encrypted with vault id
`server_traefik`, and only hosts in this group are given that password.
