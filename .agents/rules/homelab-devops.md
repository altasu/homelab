---
activation: always_on
---

# Homelab Infrastructure & GitOps Operational Rules

## 1. ENVIRONMENT & CONTAINER RUNTIME
- **System:** Linux server (x86_64), kernel networking (IP forwarding, firewalld masquerading). The exact distribution is deliberately not documented in versioned files (anti-fingerprinting rule, see section 5).
- **Container Runtime:** Rootless Podman & Podman Compose (User: `homelab` with `loginctl enable-linger`).
- **Orchestration Rule:** NEVER execute container orchestration changes without checking existing rootless systemd/Quadlet units.

## 2. STORAGE & PARTITIONS
- **OS / Active Containers:** internal SSD (XFS on LVM root).
- **Backup Vault:** dedicated external HDD (XFS), mounted via `/etc/fstab` — see `data/.env` (`BACKUP_DIR`) for the exact mount path.
- **Safety Constraint:** NEVER execute commands that modify disk partitions, LVM volumes, or unmount the backup vault silently.

## 3. CORE SERVICES & ARCHITECTURE
- **Active Stack:** Vaultwarden, PostgreSQL (`vwarden_db`, superuser defined in `data/.env` → `POSTGRES_USER`), Cloudflare Tunnel, Twingate, Actual Budget (planned).
- **Orchestration Migration (in progress):** `podman-compose` → Quadlet (rootless systemd user units). Roadmap and current state: `docs/quadlet-migration-plan.md`. Compose rules below remain authoritative for any tier not yet migrated; Quadlet units live in the repo (e.g. `apps/quadlet/`) and are deployed to `~/.config/containers/systemd/`. No Kubernetes on this server.
- **Quadlet Rules:** pinned image tags only (never `latest`), secrets via `EnvironmentFile=` pointing to untracked `.env` files, `homelab_net` shared network preserved, systemd dependencies (`After=`/`Requires=`) must reflect the tier order data → apps.
- **Volume Naming Standard:** `<tier>_<service>_data` (e.g. `apps_vaultwarden_data`, `apps_actual_budget_data`) — matches the prefix podman-compose generates, and Quadlet units must set it explicitly via `VolumeName=`. Every backup script reference (archive step AND its existence guard) must use this exact name; a mismatched name silently produces an empty backup (incident of 2026-08-03).

## 5. SECRETS & PII HYGIENE
- **Rule:** No real usernames, hostnames, exact OS/distribution names, or other personally/security-identifying values may be hardcoded in any tracked file (rules, docs, diagrams). Reference the `.env` variable name instead (e.g. `POSTGRES_USER`), never the literal value.
- **Rationale:** A leaked username reduces attacker reconnaissance effort even without a password; the same "no fingerprinting info in versioned files" logic already applied to container image versions (see `homelab-architecture.md` → Audit de Sécurité) extends to credentials and personal identifiers.
- **Local-only exception:** If an AI session genuinely needs the real value (e.g. for a specific debugging task), keep it in an untracked, gitignored local note — never in a file meant to be committed.
- **Database Safety:** Always verify backup archive integrity before performing any database restore or schema migration operations.

## 4. DOCUMENTATION STANDARD
- **Runbooks:** Keep structured technical runbooks (`.md`) with explicit disaster recovery and restore verification steps.