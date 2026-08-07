# Runbook — Quadlet Pilot: Actual Budget deployment

First service deployed via Quadlet (Step 2 of the migration plan). This workflow is the **template** for subsequent cutovers (Vaultwarden, PostgreSQL, infra).

## Involved Files (IaC)

| File (repository) | Role |
|---|---|
| `apps/quadlet/actual-budget.container` | Container unit (pinned image, resource limits) |
| `apps/quadlet/actual-budget.volume` | Volume `apps_actual_budget_data` (standard `<tier>_<service>_data`) |
| `infra/quadlet/homelab.network` | Shared network (created with `--ignore`: existing is preserved) |

## Deployment Procedure (template)

```bash
git pull                                             # synchronize IaC
mkdir -p ~/.config/containers/systemd
cp <units> ~/.config/containers/systemd/
/usr/libexec/podman/quadlet -dryrun -user            # validation BEFORE activation
systemctl --user daemon-reload
systemctl --user start <service>
systemctl --user status <service> --no-pager         # expected: active (running)
podman ps                                            # container Up
```

Internal test without published port (Zero Trust: no direct access):
```bash
podman run --rm --network homelab_net docker.io/alpine:3.22 wget -qO- http://<container>:<port> | head -5
```

Then: Cloudflare Tunnel route (Public Hostname → `HTTP` / `<container>:<port>`), and backup verification (`scripts/backup.sh` → service section ✅).

## Rollback

```bash
systemctl --user stop <service>
rm ~/.config/containers/systemd/<service units>
systemctl --user daemon-reload
```
The named volume is **not** deleted by the rollback (data preserved).

## Useful Observations (dry-run of 2026-08-03)

- The Quadlet generator automatically adds dependencies: `Requires=/After=homelab-network.service` and `actual-budget-volume.service` — startup order is guaranteed without manual configuration.
- `podman volume create --ignore` / `podman network create --ignore`: existing objects are reused as is (cutover without risk to existing setup).
- The container is launched with `--replace --rm`: cleanly recreated at each startup, persistent state lives exclusively in the volume.
- `ExecStop` executes `podman rm -f` of the container: a `systemctl --user stop` cleans up completely (no orphan container).
- First synchronization of application migrations visible in `journalctl --user -u actual-budget` ("Migrations: DONE").

## Application Security (first access)

1. Set the **server password** on first web access (store it in Vaultwarden).
2. Enable **end-to-end encryption** (Settings → Encryption): budget files are encrypted at rest on the server side. The E2E key is distinct from the server password — losing it makes data unrecoverable, store it in Vaultwarden as well.
3. Verify synchronization from the desktop app and a mobile browser.
