---
trigger: always_on
---

# Architecture Homelab Zero Trust

## Contraintes d'Infrastructure
- Le projet utilise Podman (rootless/daemonless), et NON Docker standard. Les images doivent utiliser le préfixe `docker.io/` pour éviter les erreurs de résolution de nom court.
- Le projet est strictement divisé en trois niveaux (3-tier) : `infra`, `data` et `apps`.
- Les conteneurs DOIVENT communiquer uniquement via le réseau externe nommé `homelab_net`.
- Le mode réseau hôte (`network_mode: host`) est strictement interdit pour maintenir l'isolation.

## Persistance des Données
- Les bases de données et les applications DOIVENT utiliser exclusivement des Volumes Nommés Podman (Named Volumes) pour maximiser les performances I/O et éviter les problèmes de permissions UID/SELinux rootless sur les répertoires hôtes.
- Les sauvegardes de ces volumes nommés DOIVENT être effectuées via des scripts automatisés (ex: `scripts/backup.sh`) générant des dumps logiques (comme `.sql.gz`) et les stockant sur un support externe. Les montages directs (bind mounts) de l'hôte pour les bases de données actives sont strictement interdits.
- En cas de changement de mot de passe de base de données en environnement local/test, le volume nommé contenant les données existantes de PostgreSQL doit être supprimé (`podman volume rm`) afin de permettre la réinitialisation de l'instance avec les nouveaux identifiants.
- Les scripts shell devant charger des variables depuis un fichier `.env` doivent utiliser une résolution de chemin absolue basée sur le répertoire du script lui-même (`SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`) pour éviter les dépendances liées au répertoire de travail courant du shell.

## Gestion des Secrets
- Aucun secret ni jeton (ex: Twingate, Cloudflare, PostgreSQL) ne doit être codé en dur. Ils doivent être stockés dans des fichiers `.env` situés dans leurs répertoires de niveau respectifs.
- Chaque répertoire contenant un fichier `compose.yml` DOIT inclure un fichier `.env.example`.
- Le fichier `.env` et les répertoires de sauvegardes de test locaux (ex: `/backups`) DOIVENT être ignorés par Git via le fichier `.gitignore` à la racine.
- **Encodage de mot de passe :** Si un mot de passe de base de données contient des caractères spéciaux (notamment `%`, `@`, `:`, `/`, `?`, `#`), il doit être encodé en URL (percent-encoding) dans la chaîne `DATABASE_URL` (requis par le parseur Diesel de Vaultwarden) ou limité à des caractères alphanumériques simples.

## Audit de Sécurité
- L'exposition d'informations sensibles codées en dur est interdite :
  * Pas de noms de domaine exacts dans les configurations Git (utiliser des variables comme `${DOMAIN}` ou des placeholders génériques).
  * Pas de chemins d'hôte absolus (sauf pour les points de montage spécifiques des disques externes dans les scripts de sauvegarde).
  * Pas de mots de passe ou clés d'API en clair dans le dépôt Git.
  * Pas de numéros de version précis des images de conteneurs dans les schémas d'architecture et documentations publiques (ex: fichiers PlantUML `homelab.wsd`) afin d'éviter la divulgation d'informations de sécurité facilitant la recherche de vulnérabilités (CVE).

## Cycle de Vie du Déploiement
- Tous les niveaux DOIVENT partager le réseau externe `homelab_net`.
- Ordre de déploiement obligatoire : `infra` -> `data` -> `apps`.
- Commande de déploiement : `podman-compose -f <stage>/compose.yml up -d`.
- Vérifier que le réseau partagé existe avant le déploiement : `podman network inspect homelab_net || podman network create homelab_net`.
