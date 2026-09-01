# Homelab — Infrastructure as Code

## Contexte

Ce dépôt documente la migration en conditions réelles d'un homelab personnel : d'une orchestration `podman-compose` classique vers des unités **Quadlet** (systemd natif de Podman), en conservant une posture **rootless** et **Zero Trust** de bout en bout (aucun port entrant, tout le trafic sortant via Cloudflare Tunnel et Twingate).

## Démarche

La migration a suivi un principe simple : **jamais de remplacement direct**. Chaque service a été migré en parallèle de l'existant, validé, puis basculé — avec un chemin de retour (`rollback`) disponible à chaque étape. L'ordre a suivi le rayon d'impact croissant : un pilote greenfield sans risque (un nouveau service sans données existantes), puis les applications, la base de données, et enfin l'infrastructure réseau — la ligne de vie de l'accès distant, migrée en dernier et uniquement avec un accès physique local.

Le détail complet de cette feuille de route est disponible dans le [plan de migration](quadlet-migration-plan.md).

## Incidents réels et résolutions

Un projet d'infrastructure documenté honnêtement inclut ses erreurs. Trois incidents distincts partagent la même famille de cause — un échec silencieusement déclaré comme un succès — et leur découverte progressive illustre une méthode de diagnostic plutôt qu'une simple liste de correctifs :

- **Sauvegardes inopérantes depuis une réinstallation** (chemin de sauvegarde erroné, permissions du point de montage, nommage de volume incorrect, aucune planification) — découvert par un audit d'inventaire avant même de commencer la migration proprement dite.
- **Volume applicatif vide sauvegardé comme « réussi »** — le préfixe de nommage imposé par l'orchestrateur précédent n'était pas répercuté dans le script de sauvegarde.
- **Pipeline shell masquant un échec** — le code de retour d'un pipeline ne reflétant que son dernier maillon, une commande échouée produisait malgré tout une archive (vide) déclarée valide.

Chaque incident a été corrigé, testé (restauration réelle sur une instance jetable), puis transformé en garde-fou automatisé plutôt qu'en simple correction ponctuelle — voir le [runbook des sauvegardes](runbooks/sauvegardes-verification-restauration.md).

## État actuel

Huit services tournent sous Quadlet, rootless, avec :

- des sauvegardes quotidiennes automatisées, à l'échec bruyant et à la restauration testée ;
- une supervision Prometheus/Grafana couvrant l'hôte, les conteneurs — et la sauvegarde elle-même ;
- des alertes acheminées vers un canal de notification dédié ;
- un modèle de moindre privilège pour l'accès aux données (rôle applicatif dédié, non-superuser) ;
- un test de redémarrage complet validé (reprise automatique dans le bon ordre au démarrage).

## Runbooks

- [Sauvegardes : vérification et restauration](runbooks/sauvegardes-verification-restauration.md)
- [Pilote Quadlet : Actual Budget](runbooks/quadlet-pilote-actual-budget.md)
- [Bascule : Vaultwarden](runbooks/quadlet-bascule-vaultwarden.md)
- [Bascule : PostgreSQL et moindre privilège](runbooks/quadlet-bascule-postgres.md)
- [Bascule : infrastructure réseau](runbooks/quadlet-bascule-infra.md)
- [Réseau Hôte : Twingate (Zero Trust)](runbooks/quadlet-twingate-host.md)
- [Service Git : Forgejo](runbooks/quadlet-forgejo.md)
- [Service Git : Forgejo Runner (CI/CD)](runbooks/quadlet-forgejo-runner.md)
- [Portail d'accueil : Glance Dashboard](runbooks/quadlet-glance.md)
- [Machine Virtuelle : Windows 11](runbooks/quadlet-windows.md)
- [Observabilité](runbooks/observabilite.md)