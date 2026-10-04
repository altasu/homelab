# Runbook — Quadlet : Déploiement du Dashboard Glance

Ce runbook décrit le déploiement et la gestion de **Glance**, le portail d'accueil et tableau de bord unifié du homelab, sous forme d'unité Quadlet systemd rootless.

## Rôle et Architecture

Glance (`glanceapp/glance:v0.8.5`) est un tableau de bord ultra-léger écrit en Go (~15-20 MB RAM). Il sert de page de démarrage pour le homelab :
- **Navigation centralisée :** Liens directs vers tous les services applicatifs (Vaultwarden, Actual Budget, Forgejo, Cockpit, Grafana, Prometheus, ntfy).
- **Surveillance de disponibilité (Healthcheck) :** Sondes HTTP régulières sur le réseau interne `homelab_net` pour afficher l'état (en ligne / hors ligne) de chaque conteneur.
- **Métriques & Flux d'information :** Télémétrie CPU/RAM/Disque en direct, flux RSS et suivi automatique des versions logicielles.

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

## Personnalisation des Services & Standard d'Intégrité

### Règles d'Or pour l'ajout d'un service
1. **Standardisation stricte des icônes :** Utiliser exclusivement des icônes monochromatiques issues des jeux `si:` ([Simple Icons](https://simpleicons.org/)) ou `mdi:` ([Material Design Icons](https://pictogrammers.com/library/mdi/)). Elles héritent automatiquement de la couleur d'accentuation du thème. Les jeux pré-colorés ou badges (ex: `di:`, `sh:`, `fa:`) sont strictement proscrits.
2. **Parité absolue des variables :** Toute variable d'URL interpolée sous la forme `${URL_SERVICE}` dans `apps/glance/glance.yml` doit impérativement être déclarée dans `apps/glance.env.example` (IaC public) et dans `apps/glance.env` (production sur l'hôte).

### Point de Contrôle Automatisé (`scripts/check-glance.sh`)

Un script de contrôle d'intégrité valide la configuration à deux niveaux de la chaîne GitOps :

- **Niveau 1 — CI/CD GitLab (`validate-architecture`) :**
  Exécuté sur chaque commit et Merge Request pour vérifier :
  - L'absence de tabulations illégales dans le YAML.
  - La conformité syntaxique YAML complète.
  - Le respect des préfixes d'icônes `si:` ou `mdi:`.
  - La déclaration de chaque `${VAR}` dans `apps/glance.env.example`.
  ```bash
  # Test statique local / CI
  scripts/check-glance.sh apps/glance/glance.yml apps/glance.env.example
  ```

- **Niveau 2 — GitOps Runtime (`scripts/homelab-sync.sh`) :**
  Lors d'une synchronisation sur le serveur hôte :
  - Le script compare les variables requises par `glance.yml` avec le fichier réel `apps/glance.env`.
  - **Garde-fou anti-crash :** Si une variable est manquante sur le serveur, le redémarrage de Glance est **suspendu** pour préserver la haute disponibilité du tableau de bord existant.
  - Une alerte haute priorité est instantanément transmise via `ntfy` pour inviter l'administrateur à renseigner la variable dans `apps/glance.env`.
  ```bash
  # Test runtime sur l'hôte (vérifie que les variables réelles ne sont pas vides)
  scripts/check-glance.sh apps/glance/glance.yml apps/glance.env --runtime
  ```

## Procédure d'Ajout d'un Nouveau Service

1. Déclarer la variable d'exemple dans `apps/glance.env.example` :
   ```ini
   URL_NOUVEAU_SERVICE=https://service.votre-domaine.com
   ```
2. Ajouter le raccourci ou le moniteur dans `apps/glance/glance.yml` :
   ```yaml
   - title: Nouveau Service
     icon: si:monochromeicon
     url: ${URL_NOUVEAU_SERVICE}
   ```
3. Vérifier localement la conformité :
   ```bash
   ./scripts/check-glance.sh
   ```
4. Une fois la MR fusionnée sur `main`, ajouter l'URL de production dans `apps/glance.env` sur l'hôte avant ou après la synchronisation :
   ```bash
   echo "URL_NOUVEAU_SERVICE=https://service.altasworld.com" >> apps/glance.env
   systemctl --user restart glance
   ```

## Rollback

```bash
systemctl --user stop glance
rm ~/.config/containers/systemd/glance.container
systemctl --user daemon-reload
```
