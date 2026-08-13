# stacks/

Docker Compose / Swarm stack definitions live here, one directory per
service. This tree is owned by **Arcane**, not Ansible — Arcane watches it
directly and handles sync, drift detection, and redeploys for both
standalone and swarm targets.

The `hosts/docker` role only installs and configures the Docker engine
itself; it does not touch anything under here.

## Layout convention

```
stacks/
  <service-name>/
    docker-compose.yml
    .env.example        # document required vars; real .env stays untracked
```

Nothing scaffolded here yet — add a directory per service as they're
containerized.
