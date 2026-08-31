# Connecteur Twingate : Réseau Hôte (Host Network)

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
