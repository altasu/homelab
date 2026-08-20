# Runbook — Quadlet : Déploiement et exploitation d'OmniRoute (Passerelle IA multi-fournisseurs)

Ce runbook décrit le déploiement, l'exploitation et la maintenance du service **OmniRoute** (passerelle et proxy IA unifié pour modèles de langage) au format d'unités Quadlet systemd rootless.

## Fichiers IaC impliqués

| Fichier (dépôt) | Rôle |
|---|---|
| `apps/quadlet/omniroute.container` | Unité conteneur Quadlet (image `ghcr.io/diegosouzapw/omniroute:3.8.49`, limites 1024MB RAM / 1.0 CPU) |
| `apps/quadlet/omniroute.volume` | Volume nommé `apps_omniroute_data` (base SQLite, configuration chiffrée, clés API) |
| `apps/omniroute.env.example` | Modèle de variables d'environnement (`INITIAL_PASSWORD`, `STORAGE_ENCRYPTION_KEY`, etc.) |
| `infra/quadlet/homelab.network` | Réseau interne partagé `homelab_net` |

## Modèle de Persistance et Sécurité

Conformément à la stratégie d'architecture du homelab (voir `docs/architecture.md`), OmniRoute s'appuie sur le modèle **SQLite embarqué** :
- Les configurations des fournisseurs (OpenAI, Anthropic, Gemini, DeepSeek), les clés d'API chiffrées en AES-256 et les métriques de requêtes résident exclusivement dans le volume `apps_omniroute_data` (monté dans `/app/data`).
- **Chiffrement au repos** : la variable `STORAGE_ENCRYPTION_KEY` garantit que même en cas de copie brute de la base SQLite, les clés d'API des fournisseurs LLM demeurent illisibles.
- **Posture Zero-Trust** : aucun port hôte n'est exposé ; le trafic interne est routé via `homelab_net` et l'accès externe/dashboard est sécurisé par Cloudflare Tunnel ou Twingate.

## Procédure de Déploiement (Rootless)

```bash
# 1. Synchroniser le dépôt
git pull

# 2. Préparer le fichier d'environnement
cp apps/omniroute.env.example apps/omniroute.env
chmod 600 apps/omniroute.env

# Générer les clés cryptographiques requises
openssl rand -hex 32   # Utiliser pour STORAGE_ENCRYPTION_KEY
openssl rand -hex 32   # Utiliser pour JWT_SECRET
openssl rand -hex 32   # Utiliser pour API_KEY_SECRET

# Éditer apps/omniroute.env avec vos clés et votre mot de passe administrateur fort
# Valider la conformité du fichier
scripts/check-env.sh apps/omniroute.env

# 3. Déployer les unités Quadlet
mkdir -p ~/.config/containers/systemd
cp apps/quadlet/omniroute.{container,volume} ~/.config/containers/systemd/

# 4. Valider la syntaxe
/usr/libexec/podman/quadlet -dryrun -user

# 5. Charger et démarrer le service
systemctl --user daemon-reload
systemctl --user start omniroute
systemctl --user status omniroute --no-pager
```

## Configuration du Routage (Cloudflare Tunnel / Twingate)

### 1. Accès Web / Dashboard (Cloudflare Zero Trust)
Dans le tableau de bord Cloudflare Zero Trust (Tunnels) :
- Ajouter un **Public Hostname** : `ai.${DOMAIN}` (ou `omniroute.${DOMAIN}`)
- Service : `HTTP` → `omniroute:20128`
- Associer une règle **Cloudflare Access Policy** (MFA / restriction d'accès e-mail) pour protéger le tableau de bord.

### 2. Accès VPN Local (Twingate)
Définir une ressource Twingate pointant vers l'hôte homelab sur le port `20128` pour les développements locaux hors tunnels publics.

## Configuration des Clients IA (Claude Code, Cursor, Cline)

OmniRoute expose une API compatible OpenAI sur `/v1`. Une fois vos fournisseurs configurés dans le tableau de bord :

- **Base URL** : `https://ai.${DOMAIN}/v1`
- **API Key** : Clé API générée depuis le tableau de bord OmniRoute (`Settings -> API Keys`).

Exemple pour Claude Code / OpenCode :
```bash
export OPENAI_BASE_URL="https://ai.${DOMAIN}/v1"
export OPENAI_API_KEY="<VOTRE_CLE_OMNIROUTE>"
```

## Procédure de Sauvegarde et Restauration

### Sauvegarde
La sauvegarde est automatiquement prise en charge par `scripts/backup.sh` :
- Archive générée : `omniroute_data_<TIMESTAMP>.tar.gz` sur le disque externe.

### Restauration de test
```bash
# Vérification de l'archive tar.gz
tar -tzf /path/to/backup/omniroute/omniroute_data_<TIMESTAMP>.tar.gz | grep omniroute

# Restauration sur volume de test
podman volume create test_omniroute_restore
podman run --rm -v test_omniroute_restore:/target -v /path/to/backup/omniroute:/backup:ro docker.io/alpine:3.22 tar -xzf /backup/omniroute_data_<TIMESTAMP>.tar.gz -C /target
podman volume rm test_omniroute_restore
```

## Rollback

```bash
systemctl --user stop omniroute
rm ~/.config/containers/systemd/omniroute.{container,volume}
systemctl --user daemon-reload
```
Le volume `apps_omniroute_data` est conservé par défaut.
