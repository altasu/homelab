# Homelab Architecture — Overview

Current production stack: rootless Podman, 3 tiers (`infra/` → `data/` → `apps/`), shared network `homelab_net`, Zero Trust posture (no inbound ports, outbound tunnels only).

```mermaid
flowchart TB
    user(["User"])
    cf["Cloudflare<br>(CDN + Zero Trust)"]
    tg["Twingate<br>(Zero Trust Network)"]

    user -->|"HTTPS"| cf
    user -->|"VPN Zero Trust<br>(Cockpit, SSH)"| tg

    subgraph server["Homelab Server — Rootless Podman"]
        subgraph infra["Stage 1 : Core Infra (infra/) — NEVER STOP"]
            cloudflared["cloudflared"]
            twingate["twingate-connector"]
        end
        subgraph apps["Stage 3 : Apps (apps/)"]
            vw["Vaultwarden"]
            ab["Actual Budget (planned)"]
        end
        subgraph data["Stage 2 : Data (data/) — MOST CRITICAL"]
            pg[("PostgreSQL")]
        end
        net{{"Shared Network<br>homelab_net"}}
    end

    cloudflared -.->|"Outbound tunnel"| cf
    twingate -.->|"Outbound tunnel"| tg

    cloudflared --- net
    twingate --- net
    vw --- net
    ab --- net
    pg --- net

    cloudflared -.->|"http://vaultwarden:80"| vw
    vw -.->|"postgres-db:5432"| pg
```

## Principles

- **Zero inbound ports**: all traffic goes through encrypted outbound tunnels (Cloudflare Tunnel, Twingate).
- **Rootless Podman**: no root privileges for containers.
- **Isolated secrets**: each tier has its own `.env` (never versioned).
- **Pinned versions**: images are frozen in the orchestration files; specific versions are not exposed in public diagrams.
- **Mandatory deployment order**: `infra` → `data` → `apps`.

> **Migration in progress**: the `podman-compose` orchestration is evolving towards Quadlet (user systemd units) — see [quadlet-migration-plan.md](quadlet-migration-plan.md).
