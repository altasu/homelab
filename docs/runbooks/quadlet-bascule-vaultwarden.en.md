# Runbook — Quadlet Cutover: Vaultwarden (first migration of an existing service)

Follows the pilot model ([quadlet-pilote-actual-budget.md](quadlet-pilote-actual-budget.md)) with the specificities of a service **with existing data**.

## Executed Prerequisites (in order, blocking)

1. **Fresh backup verified**: `backup.sh` + `gunzip -t` on the PostgreSQL dump.
2. **Version control before pinning**: `podman exec vaultwarden /vaultwarden --version` on the compose container (`latest` tag) — the version pinned in the unit must be **equal to or greater** than the running version (schema migrations are not reversible). Here: 1.37.0 running → 1.37.1 pinned = upgrade, OK.
3. **Per-service env**: `apps/vaultwarden.env` created from the template (final variables, `DATABASE_URL` assembled), `chmod 600`.

## Cutover

```bash
cp apps/quadlet/vaultwarden.{container,volume} ~/.config/containers/systemd/
/usr/libexec/podman/quadlet -dryrun -user     # verify generation BEFORE acting
systemctl --user daemon-reload
podman stop vaultwarden && podman rm vaultwarden    # start of downtime
systemctl --user start vaultwarden                  # end of downtime (~20 s)
journalctl --user -u vaultwarden -n 30 --no-pager   # startup banner + version
```

Verifications: web connection via the tunnel, opening + modifying an entry (DB write test), desktop and mobile synchronization.

## Rollback (documented, not needed here)

```bash
systemctl --user stop vaultwarden
rm ~/.config/containers/systemd/vaultwarden.{container,volume}
systemctl --user daemon-reload
podman-compose -f ~/homelab/apps/compose.yml up -d
```
Note: compose would relaunch the version pinned in `apps/compose.yml` — if more recent schema migrations have already run, never roll back to a previous version.

## Post-cutover observation: ADMIN_TOKEN detected in "plain text"

The startup log reported: `[NOTICE] You are using a plain text ADMIN_TOKEN which is insecure`.

**Root cause**: the token was indeed in Argon2 PHC format, but the value had been copied from the compose `.env` **with its compose escaping** (`$$` for a literal `$`) and quotes. However, `podman --env-file` reads values **literally**: the `$$` and quotes became part of the token, which therefore no longer started with `$argon2id$` — hence the "plain text" detection.

**Fix**: removal of quotes and doubled `$` in `apps/vaultwarden.env` (no regeneration necessary — the underlying secret was never exposed, no rotation required), then `systemctl --user restart vaultwarden`. NOTICE disappeared from the log (verified on 2026-08-03).

**Rule to remember for any compose → Quadlet port**: per-service env files contain final values *without* quotes and *without* `$$` escaping — the exact opposite of compose conventions.

**Tooling**: this check is now automated by [`scripts/check-env.sh`](https://gitlab.com/altasu/homelab/-/blob/main/scripts/check-env.sh) (quotes, `$$`, placeholders `${...}`, example values, permissions, known formats — without ever displaying the values). To be executed on each env file **before any cutover**.

## Lessons Learned

- Quadlet's `EnvironmentFile=` is passed to `podman run --env-file`: values read **literally** (no `${...}` interpolation, no `$$` escaping, quotes included in the value if present). Per-service env files must contain final values, without quotes.
- The generator adds `Requires=/After=` to the network and volume on its own: nothing to write by hand.
- `podman volume create --ignore` on an existing `VolumeName=` reuses data without touching it — verified (RSA keys and sessions preserved, no forced reconnection).
