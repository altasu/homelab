# Runbook — Quadlet : Réseau Hôte Twingate (Accès d'Administration Zero Trust)

Dans le cadre de l'architecture **Zero Trust**, nous utilisons deux connecteurs Twingate distincts afin de segmenter strictement les accès :

1. **`twingate-connector` (Niveau Infra / Conteneurs)** : Ce connecteur s'exécute sur le réseau Podman `homelab_net`. Il donne accès exclusivement aux services s'exécutant dans des conteneurs (ex: PostgreSQL, Vaultwarden) mais n'a **aucune route** vers l'hôte physique.
2. **`twingate-host-connector` (Niveau Hôte)** : Ce connecteur s'exécute avec le mode `Network=host`. Il donne accès aux ressources physiques du serveur (ex: Cockpit sur le port 9090, SSH sur le port 22, et le LAN local).

## Déploiement du Connecteur Hôte

### Fichiers de Configuration

- **Unité Quadlet** : `infra/quadlet/twingate-host.container`
- **Variables d'environnement** : `infra/twingate-host.env` (créé à partir de `infra/twingate-host.env.example`)

### Procédure de démarrage

Contrairement aux autres services qui dépendent du réseau Podman, ce connecteur écoute directement sur les interfaces réseau du serveur.

```bash
# 1. Copier l'unité Quadlet
cp infra/quadlet/twingate-host.container ~/.config/containers/systemd/

# 2. Informer systemd des changements
systemctl --user daemon-reload

# 3. Démarrer le connecteur (activé automatiquement au boot via WantedBy=default.target)
systemctl --user start twingate-host

# 4. Vérifier les logs
systemctl --user status twingate-host
```

## Configuration dans la console d'administration Twingate

Pour que cette séparation soit efficace, il est **impératif** de configurer Twingate correctement :

1. **Deux réseaux distants (Remote Networks)** : Vous devez créer un Remote Network distinct dans la console Twingate (ex: `Homelab-Host`). Ne placez **jamais** les deux connecteurs dans le même Remote Network, sinon Twingate tentera de faire de la répartition de charge (Load Balancing) entre les deux, rendant l'accès aléatoire.
2. **Routage des ressources** :
   - Ajoutez la ressource `192.168.x.x` (IP de l'hôte) ou `127.0.0.1` **uniquement** au Remote Network `Homelab-Host`.
   - Les autres ressources (ex: `10.89.0.x`) restent dans le Remote Network dédié aux conteneurs.

## Résolution des problèmes courants

- **Problème de connectivité réseau au démarrage** : L'initialisation du réseau rootless de Podman peut perturber les routes de l'hôte au démarrage. Une condition `ExecStartPre` a été ajoutée pour attendre que le réseau (internet) soit réellement disponible avant de lancer le processus Twingate :
  `ExecStartPre=/bin/sh -c 'while ! ping -c 1 1.1.1.1 >/dev/null 2>&1; do sleep 2; done'`
- **Erreur `Failed to enable unit`** : Ne jamais utiliser `systemctl --user enable` pour cette unité. Quadlet gère lui-même l'activation au démarrage via le générateur de système. Utilisez uniquement `systemctl --user start twingate-host`.

## Procédure de Rollback

En cas de perte de connectivité ou de mise à jour défaillante du connecteur hôte :

```bash
# 1. Arrêter l'unité systemd
systemctl --user stop twingate-host

# 2. Retirer l'unité Quadlet
rm -f ~/.config/containers/systemd/twingate-host.container
systemctl --user daemon-reload

# 3. Stopper le conteneur résiduel
podman rm -f twingate-host
```

## Leçons Retenues & Bonnes Pratiques

- **Ségrégation stricte des Remote Networks :** L'affectation des deux connecteurs à un même réseau virtuel Twingate est une erreur critique. Twingate traite les connecteurs d'un même réseau comme un cluster actif-actif et distribue les paquets de façon aléatoire. Segmenter en `Homelab-Containers` et `Homelab-Host` garantit l'étanchéité absolue entre administration système et services applicatifs.
- **Temporisation réseau `ExecStartPre` :** Sur un serveur redémarrant à froid, le service Twingate Host peut démarrer avant que la négociation DHCP et les routes par défaut de l'hôte ne soient stabilisées, provoquant des échecs d'enregistrement en boucle. La directive d'attente active ping élimine ce problème sans impacter le temps de démarrage global.
- **Posture d'administration souveraine :** Grâce à ce connecteur, les ports d'administration sensibles (SSH 22, Cockpit 9090) ne nécessitent aucune règle NAT ni redirection de port sur la box/routeur, éliminant tout balayage ou attaque par force brute depuis l'Internet public.
