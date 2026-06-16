---
trigger: always_on
---

# Homelab Zero Trust Architecture

## Infrastructure Constraints
- The project uses Podman (rootless/daemonless), NOT standard Docker. Images must use `docker.io/` prefix to prevent short-name resolution errors.
- The project is strictly divided into three tiers: `infra`, `data`, and `apps`.
- Containers MUST communicate through the external network named `homelab_net`.
- Network Mode Host (`network_mode: host`) is strictly prohibited to maintain isolation.

## Data Persistence
- Databases and applications MUST use Podman Named Volumes for maximum I/O performance and to avoid rootless SELinux/UID permission issues on host directories.
- Backups of these named volumes MUST be performed via automated scripts (e.g., `scripts/backup.sh`) that generate logical dumps (like `.sql.gz`) and store them on an external drive. Host bind mounts for live databases are strictly prohibited.

## Secrets Management
- No secrets or tokens (e.g., Twingate, Cloudflare, PostgreSQL) shall be hardcoded. They must be stored in `.env` files within their respective tier folders.