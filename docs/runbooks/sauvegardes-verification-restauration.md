# Runbook — Sauvegardes : vérification d'intégrité et restauration de test

## Répartition des données (Vaultwarden avec backend PostgreSQL)

| Données | Emplacement | Criticité |
|---|---|---|
| Coffres, utilisateurs, organisations | PostgreSQL (`vwarden_db`) | Vitale — couverte par `pg_dumpall` |
| Pièces jointes des entrées | Volume `/data/attachments/` | **Irremplaçable** — hors DB |
| Fichiers Bitwarden Send | Volume `/data/sends/` | Irremplaçable — hors DB |
| Clés RSA (signature des jetons de session) | Volume `/data/rsa_key*` | Perte = déconnexion de tous les appareils |
| Cache de favicons | Volume `/data/icon_cache/` | Jetable |

Conclusion : la sauvegarde du volume reste nécessaire même avec un backend PostgreSQL.

## Vérification d'intégrité — trois niveaux

**Niveau 1 — Intégrité de compression** (silence = succès) :
```bash
gunzip -t <dump>.sql.gz
tar -tzf <archive>.tar.gz > /dev/null && echo OK
```

**Niveau 2 — Complétude du contenu** :
```bash
# Le dump doit se terminer par le marqueur de fin pg_dumpall :
zcat <dump>.sql.gz | tail -3      # attendu : "-- PostgreSQL database cluster dump complete"
# L'archive doit contenir les fichiers critiques :
tar -tzf <archive>.tar.gz | grep rsa_key
```

**Niveau 3 — Restauration de test (référence)** — prouve que la sauvegarde est *restaurable*, pas seulement lisible :
```bash
# Instance PostgreSQL jetable, isolée (PAS sur homelab_net)
# Utiliser exactement la même image/version que data/compose.yml (source de vérité)
podman run --rm -d --name pg-restore-test -e POSTGRES_PASSWORD=testonly <image PostgreSQL de data/compose.yml>
sleep 5
zcat <dump>.sql.gz | podman exec -i pg-restore-test psql -U postgres
podman exec pg-restore-test psql -U postgres -l                                   # vwarden_db présent ?
podman exec pg-restore-test psql -U postgres -d vwarden_db -c "SELECT count(*) FROM users;"
podman stop pg-restore-test
```
Erreurs « role already exists » attendues et bénignes lors d'une restauration sur instance vierge partielle.
Vérification réussie le 2026-08-03 : base recréée, tables chargées, nombre d'utilisateurs conforme.

## Incident du 2026-08-03 — sauvegardes inopérantes après réinstallation

**Symptôme** : aucune sauvegarde présente sur le disque externe depuis la réinstallation du serveur (juillet 2026).

**Causes cumulées** :
1. `BACKUP_DIR` dans `data/.env` pointait vers un chemin de la machine de développement (fichier copié tel quel) — chemin inexistant sur le serveur.
2. Le point de montage du disque externe appartenait à `root` : l'utilisateur rootless ne pouvait pas y écrire.
3. `scripts/backup.sh` référençait le volume `vaultwarden_data` sans le préfixe ajouté par podman-compose (`apps_vaultwarden_data`) : Podman créait silencieusement un volume vide et produisait une archive de 87 octets ne contenant aucune donnée.
4. Aucune planification (ni cron, ni timer systemd) n'avait été mise en place.

**Corrections appliquées** :
1. `BACKUP_DIR` corrigé vers le point de montage du disque externe.
2. `chown` du point de montage vers l'utilisateur rootless.
3. Volume préfixé corrigé dans `backup.sh` + suppression du volume vide parasite (`podman volume rm`).
4. Planification via timer systemd utilisateur (`scripts/systemd/backup.{service,timer}`), quotidien à 03h30, `Persistent=true` (rattrapage si serveur éteint). Vérification : `systemctl --user list-timers backup.timer` et `journalctl --user -u backup.service`.

**Leçons retenues** :
- Une sauvegarde non testée en restauration n'est pas une sauvegarde (vérification niveau 3 désormais dans ce runbook).
- Les fichiers `.env` copiés entre machines doivent être revus valeur par valeur.
- Toute tâche critique doit être planifiée et journalisée (timer systemd + journalctl), jamais laissée à l'exécution manuelle.
- Les noms de volumes podman-compose sont préfixés : toujours vérifier avec `podman volume ls` avant tout script les référençant.

## Améliorations futures retenues

- [ ] Rôle PostgreSQL dédié non-superuser par application (moindre privilège OWASP) — prévu lors de la migration du niveau Data (voir plan Quadlet, Étape 4).
- [x] Étendre `backup.sh` aux volumes des futurs services — fait pour Actual Budget (données SQLite, l'application ne supporte pas PostgreSQL), avec garde-fou `podman volume exists`. Standard de nommage adopté : `<tier>_<service>_data`, le garde-fou et l'archive devant référencer exactement le même nom.
- [ ] Alerte en cas d'échec de `backup.service` (`OnFailure=` vers une unité de notification) — à étudier avec l'observabilité (Étape 7).
