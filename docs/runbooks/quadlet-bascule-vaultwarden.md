# Runbook — Bascule Quadlet : Vaultwarden (première migration d'un service existant)

Suit le modèle du pilote ([quadlet-pilote-actual-budget.md](quadlet-pilote-actual-budget.md)) avec les spécificités d'un service **avec données existantes**.

## Prérequis exécutés (dans l'ordre, bloquants)

1. **Sauvegarde fraîche vérifiée** : `backup.sh` + `gunzip -t` sur le dump PostgreSQL.
2. **Contrôle de version avant épinglage** : `podman exec vaultwarden /vaultwarden --version` sur le conteneur compose (tag `latest`) — la version épinglée dans l'unité doit être **égale ou supérieure** à la version en cours (les migrations de schéma ne sont pas réversibles). Ici : 1.37.0 en cours → 1.37.1 épinglé = mise à niveau, OK.
3. **Env par service** : `apps/vaultwarden.env` créé depuis le template (variables finales, `DATABASE_URL` assemblée), `chmod 600`.

## Bascule

```bash
cp apps/quadlet/vaultwarden.{container,volume} ~/.config/containers/systemd/
/usr/libexec/podman/quadlet -dryrun -user     # vérifier la génération AVANT d'agir
systemctl --user daemon-reload
podman stop vaultwarden && podman rm vaultwarden    # début de coupure
systemctl --user start vaultwarden                  # fin de coupure (~20 s)
journalctl --user -u vaultwarden -n 30 --no-pager   # bannière de démarrage + version
```

Vérifications : connexion web via le tunnel, ouverture + modification d'une entrée (test d'écriture DB), synchronisation desktop et mobile.

## Rollback (documenté, non nécessaire ici)

```bash
systemctl --user stop vaultwarden
rm ~/.config/containers/systemd/vaultwarden.{container,volume}
systemctl --user daemon-reload
podman-compose -f ~/homelab/apps/compose.yml up -d
```
Note : compose relancerait la version épinglée dans `apps/compose.yml` — si des migrations de schéma plus récentes ont déjà tourné, ne jamais revenir à une version antérieure.

## Constat post-bascule : ADMIN_TOKEN détecté « en clair »

Le log de démarrage signalait : `[NOTICE] You are using a plain text ADMIN_TOKEN which is insecure`.

**Cause racine** : le jeton était bien au format Argon2 PHC, mais la valeur avait été copiée depuis le `.env` compose **avec son échappement compose** (`$$` pour un `$` littéral) et des quotes. Or `podman --env-file` lit les valeurs **littéralement** : les `$$` et les quotes sont devenus partie du jeton, qui ne commençait donc plus par `$argon2id$` — d'où la détection « texte en clair ».

**Correction** : suppression des quotes et des `$` doublés dans `apps/vaultwarden.env` (aucune régénération nécessaire — le secret sous-jacent n'a jamais été exposé, pas de rotation requise), puis `systemctl --user restart vaultwarden`. NOTICE disparu du log (vérifié le 2026-08-03).

**Règle à retenir pour tout portage compose → Quadlet** : les fichiers env par service contiennent des valeurs finales *sans* quotes et *sans* échappement `$$` — l'inverse exact des conventions compose.

**Outillage** : ce contrôle est désormais automatisé par [`scripts/check-env.sh`](https://gitlab.com/altasu/homelab/-/blob/main/scripts/check-env.sh) (quotes, `$$`, placeholders `${...}`, valeurs d'exemple, permissions, formats connus — sans jamais afficher les valeurs). À exécuter sur chaque fichier env **avant toute bascule**.

## Leçons retenues

- `EnvironmentFile=` de Quadlet est passé à `podman run --env-file` : valeurs lues **littéralement** (pas d'interpolation `${...}`, pas d'échappement `$$`, quotes incluses dans la valeur si présentes). Les fichiers env par service doivent contenir des valeurs finales, sans quotes.
- Le générateur ajoute seul `Requires=/After=` vers le réseau et le volume : rien à écrire à la main.
- `podman volume create --ignore` sur un `VolumeName=` existant réutilise les données sans les toucher — vérifié (clés RSA et sessions conservées, aucune reconnexion forcée).
