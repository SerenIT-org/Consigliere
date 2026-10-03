# traefik_server

Prepares a host to run the Traefik edge stack from the separate geotraefik repo:
renders Traefik's *dynamic* configuration (a shared base, this host's own routes,
and the certificates available on the host) and creates the shared proxy network.
It does not deploy Traefik itself, and the host holds no DNS API key.

## How a node knows which routes are its own

By ordinary Ansible variable scope. Define any variable named
`traefik_server_routes` or `traefik_server_routes_<anything>`, and put it where
it should apply:

- `config/vars/host/web-host.yml`: only on that host.
- `config/vars/group/arkeep_server.yml`: wherever that service runs, so the route
  follows the service.
- `config/vars/group/all.yml`: on every proxy.

The role gathers every such variable the host can see (its groups plus its own
host file) and renders them. Unlike normal Ansible variables, layers **add up**
instead of overriding each other, because each layer uses a different name.

    traefik_server_routes_vault:
      - name: vaultwarden
        host: vault.example.com
        backend: http://vaultwarden:80      # container on the shared network

## What geotraefik must do

Mount the rendered config and the certificates, and drop the ACME resolver
(certificates are files now):

    traefik:
      volumes:
        - /opt/traefik/dynamic:/dynamic:ro
        - /opt/common/certs:/certs:ro
      networks: [edge, proxynet]         # your shared network, external

and in `traefik.yml`, a file provider on `/dynamic` with `watch: true`, and no
`certificatesResolvers`. Remove the `BUNNY_API_KEY` environment and the static
`routes.yml` config from the compose file.

## Unverified

That Traefik reloads when a referenced certificate file changes is handled by
touching `20-tls.yml` after renewal (the fetch script does this); I haven't
confirmed it against a running Traefik.
