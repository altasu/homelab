# Runbook — Backups: integrity check and test restoration

## Data distribution (Vaultwarden with PostgreSQL backend)

| Data | Location | Criticality |
|---|---|---|
| Vaults, users, organizations | PostgreSQL (`vwarden_db`) | Vital — covered by `pg_dumpall` |
| Entry attachments | Volume `/data/attachments/` | **Irreplaceable** — outside DB |
| Bitwarden Send files | Volume `/data/sends/` | Irreplaceable — outside DB |
| RSA keys (session token signature) | Volume `/data/rsa_key*` | Loss = disconnection of all devices |
| Favicon cache | Volume `/data/icon_cache/` | Disposable |

Conclusion: volume backup remains necessary even with a PostgreSQL backend.

## Integrity check — three levels

**Level 1 — Compression integrity** (silence = success):
```bash
gunzip -t <dump>.sql.gz
tar -tzf <archive>.tar.gz > /dev/null && echo OK
```

**Level 2 — Content completeness**:
```bash
# The dump must end with the pg_dumpall end marker:
zcat <dump>.sql.gz | tail -3      # expected: "-- PostgreSQL database cluster dump complete"
# The archive must contain critical files:
tar -tzf <archive>.tar.gz | grep rsa_key
```

**Level 3 — Test restoration (gold standard)** — proves that the backup is *restorable*, not just readable:
```bash
# Disposable PostgreSQL instance, isolated (NOT on homelab_net)
# Use exactly the same image/version as data/compose.yml (source of truth)
podman run --rm -d --name pg-restore-test -e POSTGRES_PASSWORD=testonly <PostgreSQL image from data/compose.yml>
sleep 5
zcat <dump>.sql.gz | podman exec -i pg-restore-test psql -U postgres
podman exec pg-restore-test psql -U postgres -l                                   # vwarden_db present?
podman exec pg-restore-test psql -U postgres -d vwarden_db -c "SELECT count(*) FROM users;"
podman stop pg-restore-test
```
"role already exists" errors are expected and benign when restoring to a partially blank instance.
Verification successful on 2026-08-03: database recreated, tables loaded, user count correct.

## 2026-08-03 Incident — inoperative backups after reinstallation

**Symptom**: no backup present on the external drive since the server reinstallation (July 2026).

**Cumulative causes**:
1. `BACKUP_DIR` in `data/.env` pointed to a path on the development machine (file copied as is) — path non-existent on the server.
2. The external drive mount point belonged to `root`: the rootless user could not write to it.
3. `scripts/backup.sh` referenced the `vaultwarden_data` volume without the prefix added by podman-compose (`apps_vaultwarden_data`): Podman silently created an empty volume and produced an 87-byte archive containing no data.
4. No scheduling (neither cron nor systemd timer) had been set up.

**Fixes applied**:
1. `BACKUP_DIR` fixed to point to the external drive mount point.
2. `chown` of the mount point to the rootless user.
3. Prefixed volume fixed in `backup.sh` + removal of the parasitic empty volume (`podman volume rm`).
4. Scheduling via user systemd timer (`scripts/systemd/backup.{service,timer}`), daily at 03:30, `Persistent=true` (catch-up if server is off). Verification: `systemctl --user list-timers backup.timer` and `journalctl --user -u backup.service`.

**Lessons Learned**:
- A backup not tested in restoration is not a backup (level 3 verification now in this runbook).
- `.env` files copied between machines must be reviewed value by value.
- Any critical task must be scheduled and logged (systemd timer + journalctl), never left to manual execution.
- podman-compose volume names are prefixed: always check with `podman volume ls` before any script referencing them.

## 2026-08-04 Incident — success reported when backup was empty

**Symptom**: the script displays `Error: no container with name or ID "postgres-db" found` **then** `✅ PostgreSQL backup successful`. The produced archive is 20 bytes (gzip header only). The `gunzip -t` check declares it valid: the level 1 verification therefore returns a false positive.

**Causes**:
1. `command | gzip > file`: `$?` reflects only the **last** link in the pipeline (`gzip`), which succeeds on empty input. The `podman exec` failure was therefore invisible. Same family of defect as the 2026-08-03 incident (misnamed volume): *a silent failure declared as success*.
2. Triggering context: the containers had been stopped by `systemctl --user disable --now podman-restart.service`. The `--now` option triggers the `ExecStop` of this unit, which executes a `podman stop`. **To remove a unit from startup without touching running services, use `disable` alone.**

**Fixes applied to `scripts/backup.sh`**:
- `set -o pipefail`: pipeline failures actually bubble up.
- `podman container exists` safeguard before dumping.
- Archive non-emptiness check; an empty archive is deleted and counted as a failure.
- Non-zero overall exit code in case of failure → `backup.service` appears as `failed` in systemd instead of hiding the problem.
- **Conditional rotation**: old backups are no longer purged when the day's backup failed (otherwise a prolonged silent failure would end up deleting the last healthy archives).

**Cross-cutting lesson**: in any backup script, failure must be **noisy**. Check not only that the command finishes, but that the result is *plausible* (size, end marker).

## Future Improvements Kept

- [ ] Dedicated non-superuser PostgreSQL role per application (OWASP least privilege) — planned during Data tier migration (see Quadlet plan, Step 4).
- [x] Extend `backup.sh` to future service volumes — done for Actual Budget (SQLite data, the application does not support PostgreSQL), with `podman volume exists` safeguard. Naming standard adopted: `<tier>_<service>_data`, the safeguard and the archive must reference exactly the same name.
- [ ] Alert on `backup.service` failure (`OnFailure=` to a notification unit) — to be studied with observability (Step 7).
