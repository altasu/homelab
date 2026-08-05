# Homelab Infrastructure (IaC)

🇫🇷 **Français** | 🇺🇸 **English**

---

## 🇫🇷 Français

Ce dépôt contient l'Infrastructure as Code (IaC) de mon homelab personnel, conçu avec une architecture sécurisée à 3 niveaux (3-tier) en utilisant Podman rootless.

📖 **Documentation publiée** : [GitLab Pages](https://homelab-ec5d79.gitlab.io/) · [GitHub Pages](https://altasu.github.io/homelab/) — démarche, incidents réels et runbooks détaillés.

### Architecture à 3 Niveaux

| Stage | Dossier | Statut | Rôle |
|:------|:--------|:------:|:-----|
| **Stage 1** | `infra/` | ✅ Actif | Passerelle Zero Trust (Cloudflare + Twingate) |
| **Stage 2** | `data/` | ✅ Actif | Persistance (PostgreSQL sur disque externe) |
| **Stage 3** | `apps/` | ✅ Actif | Applications (Vaultwarden, Actual Budget) et observabilité (Prometheus, Grafana, node_exporter, ntfy) |

Tous les stages partagent le réseau externe Podman `homelab_net`.

### Orchestration : unités Quadlet (systemd utilisateur)

L'orchestration est assurée par **Quadlet** : chaque service est décrit par une unité `.container` versionnée dans le stage correspondant (`*/quadlet/`), exécutée en mode rootless par systemd utilisateur.

```bash
# 1. Déployer les unités (après git pull)
cp infra/quadlet/* data/quadlet/* apps/quadlet/* ~/.config/containers/systemd/

# 2. Valider la syntaxe AVANT activation
/usr/libexec/podman/quadlet -dryrun -user

# 3. Recharger et démarrer
systemctl --user daemon-reload
systemctl --user start postgres vaultwarden actual-budget cloudflared twingate-connector \
  prometheus grafana node-exporter podman-exporter ntfy
```

L'ordre de démarrage n'a plus à être appliqué manuellement : les dépendances systemd (`Requires=`/`After=`) et le healthcheck de la base le garantissent, au démarrage comme au boot (`loginctl enable-linger` + section `[Install]` des unités).

Secrets : un fichier env par service (`<stage>/<service>.env`, jamais versionné), validé par `scripts/check-env.sh`.

> Les fichiers `compose.yml` sont conservés à titre historique et comme solution de repli — voir [le plan de migration](docs/quadlet-migration-plan.md).

### Posture de Sécurité (Zero-Trust)

- **Aucun port entrant ouvert** : Tout trafic passe par des tunnels sortants chiffrés.
- **Rootless Podman** : Aucun privilège root requis pour les conteneurs.
- **Secrets isolés** : Chaque service possède son propre fichier env (ignoré par Git).
- **Versions épinglées** : Les images sont versionnées pour éviter les régressions.
- **Moindre privilège** : Chaque application dispose de son propre rôle PostgreSQL non-superuser.
- **Sauvegardes vérifiées** : Sauvegarde quotidienne planifiée, échec bruyant, restauration testée — voir [le runbook](docs/runbooks/sauvegardes-verification-restauration.md).

---

## 🇺🇸 English

This repository contains the Infrastructure as Code (IaC) for my personal homelab, designed with a secure 3-tier architecture using rootless Podman.

📖 **Published documentation**: [GitLab Pages](https://homelab-ec5d79.gitlab.io/) · [GitHub Pages](https://altasu.github.io/homelab/) — approach, real incidents, and detailed runbooks.

### 3-Tier Architecture

| Stage | Directory | Status | Role |
|:------|:----------|:------:|:-----|
| **Stage 1** | `infra/` | ✅ Active | Zero Trust Gateway (Cloudflare + Twingate) |
| **Stage 2** | `data/` | ✅ Active | Persistence (PostgreSQL on external drive) |
| **Stage 3** | `apps/` | ✅ Active | Applications (Vaultwarden, Actual Budget) and observability (Prometheus, Grafana, node_exporter, ntfy) |

All stages share the external Podman network `homelab_net`.

### Orchestration: Quadlet units (user systemd)

Orchestration relies on **Quadlet**: each service is described by a version-controlled `.container` unit inside its stage (`*/quadlet/`), run rootless by user systemd.

```bash
# 1. Deploy the units (after git pull)
cp infra/quadlet/* data/quadlet/* apps/quadlet/* ~/.config/containers/systemd/

# 2. Validate syntax BEFORE activation
/usr/libexec/podman/quadlet -dryrun -user

# 3. Reload and start
systemctl --user daemon-reload
systemctl --user start postgres vaultwarden actual-budget cloudflared twingate-connector \
  prometheus grafana node-exporter podman-exporter ntfy
```

Startup order no longer needs to be applied manually: systemd dependencies (`Requires=`/`After=`) plus the database healthcheck enforce it, both on demand and at boot (`loginctl enable-linger` + the units' `[Install]` section).

Secrets: one env file per service (`<stage>/<service>.env`, never version-controlled), validated by `scripts/check-env.sh`.

> The `compose.yml` files are kept as historical reference and fallback — see [the migration plan](docs/quadlet-migration-plan.md).

### Security Posture (Zero-Trust)

- **Zero inbound ports**: All traffic flows through encrypted outbound tunnels only.
- **Rootless Podman**: No root privileges required for container operations.
- **Isolated secrets**: Each service has its own env file, excluded from Git history.
- **Pinned versions**: Container images are versioned to prevent unexpected regressions.
- **Least privilege**: Each application uses its own non-superuser PostgreSQL role.
- **Verified backups**: Scheduled daily backups that fail loudly, with tested restore — see [the runbook](docs/runbooks/sauvegardes-verification-restauration.md).