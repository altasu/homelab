# Runbook — Observabilité (Prometheus, Grafana, exportateurs)

Pile de supervision déployée à l'Étape 7, en unités Quadlet comme le reste de la stack.

## Composants et rôles

| Composant | Rôle | Exposition |
|---|---|---|
| Prometheus | Collecte et stockage des séries temporelles (rétention 15 jours) | Aucune — joignable uniquement depuis le réseau partagé |
| Grafana | Tableaux de bord et alertes | VPN Zero Trust uniquement (aucune route de tunnel public) |
| node_exporter | Métriques de l'hôte (CPU, mémoire, disques) + collecteur textfile | Interne |
| prometheus-podman-exporter | Métriques des conteneurs via le socket Podman utilisateur | Interne |

### Pourquoi cet exportateur de conteneurs plutôt que cAdvisor

En rootless, cAdvisor accède mal aux cgroups et consomme beaucoup de CPU — inacceptable sur une machine à deux cœurs. L'exportateur Podman se contente d'interroger le socket utilisateur : nettement plus léger et conçu pour ce mode d'exécution.

**Prérequis** : `systemctl --user enable --now podman.socket`.

## Ce qui est supervisé, et ce qui ne l'est pas

- **Sauvegardé** : le volume Grafana (tableaux de bord et configuration — petit mais fruit d'un travail).
- **Non sauvegardé, volontairement** : le volume Prometheus. L'historique de métriques est une donnée *remplaçable* ; sa perte n'a aucune conséquence opérationnelle et son volume grossirait inutilement les archives.

## Supervision de la sauvegarde elle-même

C'est l'apport le plus important de cette étape, tiré directement des incidents des 2026-08-03 et 2026-08-04 (sauvegardes silencieusement absentes ou vides).

`scripts/backup.sh` écrit, à chaque exécution, un fichier de métriques dans le répertoire lu par le collecteur *textfile* de node_exporter (écriture atomique : fichier temporaire puis renommage, afin que l'exportateur ne lise jamais un contenu partiel) :

- `homelab_backup_last_run_timestamp_seconds`
- `homelab_backup_last_success_timestamp_seconds`
- `homelab_backup_last_exit_code`

Ces métriques alimentent deux alertes. La règle sur l'ancienneté utilise **`noDataState: Alerting`** : la disparition pure et simple de la métrique est précisément le symptôme recherché (script qui ne s'exécute plus du tout), elle doit donc déclencher l'alerte plutôt que d'être ignorée.

## Configuration en tant que code

La source de données et les règles d'alerte sont provisionnées depuis `apps/monitoring/grafana/` (montage en lecture seule dans `/etc/grafana/provisioning/`). Après une restauration complète, Grafana retrouve seul sa configuration : aucune reconstruction à la souris.

**Vérification après tout changement de provisionnement** — un fichier invalide n'empêche pas Grafana de démarrer, l'erreur n'apparaît que dans le journal :
```bash
journalctl --user -u grafana --since "-2m" --no-pager | grep -iE "provision|error|failed"
```

Les tableaux de bord restent importés depuis l'interface (tableau de bord communautaire « Node Exporter Full ») ; leur contenu vit dans le volume Grafana, couvert par les sauvegardes.

## Requêtes de vérification utiles

```bash
# Toutes les cibles sont-elles collectees ?
podman run --rm --network homelab_net docker.io/alpine:3.22 \
  wget -qO- 'http://prometheus:9090/api/v1/query?query=up'

# Etat de la derniere sauvegarde vu par Prometheus
podman run --rm --network homelab_net docker.io/alpine:3.22 \
  wget -qO- 'http://prometheus:9090/api/v1/query?query=homelab_backup_last_exit_code'
```

## Acheminement des notifications (ntfy)

Une alerte que personne ne regarde n'a aucune valeur : les règles sont routées vers un service de notification auto-hébergé, dont le point de contact et la politique de routage sont eux aussi provisionnés en tant que code.

**Choix d'exposition** : ce service passe par le tunnel public, contrairement aux autres services privés. Un canal d'alerte joignable seulement lorsque le VPN est actif manquerait précisément les moments où il est utile. Le trafic se limite à quelques centaines d'octets de texte.

**Contrepartie obligatoire** : accès fermé par défaut (`deny-all`). Sans cela, un service de notification exposé publiquement devient un relais ouvert utilisable par n'importe qui.

**Cloisonnement des comptes** :
- un compte administrateur pour les clients (téléphone, navigateur) ;
- un compte distinct pour Grafana, en **écriture seule** sur le seul sujet concerné, authentifié par jeton. Grafana ne peut donc pas lire les notifications ni écrire ailleurs.

Le jeton vit dans le fichier d'environnement de Grafana et est référencé par `$__env{...}` dans le fichier de provisionnement : aucun secret n'entre dans le dépôt.

### Mise en forme des notifications

Grafana émet systématiquement un corps JSON complet. Publié tel quel, il produit une notification illisible sur téléphone. Le mode *template* de ntfy résout le problème : les paramètres de requête de l'URL du point de contact interprètent ce JSON et n'en retiennent que le titre et le message, déjà mis en forme par Grafana.

### Vérification de bout en bout

Utiliser le bouton **Test** du point de contact dans l'interface Grafana : ce chemin emprunte le jeton provisionné et valide toute la chaîne sans manipulation de secret.

À noter : une publication lancée depuis le serveur sans identifiants renvoie un refus (`403`). Ce n'est pas une panne mais la preuve que la fermeture par défaut fonctionne.

## Consommation constatée au déploiement

Charge très faible sur le serveur (quelques pourcents de CPU, environ 1,5 Go de mémoire pour l'ensemble de la stack, disque système occupé à quelques pourcents) : marge confortable pour d'éventuels services supplémentaires.
