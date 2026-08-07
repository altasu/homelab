# Runbook — Quadlet Cutover: PostgreSQL + least privilege (Step 4)

Cutover of the Data tier in **two distinct phases** — only one thing changes at a time:
- **Phase A**: orchestrator change only (same pinned image, same credentials).
- **Phase B**: transition of the application to the non-superuser role (once A is validated).

## Phase A — Orchestrator Cutover

Blocking prerequisites executed: fresh verified backup (`gunzip -t`), `data/postgres.env` created (**raw** values, without percent-encoding — which only applies to URLs) and validated by `scripts/check-env.sh`.

```bash
cp data/quadlet/postgres.{container,volume} ~/.config/containers/systemd/
cp apps/quadlet/vaultwarden.container ~/.config/containers/systemd/   # Requires=/After=postgres.service dependency
/usr/libexec/podman/quadlet -dryrun -user
systemctl --user daemon-reload
systemctl --user stop vaultwarden            # the dependent stops BEFORE the database
podman stop postgres-db && podman rm postgres-db
podman pod rm pod_data                       # residual compose pod, emptied by container removal
systemctl --user start postgres              # waits for healthcheck (Notify=healthy)
systemctl --user start vaultwarden
```

**Proofs of success**: PostgreSQL log "database directory appears to contain a database; **Skipping initialization**" (existing volume reused, data intact); container `Up (healthy)`; application connections visible in the postgres process list.

### Observation: benign `FATAL: role "root" does not exist` noise

The `pg_isready -q` healthcheck runs as root in the container and, without `-U`, attempts the "root" role. `pg_isready` nevertheless considers the server reachable (that's its contract: reachability, not authentication) — the healthcheck therefore works, but each probe writes a benign FATAL line in the log. **Fix planned in Step 5** (next natural restart): pass `-U` via systemd escaping `$$POSTGRES_USER`, to be validated in dry-run.

## Phase B — Least privilege application role (OWASP)

Motivation: the application was connecting with the PostgreSQL superuser. Compromise of the app = full control of the instance (including all future databases). The dedicated role limits the blast radius to `vwarden_db`.

```sql
CREATE ROLE vaultwarden_app LOGIN PASSWORD '<strong password>';
ALTER DATABASE vwarden_db OWNER TO vaultwarden_app;
\c vwarden_db
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT tablename FROM pg_tables WHERE schemaname = 'public'
  LOOP EXECUTE format('ALTER TABLE public.%I OWNER TO vaultwarden_app', r.tablename); END LOOP;
  FOR r IN SELECT sequencename FROM pg_sequences WHERE schemaname = 'public'
  LOOP EXECUTE format('ALTER SEQUENCE public.%I OWNER TO vaultwarden_app', r.sequencename); END LOOP;
END $$;
```

**Why transfer ownership (and not just GRANTs)**: schema migrations of future Vaultwarden versions execute `ALTER TABLE`, an operation reserved for the owner. DML GRANTs alone would break the first upgrade.

Verifications: `\dt` → Owner = `vaultwarden_app` on all tables; `\du` → the role has **no** attributes (neither Superuser, nor Create DB, nor Create role).

Then on the application side: update of the user/password pair in the `DATABASE_URL` of `apps/vaultwarden.env`, validation `check-env.sh`, `systemctl --user restart vaultwarden`, write test via a client.

**Machine-to-machine password**: long hexadecimal (`openssl rand -hex 24`, ~192 bits) — never typed by a human, character variety adds nothing; alphanumeric avoids any percent-encoding traps in the URL. If a password with special characters is chosen regardless: **raw** value in `CREATE ROLE`, **percent-encoded** value in the `DATABASE_URL` (encode via `urllib.parse.quote`, never manually).

**Rollback B**: revert to the old pair in the `DATABASE_URL` + restart (the superuser is not deleted). `scripts/backup.sh` continues to use the superuser via `data/.env` — unchanged.

## Template for future applications

Each application sharing the PostgreSQL instance (Keycloak, BookStack...) receives: its own database + its own non-superuser owner role + its own password. The superuser remains reserved for administration and backups.

## Lessons Learned

- `Notify=healthy` + `HealthCmd` turns `After=postgres.service` into waiting for a **truly ready database** — Quadlet equivalent of a Kubernetes readiness probe.
- Stop order = reverse of dependencies: the dependent (Vaultwarden) stops before the database.
- Never paste terminal output containing a secret into a third-party channel; in case of exposure, **immediate rotation** (`ALTER ROLE ... PASSWORD`) — the ease of rotation is precisely a benefit of the dedicated application role.
