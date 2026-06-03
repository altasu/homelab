# Homelab Infrastructure (Zero-Trust & Rootless)

🇬🇧 [English](#english) | 🇫🇷 [Français](#français)

---

<a name="english"></a>
## 🇬🇧 English

Welcome to my modern, secure, and resilient Homelab infrastructure repository. This project demonstrates my skills in System Administration, DevOps, and Security (Zero-Trust) principles using a "Separation of Concerns" approach.

### Architecture & Technologies
- **OS & Containerization:** Enterprise Linux with **Rootless Podman** (Docker alternative for enhanced security).
- **Storage & Isolation:** 
  - `Primary Storage`: Dedicated to the host OS and active containers.
  - `Backup Vault`: Physically and logically isolated secondary storage.
- **Network & Security:** 
  - **Zero-Trust Networking:** Cloudflared Tunnel (isolated) & Twingate Connector (`network_mode: host` for direct Cockpit/host access). No open inbound ports (except standard DNS port 53 managed by router).
- **Services:** Vaultwarden (Password Manager), securely routed through Cloudflare.
- **Automation:** Systemd-based automated backup jobs integrated with the Cockpit UI.

### Repository Structure
- `infrastructure/compose.yaml`: Infrastructure as Code (IaC) definition for all services.
- `infrastructure/backup.sh`: Automated backup script targeting the isolated HDD vault.
- `.env.example`: Template for required environment variables and secrets.

### 🔄 GitOps & Workflow
This infrastructure is managed using **Infrastructure as Code (IaC)** and **GitOps** principles:
- **Development:** Code is written and tested locally using VS Code.
- **Version Control:** Hosted on a public repository to showcase CI/CD and DevOps practices.
- **Deployment:** The server pulls changes via `git pull` and applies them using `podman-compose up -d`.

### Security Posture
All secrets, tokens, and specific server paths are strictly managed via environment variables (`.env`) and are explicitly ignored in version control (`.gitignore`) to ensure zero security vulnerabilities in this public repository.

---

<a name="français"></a>
## 🇫🇷 Français

Bienvenue sur le dépôt de mon infrastructure Homelab moderne, sécurisée et résiliente. Ce projet démontre mes compétences en administration système, DevOps et sécurité (Zero-Trust) en utilisant l'approche de la « Séparation des préoccupations » (Separation of Concerns).

### Architecture et Technologies
- **OS et Conteneurisation :** Enterprise Linux avec **Rootless Podman** (alternative sécurisée à Docker).
- **Stockage et Isolation :** 
  - `Stockage Principal` : Dédié au système d'exploitation hôte et aux conteneurs actifs.
  - `Coffre de Sauvegarde` : Stockage secondaire physiquement et logiquement isolé.
- **Réseau et Sécurité :** 
  - **Réseau Zero-Trust :** Cloudflared Tunnel (isolé) et Twingate Connector (en `network_mode: host` pour un accès direct à Cockpit/hôte). Aucun port entrant ouvert (sauf le port DNS standard 53 géré par le routeur).
- **Services :** Vaultwarden (Gestionnaire de mots de passe), routé de manière sécurisée via Cloudflare.
- **Automatisation :** Tâches de sauvegarde automatisées basées sur Systemd et intégrées à l'interface web Cockpit.

### Structure du Dépôt
- `infrastructure/compose.yaml` : Définition de l'infrastructure en tant que code (IaC) pour tous les services.
- `infrastructure/backup.sh` : Script de sauvegarde automatisé ciblant le disque dur isolé.
- `.env.example` : Modèle pour les variables d'environnement et les secrets requis.

### 🔄 GitOps et Flux de Travail
Cette infrastructure est gérée en utilisant les principes d'**Infrastructure as Code (IaC)** et de **GitOps** :
- **Développement :** Le code est écrit et testé localement à l'aide de VS Code.
- **Contrôle de Version :** Hébergé sur un dépôt public pour démontrer les pratiques CI/CD et DevOps.
- **Déploiement :** Le serveur récupère les modifications via `git pull` et les applique avec `podman-compose up -d`.

### Posture de Sécurité
Tous les secrets, jetons et chemins d'accès spécifiques aux serveurs sont strictement gérés via des variables d'environnement (`.env`) et sont explicitement ignorés dans le contrôle de version (`.gitignore`) pour garantir une absence totale de vulnérabilités dans ce dépôt public.
