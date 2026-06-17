---
description: Valide et prépare un niveau spécifique (infra, data ou apps) pour le déploiement.
---

# Workflow : Déploiement de Niveau Homelab

**Description :** Valide et prépare un niveau spécifique (infra, data ou apps) pour son déploiement.

## Étapes de Validation
1. Naviguer vers le répertoire du niveau demandé (`infra/`, `data/` ou `apps/`).
2. Valider la syntaxe du fichier `compose.yml`.
3. Vérifier que le réseau `homelab_net` est déclaré comme externe. Si absent, s'assurer que la commande de création existe : `podman network create homelab_net`.
4. **Vérification Architecturale :**
    - S'assurer que toutes les images utilisées dans le fichier `compose.yml` ont le préfixe `docker.io/`.
    - Vérifier que la persistance utilise exclusivement des Volumes Nommés Podman (Named Volumes) et aucun montage direct sur l'hôte (host bind mounts) pour les bases de données actives.
    - S'assurer que les versions des images dans `compose.yml` sont figées (pas de tag `latest`), mais que ces versions ne sont **pas** exposées dans les fichiers de documentation générale comme `homelab.wsd` (pour éviter la fuite d'informations).
5. S'assurer qu'un fichier `.env.example` existe dans le répertoire et que les fichiers `.env` et de sauvegarde de test (ex: `backups/`) sont ignorés dans le fichier `.gitignore` racine.
6. **Audit de Sécurité :**
    - Scanner tous les fichiers modifiés (ex: `compose.yml`, scripts, diagrammes) à la recherche de mots de passe codés en dur, de jetons, de clés d'API, de noms de domaine exacts ou de chemins absolus de l'hôte.
    - S'assurer que les secrets sont encapsulés via des variables d'environnement (`${VARIABLE_NAME}`).
    - **Validation Encodage :** Si un mot de passe dans un fichier `.env` local contient des caractères spéciaux réservés, vérifier que la variable `DATABASE_URL` les encode correctement en URL (percent-encoding) ou proposer de simplifier le mot de passe local en caractères alphanumériques.
7. Appeler la compétence `git-commits-fr` pour préparer le message de validation de validation de commit en français.
8. **Pré-requis du Déploiement :**
    - Vérifier que le réseau partagé existe sur la machine : `podman network inspect homelab_net || podman network create homelab_net`.
    - Respecter l'ordre de déploiement strict : `infra` -> `data` -> `apps`. Si le niveau `apps` est déployé, s'assurer que `data` et `infra` sont déjà actifs.
9. **Exécution :** Exécuter la commande `podman-compose -f <stage>/compose.yml up -d` pour le niveau concerné. Valider le statut avec `podman ps`.
