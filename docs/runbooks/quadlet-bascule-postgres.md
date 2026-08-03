# Runbook — Bascule Quadlet : PostgreSQL + moindre privilège (Étape 4)

Bascule du niveau Data en **deux phases distinctes** — une seule chose change à la fois :
- **Phase A** : changement d'orchestrateur uniquement (même image épinglée, mêmes identifiants).
- **Phase B** : passage de l'application au rôle non-superuser (une fois A validée).

## Phase A — Bascule d'orchestrateur

Prérequis bloquants exécutés : sauvegarde fraîche vérifiée (`gunzip -t`), `data/postgres.env` créé (valeurs **brutes**, sans percent-encoding — celui-ci ne concerne que les URL) et validé par `scripts/check-env.sh`.

```bash
cp data/quadlet/postgres.{container,volume} ~/.config/containers/systemd/
cp apps/quadlet/vaultwarden.container ~/.config/containers/systemd/   # dépendance Requires=/After=postgres.service
/usr/libexec/podman/quadlet -dryrun -user
systemctl --user daemon-reload
systemctl --user stop vaultwarden            # le dépendant s'arrête AVANT la base
podman stop postgres-db && podman rm postgres-db
podman pod rm pod_data                       # pod compose résiduel, vidé par le retrait du conteneur
systemctl --user start postgres              # attend le healthcheck (Notify=healthy)
systemctl --user start vaultwarden
```

**Preuves de succès** : log PostgreSQL « database directory appears to contain a database; **Skipping initialization** » (volume existant réutilisé, données intactes) ; conteneur `Up (healthy)` ; connexions applicatives visibles dans la liste des processus postgres.

### Observation : bruit `FATAL: role "root" does not exist`

Le healthcheck `pg_isready -q` s'exécute en tant que root dans le conteneur et, sans `-U`, tente le rôle « root ». `pg_isready` considère malgré tout le serveur comme joignable (c'est son contrat : accessibilité, pas authentification) — le healthcheck fonctionne donc, mais chaque sonde écrit une ligne FATAL bénigne dans le journal. **Correctif planifié à l'Étape 5** (prochain redémarrage naturel) : passer `-U` via l'échappement systemd `$$POSTGRES_USER`, à valider au dry-run.

## Phase B — Rôle applicatif à moindre privilège (OWASP)

Motivation : l'application se connectait avec le superuser PostgreSQL. Compromission de l'app = contrôle total de l'instance (toutes les bases futures incluses). Le rôle dédié limite le rayon d'action à `vwarden_db`.

```sql
CREATE ROLE vaultwarden_app LOGIN PASSWORD '<mot de passe fort>';
ALTER DATABASE vwarden_db OWNER TO vaultwarden_app;
\c vwarden_db
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT tablename FROM pg_tables WHERE schemaname = 'public'
  LOOP EXECUTE format('ALTER TABLE public.%I OWNER TO vaultwarden_app', r.tablename); END LOOP;
  FOR r IN SELECT sequencename FROM pg_sequences WHERE schemaname = 'public'
  LOOP EXECUTE format('ALTER SEQUENCE public.%I OWNER TO vaultwarden_app', r.sequencename); END LOOP;
END $$;
```

**Pourquoi le transfert de propriété (et pas de simples GRANT)** : les migrations de schéma des futures versions de Vaultwarden exécutent des `ALTER TABLE`, opération réservée au propriétaire. Des GRANT DML seuls casseraient la première montée de version.

Vérifications : `\dt` → Owner = `vaultwarden_app` sur toutes les tables ; `\du` → le rôle n'a **aucun** attribut (ni Superuser, ni Create DB, ni Create role).

Puis côté application : mise à jour du couple utilisateur/mot de passe dans la `DATABASE_URL` de `apps/vaultwarden.env`, validation `check-env.sh`, `systemctl --user restart vaultwarden`, test d'écriture via un client.

**Mot de passe machine-à-machine** : hexadécimal long (`openssl rand -hex 24`, ~192 bits) — jamais saisi par un humain, la variété de caractères n'ajoute rien ; l'alphanumérique évite tout piège de percent-encoding dans l'URL. Si un mot de passe à caractères spéciaux est retenu malgré tout : valeur **brute** dans `CREATE ROLE`, valeur **percent-encodée** dans la `DATABASE_URL` (encoder via `urllib.parse.quote`, jamais à la main).

**Rollback B** : revenir à l'ancien couple dans la `DATABASE_URL` + restart (le superuser n'est pas supprimé). `scripts/backup.sh` continue d'utiliser le superuser via `data/.env` — inchangé.

## Modèle pour les applications futures

Chaque application partageant l'instance PostgreSQL (Keycloak, BookStack…) reçoit : sa propre base + son propre rôle propriétaire non-superuser + son propre mot de passe. Le superuser reste réservé à l'administration et aux sauvegardes.

## Leçons retenues

- `Notify=healthy` + `HealthCmd` transforme `After=postgres.service` en attente de **base réellement prête** — équivalent Quadlet d'une readiness probe Kubernetes.
- Ordre d'arrêt = inverse des dépendances : le dépendant (Vaultwarden) s'arrête avant la base.
- Ne jamais coller de sortie de terminal contenant un secret dans un canal tiers ; en cas d'exposition, **rotation immédiate** (`ALTER ROLE ... PASSWORD`) — la facilité de rotation est précisément un bénéfice du rôle applicatif dédié.
