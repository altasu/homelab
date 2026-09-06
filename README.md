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
| **Stage 3** | `apps/` | ✅ Actif | Applications (Vaultwarden, Actual Budget, Windows 11 VM, Forgejo & Runner, Glance, Linkding) et observabilité (Prometheus, Grafana, node_exporter, ntfy) |

Tous les stages partagent le réseau externe Podman `homelab_net` (sauf les connecteurs hôtes).

### Orchestration : unités Quadlet & Déploiement GitOps (Pull-based)

L'orchestration est assurée par **Quadlet** : chaque service est décrit par une unité `.container` versionnée dans le stage correspondant (`*/quadlet/`), exécutée en mode rootless par systemd utilisateur.

Le cycle de vie et les mises à jour sont entièrement automatisés selon une approche **GitOps pull-based** :
1. **Renovate Bot** : scanne quotidiennement le dépôt (`.gitlab-ci.yml`), vérifie les versions des conteneurs Quadlet et ouvre des *Merge Requests*.
2. **Synchronisation continue (`homelab-sync.timer`)** : un timer systemd utilisateur vérifie périodiquement la branche `main`, applique les nouveaux fichiers Quadlet de manière chirurgicale, recharge le démon et redémarre uniquement les conteneurs modifiés, avec notification `ntfy`.

```bash
# Déploiement manuel ou initial (après git pull)
cp infra/quadlet/* data/quadlet/* apps/quadlet/* ~/.config/containers/systemd/
systemctl --user daemon-reload
systemctl --user start postgres vaultwarden actual-budget cloudflared twingate-connector twingate-host \
  prometheus grafana node-exporter podman-exporter ntfy windows forgejo forgejo-runner glance linkding

# Activation de la synchronisation continue GitOps
systemctl --user enable --now homelab-sync.timer
```

L'ordre de démarrage n'a plus à être appliqué manuellement : les dépendances systemd (`Requires=`/`After=`) et le healthcheck de la base le garantissent, au démarrage comme au boot (`loginctl enable-linger` + section `[Install]` des unités).

Secrets : un fichier env par service (`<stage>/<service>.env`, jamais versionné), validé par `scripts/check-env.sh`.

> Voir les runbooks dédiés : [Plan de migration](docs/quadlet-migration-plan.md) et [GitOps & Renovate Sync](docs/runbooks/gitops-renovate-sync.md).

### Posture de Sécurité (Zero-Trust)

- **Aucun port entrant ouvert** : Tout trafic passe par des tunnels sortants chiffrés.
- **Rootless Podman** : Aucun privilège root requis pour les conteneurs.
- **Déploiement GitOps Pull-based** : Aucune clé SSH privée sur GitLab.com, isolation ANSSI/OWASP totale.
- **Secrets isolés** : Chaque service possède son propre fichier env (ignoré par Git).
- **Versions épinglées & automatisées** : Les images sont versionnées et gérées par Renovate.
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
| **Stage 3** | `apps/` | ✅ Active | Applications (Vaultwarden, Actual Budget, Windows 11 VM, Forgejo & Runner, Glance, Linkding) and observability (Prometheus, Grafana, node_exporter, ntfy) |

All stages share the external Podman network `homelab_net` (except host connectors).

### Orchestration: Quadlet units & Pull-based GitOps Continuous Deployment

Orchestration relies on **Quadlet**: each service is described by a version-controlled `.container` unit inside its stage (`*/quadlet/`), run rootless by user systemd.

Service lifecycle and automated updates follow a secure **pull-based GitOps** model:
1. **Renovate Bot**: scans the repository on a scheduled basis (`.gitlab-ci.yml`), detects new Quadlet image tags, and opens automated *Merge Requests*.
2. **Continuous Sync (`homelab-sync.timer`)**: a user systemd timer periodically checks `main`, surgically copies modified Quadlet files, reloads the daemon, and restarts only affected containers with `ntfy` alerts.

```bash
# Manual or initial deployment (after git pull)
cp infra/quadlet/* data/quadlet/* apps/quadlet/* ~/.config/containers/systemd/
systemctl --user daemon-reload
systemctl --user start postgres vaultwarden actual-budget cloudflared twingate-connector twingate-host \
  prometheus grafana node-exporter podman-exporter ntfy windows forgejo forgejo-runner glance linkding

# Enable GitOps continuous synchronization timer
systemctl --user enable --now homelab-sync.timer
```

Startup order no longer needs to be applied manually: systemd dependencies (`Requires=`/`After=`) plus the database healthcheck enforce it, both on demand and at boot (`loginctl enable-linger` + the units' `[Install]` section).

Secrets: one env file per service (`<stage>/<service>.env`, never version-controlled), validated by `scripts/check-env.sh`.

> See dedicated runbooks: [Migration Plan](docs/quadlet-migration-plan.md) and [GitOps & Renovate Sync](docs/runbooks/gitops-renovate-sync.md).

### Security Posture (Zero-Trust)

- **Zero inbound ports**: All traffic flows through encrypted outbound tunnels only.
- **Rootless Podman**: No root privileges required for container operations.
- **Pull-based GitOps Deployment**: Zero private SSH keys stored on GitLab.com, maintaining strict ANSSI/OWASP isolation.
- **Isolated secrets**: Each service has its own env file, excluded from Git history.
- **Automated pinned versions**: Container images are versioned and maintained by Renovate.
- **Least privilege**: Each application uses its own non-superuser PostgreSQL role.
- **Verified backups**: Scheduled daily backups that fail loudly, with tested restore — see [the runbook](docs/runbooks/sauvegardes-verification-restauration.md).