# Runbook — Quadlet Cutover: Infra Tier (Cloudflare Tunnel + Twingate)

Last cutover of the migration (Step 5). These two services constitute **the lifeline of remote access**: stopping them cuts off all access from outside the local network.

## Absolute Rule

Cutover only during a window with **local physical access** to the server (or at least, on the LAN). If a tunnel fails to come back up, the fix can only be done locally.

## Principle: one tunnel at a time

Twingate first, full validation, **then** Cloudflare. Never both simultaneously: as long as one of the two access paths works, the server remains reachable remotely in case of a problem on the other.

## Prerequisites (blocking)

1. Fresh backup verified (`scripts/backup.sh` + `gunzip -t`).
2. `infra/cloudflared.env` and `infra/twingate.env` created from templates, `chmod 600`, validated by `scripts/check-env.sh`.
   - Point of attention: the Cloudflare tunnel variable now bears its **final name** (`TUNNEL_TOKEN`); compose performed this renaming on the fly, the Quadlet `EnvironmentFile=` does not.
3. Units copied + `quadlet -dryrun -user` without error + `daemon-reload`.

## Twingate Cutover

```bash
podman stop twingate-connector && podman rm twingate-connector
systemctl --user start twingate-connector
podman inspect twingate-connector --format '{{.NetworkSettings.Networks.homelab_net.IPAddress}}'
```

The **static IP must be identical** to the one in the compose configuration (`IP=` in the unit): Twingate resources target this address, a change would break access.

Validation: from a device on **cellular data** (not local Wi-Fi — otherwise the test does not truly traverse the tunnel), connect via the Twingate client and reach an internal resource.

## Cloudflare Tunnel Cutover

Only after Twingate validation.

```bash
podman stop cloudflare-tunnel && podman rm cloudflare-tunnel
systemctl --user start cloudflared
journalctl --user -u cloudflared -n 15 --no-pager   # "Registered tunnel connection"
```

Validation: from a device on cellular data, HTTPS access to published services (password manager, budget) — connection and synchronization.

## Rollback (identical for both)

```bash
systemctl --user stop <service>
rm ~/.config/containers/systemd/<service>.container
systemctl --user daemon-reload
podman-compose -f ~/homelab/infra/compose.yml up -d
```

## Fix applied concurrently: PostgreSQL healthcheck

The healthcheck from Step 4 was generating a benign FATAL on each probe. Two successive causes, fixed one after the other:

1. `pg_isready -q` without `-U` → probe executed as root in the container → `FATAL: role "root" does not exist`.
   Fix: `-U $$POSTGRES_USER` (the systemd escaping `$$` produces a `$` at runtime, resolved from the `EnvironmentFile`).
2. With `-U` but without `-d`, `pg_isready` targets a database **homonymous to the user** (little-known default behavior) → `FATAL: database "<user>" does not exist`.
   Final fix: `-U $$POSTGRES_USER -d $$POSTGRES_DB`.

Result: zero FATALs over an observation window, and the probe now checks something more useful — not "the server answers" but "the server answers **and** the application database is reachable".

## Lessons Learned

- Migrate remote access components **one by one**, never in a batch: redundancy of access paths is the safety net.
- Always test from an outside network (cellular data): a test from the LAN does not prove that the tunnel works.
- Variable renames that compose performed implicitly must be made explicit in the per-service env files.
- Check hardcoded infrastructure values (static IP) **after** cutover, not just in the unit file.
