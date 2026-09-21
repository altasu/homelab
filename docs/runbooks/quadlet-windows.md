# Runbook — Quadlet : Déploiement et exploitation de Windows 11 VM (KVM Rootless)

Ce runbook décrit le déploiement, l'exploitation et la maintenance d'une machine virtuelle **Windows 11** conteneurisée avec accélération matérielle KVM, au format d'unités Quadlet systemd rootless.

## Cas d'Usage & Architecture

- **Poste de travail distant persistant** : Dédié aux tâches nécessitant un environnement Windows 11 isolé, sécurisé et accessible à distance.
- **Empreinte IP & Sécurité Zero-Trust** : Les connexions s'effectuent exclusivement via **Twingate VPN** (RDP natif sur port `3389`). Aucun port n'est exposé sur Internet ; le trafic sortant utilise l'adresse IP fixe du serveur homelab.
- **Persistance intégrale** : L'installation Windows, le profil utilisateur, les configurations et les fichiers sont conservés sur le volume nommé `apps_windows_data`.

## Fichiers IaC impliqués

| Fichier (dépôt) | Rôle |
|---|---|
| `apps/quadlet/windows.container` | Unité conteneur Quadlet (image `docker.io/dockurr/windows:6.05`, KVM, 6GB RAM / 2 vCPUs) |
| `apps/quadlet/windows.volume` | Volume nommé `apps_windows_data` (disque virtuel `data.qcow2` de 64GB) |
| `apps/windows.env.example` | Modèle de variables d'environnement (`VERSION`, `RAM_SIZE`, `PASSWORD`, etc.) |
| `infra/quadlet/homelab.network` | Réseau interne partagé `homelab_net` |

## Prérequis Hôte (Virtualisation / KVM)

1. **Virtualisation matérielle active** (Intel VT-x ou AMD-V dans le BIOS/UEFI).
2. **Droits d'accès KVM pour l'utilisateur rootless** :
   ```bash
   # Vérifier la présence du périphérique KVM
   ls -la /dev/kvm
   
   # Ajouter l'utilisateur homelab au groupe kvm si nécessaire
   sudo usermod -aG kvm $USER
   ```
   *(Une déconnexion / reconnexion SSH est requise pour appliquer l'appartenance au groupe).*

## Procédure de Déploiement

```bash
# 1. Synchroniser le dépôt
git pull

# 2. Préparer le fichier d'environnement
cp apps/windows.env.example apps/windows.env
chmod 600 apps/windows.env

# Éditer le mot de passe de session Windows
# nano apps/windows.env -> PASSWORD=<VOTRE_MOT_DE_PASSE_SECURISE>
scripts/check-env.sh apps/windows.env

# 3. Déployer les unités Quadlet
mkdir -p ~/.config/containers/systemd
cp apps/quadlet/windows.{container,volume} ~/.config/containers/systemd/

# 4. Valider la syntaxe
/usr/libexec/podman/quadlet -dryrun -user

# 5. Charger et démarrer le service
systemctl --user daemon-reload
systemctl --user start windows
systemctl --user status windows --no-pager
```

## Suivi de l'Installation Initiale

Lors du premier démarrage, le conteneur télécharge automatiquement l'ISO officielle de Windows 11 depuis les serveurs Microsoft, intègre les pilotes VirtIO et exécute une installation automatisée (unattended) sans intervention manuelle (durée : ~5 à 10 minutes selon la vitesse de connexion).

Pour suivre la progression :
```bash
# Consulter les journaux d'installation
journalctl --user -u windows -f
```

Ou ouvrir la vue Web temporaire (noVNC) via Twingate / Cloudflare Tunnel sur le port `8006` (`http://windows:8006`).

## Connexion via Bureau à Distance (Microsoft Remote Desktop)

Une fois l'installation terminée, la méthode d'accès recommandée est le **RDP natif** (haute performance, fluidité 60 FPS, partage de presse-papier et de fichiers Mac <-> Windows) :

1. Ouvrir **Microsoft Remote Desktop** sur votre Mac.
2. Ajouter un nouveau PC :
   - **PC Name** : `windows:3389` (ou l'IP Twingate assignée à la ressource Windows).
   - **User Account** : `homelab` (ou le `USERNAME` défini dans `windows.env`).
   - **Password** : Le `PASSWORD` configuré dans `windows.env`.
3. Activer le partage du presse-papier (*Clipboard*) et des dossiers locaux dans les paramètres de la connexion RDP pour glisser-déposer vos fichiers numériques directement depuis le Mac.

## Arrêt et Rollback

```bash
# Arrêter proprement la VM (permet à Windows de flusher le système de fichiers NTFS)
systemctl --user stop windows

# Désactiver et supprimer l'unité
rm -f ~/.config/containers/systemd/windows.{container,volume}
systemctl --user daemon-reload
```
Le volume `apps_windows_data` conserve l'intégralité du disque virtuel `data.qcow2` et des données utilisateur.

---

## Leçons Retenues & Bonnes Pratiques

- **Exemption technique KVM rootless :** La virtualisation KVM sous Podman rootless requiert obligatoirement `AddDevice=/dev/kvm` et le périphérique réseau virtuel `AddDevice=/dev/net/tun` couplé à `AddCapability=NET_ADMIN`. C'est la raison pour laquelle ce conteneur est exempté de la politique globale `DropCapability=ALL`.
- **Délai d'initialisation (`TimeoutStartSec=600`) :** Le premier amorçage d'une image Windows 11 déploie une installation non surveillée (*unattended ISO setup*) qui dure 5 à 8 minutes. Sans un `TimeoutStartSec` généreux dans systemd, le superviseur tue le conteneur pour inactivité apparente avant la fin de l'installation.
- **RDP natif vs Web Viewer noVNC :** L'interface web HTTP 8006 (noVNC) est utile uniquement pour observer le déroulement de l'installation. Pour une utilisation professionnelle, l'accès RDP natif (port 3389) via le tunnel privé Twingate offre l'accélération matérielle, le multi-écrans, la synchronisation du presse-papier et un framerate fluide à 60 fps.
- **Synchronisation temporelle et mise en veille :** Le montage en lecture seule de `/etc/localtime` couplé au réglage `TZ=Europe/Paris` évite les dérives d'horloge dans Windows. De plus, l'image `dockurr/windows` désactive nativement la veille du système d'exploitation invité, assurant la disponibilité 24/7 de la machine.
