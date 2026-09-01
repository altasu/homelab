# Runbook — Quadlet : Déploiement du Dashboard Glance

Ce runbook décrit le déploiement et la gestion de **Glance**, le portail d'accueil et tableau de bord unifié du homelab, sous forme d'unité Quadlet systemd rootless.

## Rôle et Architecture

Glance (`glanceapp/glance:v0.8.5`) est un tableau de bord ultra-léger écrit en Go (~15-20 MB RAM). Il sert de page de démarrage pour le homelab :
- **Navigation centralisée :** Liens directs vers tous les services applicatifs (Vaultwarden, Actual Budget, Forgejo, Windows VM, Cockpit).
- **Surveillance de disponibilité (Healthcheck) :** Sondes HTTP régulières sur le réseau interne `homelab_net` pour afficher l'état (en ligne / hors ligne) de chaque conteneur.
- **Flux d'information :** Intégration de flux RSS et widgets temporels.

## Fichiers IaC impliqués

| Fichier (dépôt) | Rôle |
|---|---|
| `apps/quadlet/glance.container` | Unité conteneur Quadlet (image `docker.io/glanceapp/glance:v0.8.5`) |
| `apps/glance/glance.yml` | Fichier de configuration principal définissant les pages, colonnes et widgets |
| `apps/glance.env.example` | Modèle de variables d'environnement |

## Procédure de Déploiement

### 1. Préparer l'environnement
Copiez le modèle d'environnement et configurez les URLs d'accès à vos services :
```bash
cp apps/glance.env.example apps/glance.env
nano apps/glance.env
```
Renseignez vos URLs réelles selon votre mode d'accès (Cloudflare Tunnel ou Twingate) :
```ini
TZ=Europe/Paris

URL_VAULTWARDEN=https://vaultwarden.votre-domaine.com
URL_ACTUAL_BUDGET=https://budget.votre-domaine.com
URL_FORGEJO=https://git.votre-domaine.com
URL_COCKPIT=https://192.168.x.x:9090
URL_GRAFANA=https://grafana.votre-domaine.com
URL_PROMETHEUS=http://prometheus:9090
URL_NTFY=https://ntfy.votre-domaine.com
```
> **Bonne pratique de sécurité (Zero Trust) :** Toutes les URLs réelles et adresses privées sont isolées dans `apps/glance.env` (ignoré par Git) et injectées dynamiquement dans `glance.yml`. Le dépôt Git public ne contient aucune donnée sensible.

### 2. Déploiement Quadlet
```bash
cp apps/quadlet/glance.container ~/.config/containers/systemd/

systemctl --user daemon-reload
systemctl --user start glance
systemctl --user status glance --no-pager
```

## Personnalisation des Services

Pour ajouter ou modifier des raccourcis et des sondes de surveillance :
1. Éditez le fichier `apps/glance/glance.yml`.
2. Redémarrez l'unité pour appliquer immédiatement les changements :
```bash
systemctl --user restart glance
```

## Rollback

```bash
systemctl --user stop glance
rm ~/.config/containers/systemd/glance.container
systemctl --user daemon-reload
```
