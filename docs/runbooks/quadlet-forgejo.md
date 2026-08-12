# Runbook — Quadlet : Déploiement et exploitation de Forgejo (Git self-hosted)

Ce runbook décrit le déploiement, l'exploitation et la restauration du service **Forgejo** (forge logicielle et serveur Git souverain) au format d'unités Quadlet systemd rootless.

## Fichiers IaC impliqués

| Fichier (dépôt) | Rôle |
|---|---|
| `apps/quadlet/forgejo.container` | Unité conteneur Quadlet (image `codeberg.org/forgejo/forgejo:16-rootless`, limites de ressources 512MB RAM) |
| `apps/quadlet/forgejo.volume` | Volume nommé `apps_forgejo_data` (persistance SQLite, dépôts Git, clés SSH) |
| `apps/forgejo.env.example` | Modèle de variables d'environnement (`FORGEJO__server__ROOT_URL`, etc.) |
| `infra/quadlet/homelab.network` | Réseau partagé externe |

## Modèle de Persistance et Base de Données

Conformément à la stratégie d'architecture du homelab (voir `docs/architecture.md`), Forgejo utilise le modèle **SQLite embarqué** :
- Le fichier de base de données SQLite `gitea.db` et l'ensemble des dépôts Git résident exclusivement dans le volume nommé `apps_forgejo_data` (monté dans `/var/lib/gitea`).
- **Avantages** : zéro daemon veritabanı harici, empreinte RAM minimale (~200MB), isolation totale et sauvegarde/restauration atomique par le script `scripts/backup.sh`.

## Procédure de Déploiement (Rootless)

```bash
git pull                                              # Synchroniser IaC
mkdir -p ~/.config/containers/systemd
cp apps/quadlet/forgejo.{container,volume} ~/.config/containers/systemd/
cp apps/forgejo.env ~/.config/containers/systemd/    # généré depuis forgejo.env.example

# Validation de la syntaxe avant activation
/usr/libexec/podman/quadlet -dryrun -user

# Activation et démarrage de l'unité systemd
systemctl --user daemon-reload
systemctl --user start forgejo
systemctl --user status forgejo --no-pager          # attendu : active (running)
```

Test interne (Zero Trust — pas de port hôte exposé) :
```bash
podman run --rm --network homelab_net docker.io/alpine:3.22 wget -qO- http://forgejo:3000 | head -5
```

## Configuration du Tunnel Cloudflare (Web UI)

1. Dans le tableau de bord Cloudflare Zero Trust (Tunnels) :
   - Ajouter un **Public Hostname** : `git.${DOMAIN}`
   - Service : `HTTP` → `forgejo:3000`
2. Ouvrir `https://git.${DOMAIN}` dans le navigateur et finaliser le premier assistant d'installation (le compte d'administration créé lors du premier formulaire devient l'administrateur principal).

## Procédure de Sauvegarde et Restauration

### Sauvegarde
La sauvegarde est automatiquement prise en charge par `scripts/backup.sh` (timer systemd quotidien à 03h30) :
- Archive générée : `forgejo_data_<TIMESTAMP>.tar.gz` sur le disque externe.

### Restauration de test (Vérification Niveau 3)
```bash
# Tester l'intégrité de l'archive tar.gz
tar -tzf /path/to/backup/forgejo/forgejo_data_<TIMESTAMP>.tar.gz | grep gitea.db

# Restauration sur une instance de test jetable
podman volume create test_forgejo_restore
podman run --rm -v test_forgejo_restore:/target -v /path/to/backup/forgejo:/backup:ro docker.io/alpine:3.22 tar -xzf /backup/forgejo_data_<TIMESTAMP>.tar.gz -C /target
podman volume rm test_forgejo_restore
```

## Rollback

```bash
systemctl --user stop forgejo
rm ~/.config/containers/systemd/forgejo.{container,volume}
systemctl --user daemon-reload
```
Le volume nommé `apps_forgejo_data` n'est pas supprimé par le rollback (données préservées).
