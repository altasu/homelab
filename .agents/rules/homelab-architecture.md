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
- Database volumes (Stage 2) MUST be mapped to an external drive. The exact host path MUST be parameterized using an environment variable (e.g., `${POSTGRES_DATA_PATH}`) via the `.env` file, and MUST NOT be hardcoded.

## Secrets Management
- No secrets or tokens (e.g., Twingate, Cloudflare, PostgreSQL) shall be hardcoded. They must be stored in `.env` files within their respective tier folders.