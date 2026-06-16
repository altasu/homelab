# Homelab Infrastructure (IaC)

🇫🇷 **Français** | 🇺🇸 **English**

---

## 🇫🇷 Français

Ce dépôt contient l'Infrastructure as Code (IaC) de mon homelab personnel, conçu avec une architecture sécurisée à 3 niveaux (3-tier) en utilisant Podman rootless.

### Architecture à 3 Niveaux

| Stage | Dossier | Statut | Rôle |
|:------|:--------|:------:|:-----|
| **Stage 1** | `infra/` | ✅ Actif | Passerelle Zero Trust (Cloudflare + Twingate) |
| **Stage 2** | `data/` | ✅ Actif | Persistance (PostgreSQL sur disque externe) |
| **Stage 3** | `apps/` | ✅ Actif | Applications (Vaultwarden, ...) |

Tous les stages partagent le réseau externe Podman `homelab_net`.

### Déploiement (Ordre Obligatoire)

```bash
# 1. Réseau partagé (une seule fois)
podman network create homelab_net

# 2. Stage 1 — Ne jamais arrêter à distance
podman-compose -f infra/compose.yml up -d

# 3. Stage 2 — Bases de données
podman-compose -f data/compose.yml up -d

# 4. Stage 3 — Applications
podman-compose -f apps/compose.yml up -d
```

### Posture de Sécurité (Zero-Trust)

- **Aucun port entrant ouvert** : Tout trafic passe par des tunnels sortants chiffrés.
- **Rootless Podman** : Aucun privilège root requis pour les conteneurs.
- **Secrets isolés** : Chaque stage possède son propre `.env` (ignoré par Git).
- **Versions épinglées** : Les images sont versionnées pour éviter les régressions.

---

## 🇺🇸 English

This repository contains the Infrastructure as Code (IaC) for my personal homelab, designed with a secure 3-tier architecture using rootless Podman.

### 3-Tier Architecture

| Stage | Directory | Status | Role |
|:------|:----------|:------:|:-----|
| **Stage 1** | `infra/` | ✅ Active | Zero Trust Gateway (Cloudflare + Twingate) |
| **Stage 2** | `data/` | ✅ Active | Persistence (PostgreSQL on external drive) |
| **Stage 3** | `apps/` | ✅ Active | Applications (Vaultwarden, ...) |

All stages share the external Podman network `homelab_net`.

### Deployment (Mandatory Order)

```bash
# 1. Shared network (once only)
podman network create homelab_net

# 2. Stage 1 — Never stop remotely
podman-compose -f infra/compose.yml up -d

# 3. Stage 2 — Databases
podman-compose -f data/compose.yml up -d

# 4. Stage 3 — Applications
podman-compose -f apps/compose.yml up -d
```

### Security Posture (Zero-Trust)

- **Zero inbound ports**: All traffic flows through encrypted outbound tunnels only.
- **Rootless Podman**: No root privileges required for container operations.
- **Isolated secrets**: Each stage has its own `.env` file, excluded from Git history.
- **Pinned versions**: Container images are versioned to prevent unexpected regressions.