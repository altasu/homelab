# Homelab — Infrastructure as Code

## Context

This repository documents the real-world migration of a personal homelab: from a classic `podman-compose` orchestration to **Quadlet** units (Podman's native systemd integration), while maintaining a **rootless** and **Zero Trust** posture end-to-end (no inbound ports, all outbound traffic via Cloudflare Tunnel and Twingate).

## Approach

The migration followed a simple principle: **never a direct replacement**. Each service was migrated in parallel with the existing one, validated, and then switched over — with a fallback path (`rollback`) available at each step. The order followed the increasing impact radius: a risk-free greenfield pilot (a new service without existing data), then the applications, the database, and finally the network infrastructure — the lifeline for remote access, migrated last and only with local physical access.

The complete details of this roadmap are available in the [migration plan](quadlet-migration-plan.md).

## Real Incidents and Resolutions

An honestly documented infrastructure project includes its mistakes. Three distinct incidents share the same family of causes — a failure silently declared as a success — and their gradual discovery illustrates a diagnostic method rather than a simple list of fixes:

- **Backups inoperative since a reinstallation** (incorrect backup path, mount point permissions, incorrect volume naming, no scheduling) — discovered by an inventory audit even before starting the actual migration.
- **Empty application volume backed up as "successful"** — the naming prefix imposed by the previous orchestrator was not reflected in the backup script.
- **Shell pipeline masking a failure** — the return code of a pipeline reflecting only its last link, a failed command still produced an (empty) archive declared valid.

Each incident was fixed, tested (real restoration on a disposable instance), and then transformed into an automated safeguard rather than just a quick fix — see the [backups runbook](runbooks/sauvegardes-verification-restauration.md).

## Current State

Eight services run under Quadlet, rootless, with:

- automated daily backups, with noisy failures and tested restoration;
- Prometheus/Grafana monitoring covering the host, containers — and the backup itself;
- alerts routed to a dedicated notification channel;
- a least-privilege model for data access (dedicated application role, non-superuser);
- a validated full reboot test (automatic recovery in the right order upon boot).

## Runbooks

- [Backups: verification and restoration](runbooks/sauvegardes-verification-restauration.md)
- [Quadlet Pilot: Actual Budget](runbooks/quadlet-pilote-actual-budget.md)
- [Cutover: Vaultwarden](runbooks/quadlet-bascule-vaultwarden.md)
- [Cutover: PostgreSQL and least privilege](runbooks/quadlet-bascule-postgres.md)
- [Cutover: Network infrastructure](runbooks/quadlet-bascule-infra.md)
- [Observability](runbooks/observabilite.md)
