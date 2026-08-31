# Runbook — Quadlet : Déploiement du Runner Forgejo Actions (CI/CD)

Ce runbook décrit le déploiement et l'exploitation de **Forgejo Runner**, l'agent qui exécute les pipelines CI/CD de Forgejo Actions, sous forme d'unité Quadlet systemd rootless.

## Fichiers IaC impliqués

| Fichier (dépôt) | Rôle |
|---|---|
| `apps/quadlet/forgejo-runner.container` | Unité conteneur Quadlet (image `data.forgejo.org/forgejo/runner:3.5.0`) |
| `apps/quadlet/forgejo-runner.volume` | Volume nommé `apps_forgejo_runner_data` (persistance du fichier `.runner` et config) |
| `apps/forgejo-runner.env.example` | Modèle de variables d'environnement (Token, URL, Labels) |
| `apps/ci/Containerfile` | Recette de construction de l'image locale d'exécution CI (`localhost/homelab-ci:latest`) |

## Spécificités d'Architecture (Zero Trust)

Conformément à nos règles de sécurité :
1. **Image locale dédiée (`homelab-ci`) :** Pour respecter la posture Zero Trust et éviter les risques de supply chain tiers, les pipelines s'exécutent dans une image construite localement depuis `node:20-bookworm-slim` avec les outils de validation préinstallés (`git`, `curl`, `python3`, `shellcheck`, `mkdocs-material`).
2. **Accès au Socket Podman :** Le runner a besoin de démarrer des conteneurs éphémères pour exécuter les jobs CI. Il monte le socket `/run/user/1000/podman/podman.sock`.
3. **User=0:0 :** Pour que le runner puisse accéder à ce socket (appartenant à l'hôte), le conteneur est forcé à s'exécuter en tant que root `0:0` en interne, ce qui correspond de manière sécurisée à l'utilisateur non privilégié `homelab` sur l'hôte (grâce aux *User Namespaces* de Podman rootless).
4. **Auto-enregistrement :** L'unité contient un script `Exec=` qui enregistre automatiquement le runner auprès de l'instance Forgejo s'il n'est pas encore enregistré.

## Procédure de Déploiement

### 1. Obtenir un jeton d'enregistrement (Registration Token)
Avant de lancer le runner, il faut générer un jeton d'enregistrement global depuis le serveur hébergeant Forgejo :
```bash
podman exec -u git forgejo forgejo forgejo-cli actions generate-runner-token
```

### 2. Construire l'image locale d'exécution CI
```bash
podman build -t localhost/homelab-ci:latest apps/ci/
```

### 3. Configuration
Copiez le modèle et insérez le jeton :
```bash
cp apps/forgejo-runner.env.example apps/forgejo-runner.env
nano apps/forgejo-runner.env
```
Ajoutez :
```env
FORGEJO_URL=http://forgejo:3000
FORGEJO_TOKEN=votre_jeton_ici
FORGEJO_RUNNER_NAME=homelab-runner
FORGEJO_RUNNER_LABELS=docker:docker://localhost/homelab-ci:latest,ubuntu-latest:docker://localhost/homelab-ci:latest,ubuntu-22.04:docker://localhost/homelab-ci:latest
```

### 4. Déploiement
```bash
mkdir -p ~/.config/containers/systemd
cp apps/quadlet/forgejo-runner.{container,volume} ~/.config/containers/systemd/
cp apps/forgejo-runner.env ~/homelab/apps/forgejo-runner.env

systemctl --user daemon-reload
systemctl --user restart forgejo-runner
systemctl --user status forgejo-runner --no-pager
```

## Vérification

Pour vérifier que le runner est bien connecté et prêt à recevoir des tâches :
```bash
journalctl --user -u forgejo-runner.service | grep -v "systemd" | tail -n 10
```
Vous devriez y voir `Starting runner daemon` et `[poller 0] launched`.

## Rollback

```bash
systemctl --user stop forgejo-runner
rm ~/.config/containers/systemd/forgejo-runner.{container,volume}
systemctl --user daemon-reload
```
