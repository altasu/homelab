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

Quatorze conteneurs déclaratifs s'exécutent en production sous Quadlet (Podman rootless sous l'UID 1000), répartis en 3 tiers étanches (`infra/`, `data/`, `apps/`), avec :

- **Posture Zero Trust intégrale** : aucun port entrant exposé sur l'hôte, exposition publique chiffrée via Cloudflare Tunnel et accès d'administration distant via Twingate SDN ;
- **Confinement de sécurité défensif** : suppression des capacités noyau Linux (`DropCapability=ALL`), interdiction d'élévation de privilèges (`NoNewPrivileges=true`) et plafonnement systématique des ressources par Cgroups v2 (CPU et RAM) sur l'ensemble des conteneurs ;
- **Sauvegardes quotidiennes résilientes** : script automatisé (`scripts/backup.sh`) à l'échec bruyant, validation d'intégrité gzip et restauration périodique testée sur les volumes et la base PostgreSQL ;
- **Observabilité et alertes push** : supervision temps réel Prometheus/Grafana (hôte, conteneurs, état des sauvegardes) couplée à des notifications push ntfy cloisonnées par jetons et utilisateurs de service dédiés ;
- **Cycle de vie GitOps continu** : boucle de mise à jour automatisée orchestrant Renovate Bot et un minuteur systemd local (`homelab-sync.timer`).

## Guide des Runbooks

### Socle, Gouvernance & Exploitation
- [Sauvegardes : vérification d'intégrité et restauration de test](runbooks/sauvegardes-verification-restauration.md)
- [Observabilité : métriques, supervision des sauvegardes et alertes push](runbooks/observabilite.md)
- [GitOps & Déploiement continu : boucle Renovate et synchronisation systemd](runbooks/gitops-renovate-sync.md)

### Infrastructure Réseau & Tunnels
- [Bascule : infrastructure réseau (Cloudflare Tunnel & Twingate Conteneur)](runbooks/quadlet-bascule-infra.md)
- [Réseau Hôte : Connecteur Twingate Hôte (Accès Zero Trust Cockpit & SSH)](runbooks/quadlet-twingate-host.md)

### Données & Persistance
- [Bascule : PostgreSQL et politique de moindre privilège (OWASP)](runbooks/quadlet-bascule-postgres.md)

### Applications & Services Métier
- [Pilote Quadlet : Actual Budget (Gestion budgétaire)](runbooks/quadlet-pilote-actual-budget.md)
- [Bascule : Vaultwarden (Gestionnaire de mots de passe)](runbooks/quadlet-bascule-vaultwarden.md)
- [Portail d'accueil : Glance Dashboard (Agrégateur de flux & télémétrie)](runbooks/quadlet-glance.md)
- [Gestionnaire de signets : Linkding (Bookmarks souverains)](runbooks/quadlet-linkding.md)
- [Télémétrie de code : Wakapi (Statistiques WakaTime self-hosted)](runbooks/quadlet-wakapi.md)
- [Surveillance des conteneurs : Diun (Notifications de mises à jour d'images)](runbooks/quadlet-diun.md)
- [Forge logicielle : Forgejo (Serveur Git autonome)](runbooks/quadlet-forgejo.md)
- [Exécuteur CI/CD : Forgejo Runner (Actions hermétiques rootless)](runbooks/quadlet-forgejo-runner.md)
- [Virtualisation : Windows 11 VM (Station de travail KVM rootless)](runbooks/quadlet-windows.md)