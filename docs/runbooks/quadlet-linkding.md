# Runbook — Quadlet : Déploiement et exploitation de Linkding (Gestionnaire de Signets)

Ce runbook décrit le déploiement, l'exploitation et la restauration du service **Linkding** (gestionnaire de signets et de favoris web auto-hébergé) sous forme d'unités Quadlet systemd rootless.

## Rôle et Architecture

Linkding (`sissbruecker/linkding:1.46.2`) est une application web ultra-légère et rapide (~30-50 MB RAM) conçue pour centraliser et synchroniser les favoris web entre plusieurs navigateurs et appareils (Brave, Firefox, Safari, Chrome, mobile) :
- **Indépendance vis-à-vis des navigateurs :** Évite la dispersion des signets entre profils et moteurs de navigation.
- **Organisation & Recherche :** Gestion par tags, recherche en texte intégral, archivage automatique et interface épurée.
- **Intégration transparente :** Extensions officielles pour navigateurs et API REST complète.

## Fichiers IaC impliqués

| Fichier (dépôt) | Rôle |
|---|---|
| `apps/quadlet/linkding.container` | Unité conteneur Quadlet (image `docker.io/sissbruecker/linkding:1.46.2`, limites 512MB RAM / 0.5 CPU) |
| `apps/quadlet/linkding.volume` | Volume nommé `apps_linkding_data` (persistance SQLite et signets dans `/etc/linkding/data`) |
| `apps/linkding.env.example` | Modèle de variables d'environnement (`LD_SUPERUSER_NAME`, `LD_CSRF_TRUSTED_ORIGINS`, etc.) |
| `apps/glance/glance.yml` | Portail d'accueil Glance (sonde de disponibilité `http://linkding:9090` et suivi de version) |
| `scripts/backup.sh` | Sauvegarde logique quotidienne et rotation automatique du volume SQLite |

## Modèle de Persistance et Base de Données

Conformément à la stratégie d'architecture du homelab (voir `docs/architecture.md`), Linkding utilise le modèle **SQLite embarqué** :
- Les données et index résident exclusivement dans le volume nommé `apps_linkding_data` monté sur `/etc/linkding/data`.
- **Avantages :** Zéro daemon externe, empreinte mémoire minimale, isolation totale du rayon d'impact et sauvegarde 1:1 atomique.

## Procédure de Déploiement (Rootless)

### 1. Préparer les variables d'environnement

```bash
cp apps/linkding.env.example apps/linkding.env
chmod 600 apps/linkding.env
nano apps/linkding.env
```

Contenu type de `apps/linkding.env` :
```ini
TZ=Europe/Paris
LD_SUPERUSER_NAME=admin
LD_SUPERUSER_PASSWORD=VotreMotDePasseTresSecurise123!
LD_DISABLE_REGISTRATION=True
LD_CSRF_TRUSTED_ORIGINS=https://bookmarks.votre-domaine.com
LD_USE_X_FORWARDED_HOST=True
LD_USE_X_FORWARDED_PORT=True
```

Valider la conformité du fichier secret :
```bash
./scripts/check-env.sh apps/linkding.env
```

### 2. Déployer l'unité Quadlet

```bash
cp apps/quadlet/linkding.{container,volume} ~/.config/containers/systemd/

# Validation syntaxique Quadlet avant activation
/usr/libexec/podman/quadlet -dryrun -user

# Recharger systemd et démarrer le service
systemctl --user daemon-reload
systemctl --user start linkding
systemctl --user status linkding --no-pager
```

### 3. Validation interne Zero Trust (aucun port hôte exposé)

```bash
podman run --rm --network homelab_net docker.io/alpine:3.22 wget -qO- http://linkding:9090 | head -10
```

## Configuration de l'Accès Externe / Zero Trust

### Option A : Cloudflare Tunnel (Accès Web HTTPS)
1. Dans la console Cloudflare Zero Trust (Tunnels) :
   - Ajouter un **Public Hostname** : `bookmarks.votre-domaine.com`
   - Service : `HTTP` → `linkding:9090`
2. Ouvrir `https://bookmarks.votre-domaine.com` et se connecter avec le compte super-utilisateur initial défini dans `linkding.env`.

### Option B : Twingate SDN (Accès Réseau Privé)
- Définir une ressource Twingate pointant vers `linkding:9090` sur le réseau conteneur `homelab_net`.

## Intégration Navigateurs (Extensions)

1. Se connecter à l'interface web de Linkding.
2. Aller dans **Settings** → **Integrations** et copier le jeton d'API (API Authentication Token).
3. Installer l'extension Linkding sur votre navigateur (Chrome Web Store ou Firefox Add-ons).
4. Renseigner l'URL de votre instance (`https://bookmarks.votre-domaine.com`) et le jeton d'API.

## Procédure de Sauvegarde et Restauration

### Sauvegarde
La sauvegarde du volume `apps_linkding_data` est automatisée par `scripts/backup.sh` (timer systemd quotidien) :
- Archive générée : `linkding_data_<TIMESTAMP>.tar.gz` sur le disque externe.

### Test de Restauration
```bash
# Vérifier le contenu de l'archive
tar -tzf /path/to/backup/linkding/linkding_data_<TIMESTAMP>.tar.gz | grep db.sqlite3

# Test de restauration dans un volume temporaire
podman volume create test_linkding_restore
podman run --rm -v test_linkding_restore:/target -v /path/to/backup/linkding:/backup:ro docker.io/alpine:3.22 tar -xzf /backup/linkding_data_<TIMESTAMP>.tar.gz -C /target
podman volume rm test_linkding_restore
```

## Rollback

```bash
systemctl --user stop linkding
rm ~/.config/containers/systemd/linkding.{container,volume}
systemctl --user daemon-reload
```
Le volume nommé `apps_linkding_data` est conservé pour éviter toute perte accidentelle de données.
