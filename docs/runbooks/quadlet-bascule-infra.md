# Runbook — Bascule Quadlet : niveau Infra (Cloudflare Tunnel + Twingate)

Dernière bascule de la migration (Étape 5). Ces deux services constituent **la ligne de vie de l'accès distant** : leur arrêt coupe tout accès hors du réseau local.

## Règle absolue

Bascule uniquement dans une fenêtre avec **accès local physique** au serveur (ou à défaut, sur le LAN). Si un tunnel ne remonte pas, la correction ne peut se faire que localement.

## Principe : un tunnel à la fois

Twingate d'abord, validation complète, **puis** Cloudflare. Jamais les deux simultanément : tant qu'un des deux chemins d'accès fonctionne, le serveur reste joignable à distance en cas de problème sur l'autre.

## Prérequis (bloquants)

1. Sauvegarde fraîche vérifiée (`scripts/backup.sh` + `gunzip -t`).
2. `infra/cloudflared.env` et `infra/twingate.env` créés depuis les templates, `chmod 600`, validés par `scripts/check-env.sh`.
   - Point d'attention : la variable du tunnel Cloudflare porte désormais son **nom final** (`TUNNEL_TOKEN`) ; compose effectuait ce renommage à la volée, l'`EnvironmentFile=` Quadlet non.
3. Unités copiées + `quadlet -dryrun -user` sans erreur + `daemon-reload`.

## Bascule Twingate

```bash
podman stop twingate-connector && podman rm twingate-connector
systemctl --user start twingate-connector
podman inspect twingate-connector --format '{{.NetworkSettings.Networks.homelab_net.IPAddress}}'
```

L'**IP statique doit être identique** à celle de la configuration compose (`IP=` dans l'unité) : les ressources Twingate ciblent cette adresse, un changement casserait les accès.

Validation : depuis un appareil en **données mobiles** (pas le Wi-Fi local — sinon le test ne traverse pas réellement le tunnel), se connecter via le client Twingate et atteindre une ressource interne.

## Bascule Cloudflare Tunnel

Uniquement après validation de Twingate.

```bash
podman stop cloudflare-tunnel && podman rm cloudflare-tunnel
systemctl --user start cloudflared
journalctl --user -u cloudflared -n 15 --no-pager   # « Registered tunnel connection »
```

Validation : depuis un appareil en données mobiles, accès HTTPS aux services publiés (gestionnaire de mots de passe, budget) — connexion et synchronisation.

## Rollback (identique pour les deux)

```bash
systemctl --user stop <service>
rm ~/.config/containers/systemd/<service>.container
systemctl --user daemon-reload
podman-compose -f ~/homelab/infra/compose.yml up -d
```

## Correctif appliqué au passage : healthcheck PostgreSQL

Le healthcheck de l'Étape 4 générait un FATAL bénin à chaque sonde. Deux causes successives, corrigées l'une après l'autre :

1. `pg_isready -q` sans `-U` → sonde exécutée en root dans le conteneur → `FATAL: role "root" does not exist`.
   Correction : `-U $$POSTGRES_USER` (l'échappement systemd `$$` produit un `$` à l'exécution, résolu depuis l'`EnvironmentFile`).
2. Avec `-U` mais sans `-d`, `pg_isready` vise une base **homonyme de l'utilisateur** (comportement par défaut peu connu) → `FATAL: database "<utilisateur>" does not exist`.
   Correction finale : `-U $$POSTGRES_USER -d $$POSTGRES_DB`.

Résultat : zéro FATAL sur une fenêtre d'observation, et la sonde vérifie désormais quelque chose de plus utile — non pas « le serveur répond » mais « le serveur répond **et** la base applicative est joignable ».

## Leçons retenues

- Migrer les composants d'accès distant **un par un**, jamais en lot : la redondance des chemins d'accès est le filet de sécurité.
- Toujours tester depuis un réseau extérieur (données mobiles) : un test depuis le LAN ne prouve pas que le tunnel fonctionne.
- Les renommages de variables que compose effectuait implicitement doivent être rendus explicites dans les fichiers env par service.
- Vérifier les valeurs d'infrastructure figées (IP statique) **après** bascule, pas seulement dans le fichier d'unité.
