# Homelab Infrastructure (IaC)

🇫🇷 **Français** | 🇺🇸 **English**

---

## 🇫🇷 Français
Ce dépôt contient l'Infrastructure as Code (IaC) de mon homelab personnel, conçu avec une architecture sécurisée à 3 niveaux (3-tier) en utilisant Podman.

### État Actuel : Étape 1 (Core Infra) - Actif
- **Réseau :** Réseau Docker externe (`homelab_net`) créé pour la communication entre les conteneurs.
- **Passerelle :** Cloudflare Tunnel et Twingate Connector s'exécutent dans un environnement isolé. Cela fournit un accès à distance Zero Trust sans ouvrir de ports entrants sur le routeur.
- **Prochaines Étapes :** Implémentation de l'Étape 2 (Données / Persistance) avec connexion au stockage externe.

---

## 🇺🇸 English
This repository contains the Infrastructure as Code (IaC) for my personal homelab, designed with a secure, 3-tier architecture using Podman.

### Current State: Stage 1 (Core Infra) - Active
- **Networking:** External Docker network (`homelab_net`) created for inter-container communication.
- **Gateway:** Cloudflare Tunnel and Twingate Connector are running in an isolated environment. This provides Zero Trust remote access without opening any inbound ports on the router.
- **Next Steps:** Implementation of Stage 2 (Data / Persistence) connecting to external storage.