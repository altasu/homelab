# Runbook — Quadlet : Déploiement et exploitation de Wakapi (Télémétrie de Code WakaTime)

Ce runbook décrit le déploiement, l'exploitation, la configuration des clients IDE et la sauvegarde du service **Wakapi** (backend auto-hébergé compatible WakaTime) sous forme d'unités Quadlet systemd rootless.

---

## 1. Rôle et Architecture

Wakapi (`ghcr.io/muety/wakapi:2.17.6`) est un serveur léger écrit en Go conçu pour collecter, analyser et restituer les métriques d'activité de développement (temps passé par langage, projet, branche et éditeur) :

- **Compatibilité WakaTime :** Implémente l'API v1 WakaTime, permettant l'utilisation directe des extensions officielles (IntelliJ IDEA, VS Code, Neovim, etc.).
- **Ultra-léger & Éco-conçu :** Consommation mémoire minimale (~15 à 25 Mo de RAM au repos), idéale pour un serveur modeste (Lenovo i7-6500U).
- **Souveraineté des Données :** Les habitudes et volumes de travail restent confinés sur l'infrastructure personnelle sans télémétrie externe.

---

## 2. Fichiers IaC Impliqués

| Fichier (dépôt) | Rôle |
|---|---|
| `apps/quadlet/wakapi.container` | Unité conteneur Quadlet (image `ghcr.io/muety/wakapi:2.17.6`, limites 128 Mo RAM / 0.25 vCPU) |
| `apps/quadlet/wakapi.volume` | Volume nommé `apps_wakapi_data` (persistance SQLite dans `/data/wakapi.db`) |
| `apps/wakapi.env.example` | Modèle de variables d'environnement (`WAKAPI_PASSWORD_SALT`, `WAKAPI_PUBLIC_URL`, etc.) |
| `scripts/backup.sh` | Sauvegarde logique quotidienne et rotation automatique du volume SQLite |

---

## 3. Modèle de Persistance et Base de Données

Conformément à la convention d'architecture du homelab (voir `docs/architecture.md`) :
- Les données et la base SQLite résident exclusivement dans le volume nommé `apps_wakapi_data` monté sur `/data`.
- **Avantages :** Zéro daemon externe, empreinte mémoire minimale, isolation totale du rayon d'impact et sauvegarde atomique intégrée.


---

## 4. Procédure de Déploiement sur le Serveur

### Étape 1 : Préparation du fichier d'environnement

```bash
cd ~/homelab
cp apps/wakapi.env.example apps/wakapi.env
chmod 600 apps/wakapi.env
nano apps/wakapi.env
```

Paramètres à ajuster dans `apps/wakapi.env` :
- `WAKAPI_PASSWORD_SALT` : Générer une clé aléatoire forte (`openssl rand -hex 32`).
- `WAKAPI_PUBLIC_URL` : URL publique du service (ex : `https://wakapi.votre-domaine.com`).
- `WAKAPI_ALLOW_SIGNUP` : Laisser à `true` lors de la première initialisation pour créer le compte administrateur.

Valider la conformité du format :
```bash
./scripts/check-env.sh apps/wakapi.env
```

### Étape 2 : Déploiement et activation de l'unité Quadlet

```bash
cp apps/quadlet/wakapi.{container,volume} ~/.config/containers/systemd/

# Validation syntaxique Quadlet
/usr/libexec/podman/quadlet -dryrun -user

# Rechargement et démarrage
systemctl --user daemon-reload
systemctl --user start wakapi
systemctl --user status wakapi --no-pager
```

### Étape 3 : Validation interne

```bash
podman run --rm --network homelab.network docker.io/alpine:3.22 wget -qO- http://wakapi:3000/api/health
```
*(Doit renvoyer un statut 200 OK).*

---

## 5. Exposition Réseau (Cloudflare Tunnel)

Dans la console Cloudflare Zero Trust (Tunnels) :
1. Ajouter un **Public Hostname** : `wakapi.votre-domaine.com`
2. Service : `HTTP` vers `wakapi:3000`
3. Ouvrir l'URL dans le navigateur, créer votre compte utilisateur dans Wakapi, puis repasser impérativement `WAKAPI_ALLOW_SIGNUP=false` dans `apps/wakapi.env` et redémarrer le service (`systemctl --user restart wakapi`).

---

## 6. Configuration des Clients IDE (IntelliJ IDEA & VS Code)

Une fois connecté sur l'interface web de Wakapi :
1. Cliquer sur les paramètres de profil pour récupérer votre **API Key** (clé secrète).
2. Dans votre répertoire utilisateur local sur Mac/Linux (`~/.wakatime.cfg`), renseigner :

```ini
[settings]
api_url = https://wakapi.votre-domaine.com/api/compat/wakatime/v1
api_key = votre_cle_api_wakapi
```

3. **Dans IntelliJ IDEA :**
   - Installer le plugin officiel **WakaTime** via le Marketplace.
   - Le plugin détecte automatiquement la configuration `~/.wakatime.cfg`.
   - Vos frappes et modifications de code remontent instantanément sur votre tableau de bord personnel.

---

## 7. Sauvegarde et Résilience

La sauvegarde du volume `apps_wakapi_data` est intégrée dans le cycle quotidien de `scripts/backup.sh` :
- Archive générée : `wakapi_data_<TIMESTAMP>.tar.gz` sur `/mnt/backup_vault/wakapi/`.
- Test d'intégrité de décompression automatique (`gunzip -t`).
