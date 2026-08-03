# Runbook — Pilote Quadlet : déploiement d'Actual Budget

Premier service déployé via Quadlet (Étape 2 du plan de migration). Ce déroulé est le **modèle** des bascules suivantes (Vaultwarden, PostgreSQL, infra).

## Fichiers impliqués (IaC)

| Fichier (dépôt) | Rôle |
|---|---|
| `apps/quadlet/actual-budget.container` | Unité conteneur (image épinglée, limites de ressources) |
| `apps/quadlet/actual-budget.volume` | Volume `apps_actual_budget_data` (standard `<tier>_<service>_data`) |
| `infra/quadlet/homelab.network` | Réseau partagé (créé avec `--ignore` : l'existant est conservé) |

## Procédure de déploiement (modèle)

```bash
git pull                                             # synchroniser l'IaC
mkdir -p ~/.config/containers/systemd
cp <unités> ~/.config/containers/systemd/
/usr/libexec/podman/quadlet -dryrun -user            # validation AVANT activation
systemctl --user daemon-reload
systemctl --user start <service>
systemctl --user status <service> --no-pager         # attendu : active (running)
podman ps                                            # conteneur Up
```

Test interne sans port publié (Zero Trust : aucun accès direct) :
```bash
podman run --rm --network homelab_net docker.io/alpine:3.22 wget -qO- http://<conteneur>:<port> | head -5
```

Puis : route Cloudflare Tunnel (Public Hostname → `HTTP` / `<conteneur>:<port>`), et vérification de la sauvegarde (`scripts/backup.sh` → section du service ✅).

## Rollback

```bash
systemctl --user stop <service>
rm ~/.config/containers/systemd/<unités du service>
systemctl --user daemon-reload
```
Le volume nommé n'est **pas** supprimé par le rollback (données conservées).

## Observations utiles (dry-run du 2026-08-03)

- Le générateur Quadlet ajoute automatiquement les dépendances : `Requires=/After=homelab-network.service` et `actual-budget-volume.service` — l'ordre de démarrage est garanti sans configuration manuelle.
- `podman volume create --ignore` / `podman network create --ignore` : les objets existants sont réutilisés tels quels (bascule sans risque pour l'existant).
- Le conteneur est lancé avec `--replace --rm` : recréé proprement à chaque démarrage, l'état persistant vit exclusivement dans le volume.
- `ExecStop` exécute `podman rm -f` du conteneur : un `systemctl --user stop` nettoie complètement (pas de conteneur orphelin).
- Première synchronisation des migrations applicatives visible dans `journalctl --user -u actual-budget` (« Migrations: DONE »).

## Sécurité applicative (premier accès)

1. Définir le **mot de passe serveur** au premier accès web (le stocker dans Vaultwarden).
2. Activer le **chiffrement de bout en bout** (Settings → Encryption) : les fichiers de budget sont chiffrés au repos côté serveur. La clé E2E est distincte du mot de passe serveur — sa perte rend les données irrécupérables, la stocker aussi dans Vaultwarden.
3. Vérifier la synchronisation depuis l'application desktop et un navigateur mobile.
