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

| Fichier (dépôt)                 | Rôle                                                                                          |
| ------------------------------- | --------------------------------------------------------------------------------------------- |
| `apps/quadlet/wakapi.container` | Unité conteneur Quadlet (image `ghcr.io/muety/wakapi:2.17.6`, limites 128 Mo RAM / 0.25 vCPU) |
| `apps/quadlet/wakapi.volume`    | Volume nommé `apps_wakapi_data` (persistance SQLite dans `/data/wakapi.db`)                   |
| `apps/wakapi.env.example`       | Modèle de variables d'environnement (`WAKAPI_PASSWORD_SALT`, `WAKAPI_PUBLIC_URL`, etc.)       |
| `scripts/backup.sh`             | Sauvegarde logique quotidienne et rotation automatique du volume SQLite                       |

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
podman run --rm --network homelab_net docker.io/alpine:3.22 wget -qO- http://wakapi:3000/api/health
```

_(Doit renvoyer un statut 200 OK)._

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
api_url = https://wakapi.votre-domaine.com/api
api_key = votre_cle_api_wakapi
```
*(Remarque : `https://wakapi.votre-domaine.com/api` est l'URL canonique recommandée par Wakapi. L'alias `/api/compat/wakatime/v1` reste également fonctionnel).*


3. **Dans IntelliJ IDEA :**
   - Installer le plugin officiel **WakaTime** via le Marketplace.
   - Le plugin détecte automatiquement la configuration `~/.wakatime.cfg`.
   - Vos frappes et modifications de code remontent instantanément sur votre tableau de bord personnel.

---

## 7. Sauvegarde et Résilience

- Archive générée : `wakapi_data_<TIMESTAMP>.tar.gz` sur le disque externe.
- Test d'intégrité de décompression automatique (`gunzip -t`).

---

## 8. Procédure de Rollback (Retour Arrière)

En cas de régression ou de défaillance lors d'une mise à jour de Wakapi :

```bash
# 1. Stopper l'unité systemd
systemctl --user stop wakapi

# 2. Retirer les unités Quadlet actives
rm -f ~/.config/containers/systemd/wakapi.{container,volume}
systemctl --user daemon-reload

# 3. Supprimer le conteneur résiduel
podman rm -f wakapi
```

Pour restaurer une version précédente depuis l'historique Git :
```bash
git -C ~/homelab checkout <commit-sha> -- apps/quadlet/wakapi.container
cp ~/homelab/apps/quadlet/wakapi.container ~/.config/containers/systemd/
systemctl --user daemon-reload && systemctl --user start wakapi
```

---

## 9. Leçons Retenues & Bonnes Pratiques

- **Verrouillage strict des inscriptions (`WAKAPI_ALLOW_SIGNUP=false`) :** Dès la création du compte initial effectuée, la variable d'environnement doit repasser à `false`. Étant exposé publiquement via Cloudflare Tunnel, laisser les inscriptions ouvertes exposerait l'instance à un détournement de stockage télémétrique.
- **Normalisation de l'API WakaTime (`/api`) :** Les plugins WakaTime (IntelliJ, VS Code) requièrent explicitement le suffixe `/api` dans `api_url = https://wakapi.<domaine>/api`. Omettre ce suffixe provoque des erreurs silencieuses 404 lors de l'envoi des *heartbeats* de frappe.
- **Efficacité de l'architecture binaire Go + SQLite :** Contrairement aux stacks télémétriques lourdes, Wakapi est un binaire Go compilé statiquement opérant sur SQLite en mode WAL. L'empreinte mémoire reste inférieure à 30 Mo de RAM, permettant un confinement cgroups strict à `128m` sans aucun risque de déclenchement d'OOM Killer.
- **Résilience des tokens IDE :** Les clés API générées par Wakapi sont persistées dans `/data/wakapi.db`. La sauvegarde quotidienne du volume `apps_wakapi_data` assure qu'en cas de réinstallation, aucun IDE local n'a besoin d'être reconfiguré.
