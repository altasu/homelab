# Architecture Homelab — Vue d'ensemble

Stack de production actuelle : Podman rootless, 3 niveaux (`infra/` → `data/` → `apps/`), réseau partagé `homelab_net`, posture Zero Trust (aucun port entrant, tunnels sortants uniquement).

```mermaid
flowchart TB
    user(["Utilisateur / User"])
    cf["Cloudflare<br>(CDN + Zero Trust)"]
    tg["Twingate<br>(Zero Trust Network)"]

    user -->|"HTTPS"| cf
    user -->|"VPN Zero Trust<br>(Cockpit, SSH)"| tg

    subgraph server["Serveur Homelab — Podman rootless"]
        subgraph infra["Stage 1 : Core Infra (infra/) — NE JAMAIS ARRÊTER"]
            cloudflared["cloudflared"]
            twingate["twingate-connector"]
        end
        subgraph apps["Stage 3 : Apps (apps/)"]
            vw["Vaultwarden"]
            ab["Actual Budget (prévu)"]
        end
        subgraph data["Stage 2 : Data (data/) — LE PLUS CRITIQUE"]
            pg[("PostgreSQL")]
        end
        net{{"Réseau partagé<br>homelab_net"}}
    end

    cloudflared -.->|"Tunnel sortant (outbound)"| cf
    twingate -.->|"Tunnel sortant (outbound)"| tg

    cloudflared --- net
    twingate --- net
    vw --- net
    ab --- net
    pg --- net

    cloudflared -.->|"http://vaultwarden:80"| vw
    vw -.->|"postgres-db:5432"| pg
```

## Principes

- **Zéro port entrant** : tout le trafic passe par des tunnels sortants chiffrés (Cloudflare Tunnel, Twingate).
- **Rootless Podman** : aucun privilège root pour les conteneurs.
- **Secrets isolés** : chaque niveau possède son propre `.env` (jamais versionné).
- **Versions épinglées** : les images sont figées dans les fichiers d'orchestration ; les versions précises ne sont pas exposées dans les diagrammes publics.
- **Ordre de déploiement obligatoire** : `infra` → `data` → `apps`.

## Stratégie d'Architecture des Bases de Données (Modèle Hybride)

Le homelab adopte une approche hybride d'organisation des bases de données selon les besoins des services :

1. **SQLite embarqué par service (`apps_<service>_data`)** :
   - Utilisé pour Forgejo, Actual Budget, ntfy.
   - **Avantages** : empreinte mémoire nulle (0 MB RAM de daemon), isolation totale du rayon d'impact (blast radius), persistance autonome dans le Named Volume Quadlet et restauration 1:1 sans dépendance réseau.
2. **PostgreSQL centralisé (Niveau `data/`)** :
   - Réservé aux applications à fortes transactions ou multi-utilisateurs complexes (Vaultwarden).
   - **Sécurité** : application stricte du principe du moindre privilège OWASP (rôle application dédié non-superuser par base de données, pas d'accès global).

> **Migration en cours** : l'orchestration `podman-compose` évolue vers Quadlet (unités systemd utilisateur) — voir [quadlet-migration-plan.md](quadlet-migration-plan.md).
