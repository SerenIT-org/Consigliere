# fleet-config (example)

This directory is a **template**, not something this framework reads
directly. Copy it into your own **separate, private** git repository —
that private repo is what actually drives your fleet. This framework repo
stays public and generic: roles, the playbook, and a tag-based Tailscale
inventory plugin config with no site-specific values in it at all.

## Why a separate repo, not just a gitignored folder here

A gitignored folder would still require editing files *inside this
framework's own checkout*, which makes it awkward to pull upstream
framework updates without your real config getting in the way, and makes
it easy to accidentally commit something real into the public repo by
habit. A separate repo keeps the two cleanly apart: this one is the tool,
yours is the config.

## Setting it up

```bash
# somewhere private — a new repo, not a fork of this one
git init my-fleet-config
cp -r fleet-config.example/* my-fleet-config/
cd my-fleet-config
# fill in group_vars/, add host_vars/ as needed, create + encrypt vault.yml
git add -A && git commit -m "Initial fleet config"
git remote add origin git@github.com:you/my-fleet-config.git   # make this PRIVATE
git push -u origin main
```

Then point every host at both repos (see `hosts/bootstrap/bootstrap.sh`):

```bash
FRAMEWORK_REPO_URL=https://github.com/<you>/<this-framework-repo>.git \
FLEET_CONFIG_REPO_URL=git@github.com:you/my-fleet-config.git \
./bootstrap.sh
```

`FLEET_CONFIG_REPO_URL` needs its own git access on every host (an SSH
deploy key with read-only access is the usual choice) — provisioning that
key is a one-time, out-of-band step (cloud-init, or manual); it isn't
handled by this framework.

## Shape

```
group_vars/
  all.yml                # defaults applied to every host
  all/
    vault.yml            # ansible-vault encrypted -- never commit plaintext
  arkeep_server.yml       # real values for tag:arkeep-server
  arkeep_agent.yml        # real values for tag:arkeep-agent
  arcane_manager.yml      # real values for tag:arcane-manager
  arcane_agent.yml        # real values for tag:arcane-agent (except the token, see below)
host_vars/
  example-arcane-agent-host.yml   # per-host arcane_agent_token (minted from the manager UI, can't be shared)
```

See the files in this directory for a concrete starting point.
