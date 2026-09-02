# Runbook — GitOps & Renovate : Déploiement Continu Automatique

Ce runbook documente la chaîne complète de mise à jour automatisée des services du homelab : de la détection de nouvelles versions d'images conteneurisées jusqu'au déploiement sécurisé et ciblé sur le serveur sans intervention manuelle en SSH.

---

## 1. Vue d'ensemble de la chaîne GitOps

```
┌────────────────────────┐      ┌─────────────────────────┐      ┌─────────────────────────┐
│  Docker Hub / Registry │ ───> │  Renovate Bot (GitLab)  │ ───> │  Merge Request (GitLab) │
└────────────────────────┘      └─────────────────────────┘      └─────────────────────────┘
                                                                              │
                                                                   Validation humaine (Merge)
                                                                              │
                                                                              ▼
┌────────────────────────┐      ┌─────────────────────────┐      ┌─────────────────────────┐
│ Notification (ntfy)    │ <─── │ Déploiement ciblé (sync)│ <─── │ homelab-sync.timer (30m)│
└────────────────────────┘      └─────────────────────────┘      └─────────────────────────┘
```

1. **Veille & Détection (Renovate) :** Renovate analyse périodiquement les unités Quadlet (`.container`) du dépôt.
2. **Proposition (GitLab MR) :** Lorsqu'une nouvelle version stable est publiée, une Merge Request est automatiquement créée avec son journal des modifications (*Changelog*).
3. **Validation :** L'administrateur valide la mise à jour en fusionnant la MR sur la branche `main`.
4. **Déploiement Continu (Serveur) :** Le service systemd utilisateur `homelab-sync.timer` détecte le nouveau commit, synchronise le dépôt, applique le fichier Quadlet ciblé dans `~/.config/containers/systemd/`, recharge systemd et redémarre uniquement le conteneur concerné.
5. **Notification :** Un message de confirmation est transmis via `ntfy`.

---

## 2. Configuration de Renovate Bot (`renovate.json`)

Le fichier `renovate.json` à la racine du projet configure le comportement de l'analyseur :

- **Prise en charge native de Quadlet :** Renovate extrait automatiquement les directives `Image=` des fichiers `.container`.
- **Politique de versionnage :** Les mises à jour de correctifs (*patch*) et mineures sont isolées. PostgreSQL est protégé contre les montées de version majeures accidentelles (`allowedVersions: "<17.0.0"`).
- **Intégration GitLab CI (`.gitlab-ci.yml`) :** L'exécution est programmée via une tâche planifiée (*Pipeline Schedule*) exécutant l'image officielle `renovate/renovate:latest`.

---

## 3. Mécanisme de Synchronisation Ciblée (`scripts/homelab-sync.sh`)

Le script applique le principe de **moindre privilège et de rayon d'impact minimal (*Blast Radius*)** :

- **Comparaison de hash Git :** `git fetch` et comparaison `HEAD` vs `origin/main`. Si aucun commit n'est présent, le script s'arrête immédiatement (0 ressource consommée).
- **Ciblage strict des fichiers modifiés :** Seuls les fichiers `.container`, `.volume` ou `.network` apparaissant dans `git diff` sont copiés vers `~/.config/containers/systemd/`. Les autres services ne sont ni écrasés ni modifiés.
- **Rechargement conditionnel :** `systemctl --user daemon-reload` n'est invoqué que si une unité Quadlet a effectivement changé.
- **Redémarrage chirurgical :** Seul le conteneur impacté est redémarré (`systemctl --user restart <service>`).

---

## 4. Déploiement et Administration sur l'Hôte

### Fichiers d'unité systemd (utilisateur)

- `scripts/systemd/homelab-sync.service` : unité *oneshot* appelant le script de synchronisation.
- `scripts/systemd/homelab-sync.timer` : planification toutes les 30 minutes (`OnUnitActiveSec=30min`) et 10 minutes après le démarrage (`OnBootSec=10min`).

### Activation initiale sur le serveur

```bash
cd ~/homelab && git pull origin main
cp scripts/systemd/homelab-sync.{service,timer} ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now homelab-sync.timer
```

---

## 5. Commandes de Vérification et Diagnostic

| Action | Commande |
|---|---|
| Vérifier l'état du timer | `systemctl --user list-timers homelab-sync.timer` |
| Exécuter une synchronisation manuelle | `systemctl --user start homelab-sync.service` |
| Consulter les journaux de synchronisation | `journalctl --user -u homelab-sync.service -n 50 --no-pager` |
| Vérifier les statuts des conteneurs après sync | `systemctl --user is-active <service>` |
