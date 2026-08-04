---
description: Valide et déploie un service du homelab via son unité Quadlet (infra, data ou apps).
---

# Workflow : Déploiement d'un Service Homelab (Quadlet)

**Description :** Valide et déploie un service décrit par une unité Quadlet versionnée dans son niveau (`infra/quadlet/`, `data/quadlet/` ou `apps/quadlet/`).

> Les fichiers `compose.yml` sont conservés comme solution de repli uniquement. Toute évolution passe par les unités Quadlet.

## Étapes de Validation

1. Identifier le niveau concerné (`infra/`, `data/` ou `apps/`) et les unités associées (`.container`, `.volume`).
2. **Vérification Architecturale :**
    - Toutes les images doivent porter le préfixe `docker.io/` et une **version épinglée** (jamais `latest`), sans que ces versions apparaissent dans la documentation générale (diagrammes Mermaid de `docs/`).
    - La persistance doit utiliser exclusivement des volumes nommés Podman, déclarés par une unité `.volume` avec `VolumeName=` suivant le standard `<niveau>_<service>_data` (aucun montage direct de l'hôte pour les données actives).
    - Le réseau doit être `homelab.network` (réseau partagé `homelab_net`) ; jamais `network_mode: host`, jamais de port publié.
    - Les dépendances entre niveaux doivent être exprimées par `Requires=`/`After=` (ordre `data` → `apps`), et un service dont d'autres dépendent doit exposer un healthcheck avec `Notify=healthy`.
3. **Secrets :**
    - Un fichier env par service (`<niveau>/<service>.env`), consommé par `EnvironmentFile=`, accompagné d'un `<service>.env.example` versionné.
    - Valeurs **finales** dans le fichier env : ni quotes, ni échappement `$$`, ni placeholders — contrairement aux conventions compose.
    - Vérifier avec `scripts/check-env.sh <fichier>` et s'assurer des permissions `600`.
4. **Audit de Sécurité** (dépôt public) :
    - Scanner tous les fichiers modifiés à la recherche de secrets, d'identifiants réels, de noms de domaine, d'adresses IP du réseau local ou d'empreintes système.
    - Se référer à la classification secrets / valeurs identifiantes / constantes structurelles de `.agents/rules/homelab-devops.md`.
5. **Sauvegarde préalable** (tout service manipulant des données existantes) : exécuter `scripts/backup.sh` et vérifier l'intégrité de l'archive produite avant toute bascule.
6. Préparer le message de commit en français (format Conventional Commits) et le soumettre à validation explicite de l'utilisateur avant tout `git commit`.

## Déploiement

```bash
git pull
cp <niveau>/quadlet/<service>.* ~/.config/containers/systemd/
/usr/libexec/podman/quadlet -dryrun -user      # validation AVANT activation
systemctl --user daemon-reload
systemctl --user start <service>
systemctl --user status <service> --no-pager
podman ps
```

Vérifier ensuite l'accès applicatif depuis un réseau extérieur (le trafic devant traverser le tunnel) et, pour les services persistants, que `scripts/backup.sh` couvre bien leur volume.

## Rollback

```bash
systemctl --user stop <service>
rm ~/.config/containers/systemd/<service>.*
systemctl --user daemon-reload
podman-compose -f <niveau>/compose.yml up -d   # repli historique, si applicable
```

Le volume nommé n'est jamais supprimé par un rollback : les données sont conservées.

## Précautions

- Ne jamais migrer plusieurs composants d'accès distant (tunnels) simultanément : un chemin d'accès doit rester fonctionnel.
- Toute bascule touchant le niveau `infra` exige un accès local physique au serveur.
- `systemctl --user disable --now podman-restart.service` arrête les conteneurs en cours (`ExecStop`) : utiliser `disable` seul pour retirer une unité du démarrage sans interrompre le service.
