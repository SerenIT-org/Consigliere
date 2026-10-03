# server_certwarden

Deploys [Cert Warden](https://github.com/gregtwallace/certwarden), a central ACME
client, on ONE host. It obtains Let's Encrypt certificates (DNS-01, e.g. via
Bunny) and serves each certificate plus key to the hosts that need it
(`agent_certwarden`). That keeps your DNS API key on a single host.

**License:** Cert Warden permits only personal, private (non-commercial) use and
reserves all other rights. It is not open source; confirm it suits your use. The
proxy side of this framework doesn't depend on it: anything that writes
`<certs dir>/<name>/fullchain.pem` and `privkey.pem` works (see `agent_certwarden`).

## After the first deploy (done in Cert Warden's web UI, on the tailnet)

1. Open `https://<tailscale-ip>:4055` (self-signed at first) and **change the
   default admin credentials immediately**.
2. Add the ACME account, then your DNS provider (Bunny) under the DNS-01
   challenge providers. Credentials entered there live in the data volume.
3. Create a private key and a certificate for each name set (e.g. a wildcard),
   with an API key for each (a certificate API key and a private-key API key).
4. Put those two keys in a vault file of their own for that certificate:
   `scripts/vault.sh create cw.<name>` then `edit` (file `config/secrets/cw/<name>.yml`,
   vault id `cw.<name>`; see the template's `_template.yml.example`). Only hosts that
   list `<name>` in `agent_certwarden_certs` read it, and only they get its password.

(The UI steps are from my reading of the project; verify against its docs.)

## Operations

- Bound to the Tailscale IP only by default.
- Back up the `certwarden-data` volume (it holds the DNS credentials and every
  private key) with an encrypted policy.
- If it is down, existing certificates keep working until they expire; renewals
  and new issuance pause.
