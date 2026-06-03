# Homelab Infrastructure (Zero-Trust & Rootless)

🇫🇷 [Français](#français) | 🇬🇧 [English](#english)

---

<a name="français"></a>
## 🇫🇷 Français

Bienvenue sur le dépôt de mon infrastructure Homelab moderne, hautement sécurisée et résiliente. Ce projet implémente les meilleures pratiques d'administration système, DevOps et sécurité (Zero-Trust) en s'appuyant sur le principe de la « Séparation des préoccupations » (Separation of Concerns).

### Architecture et Technologies

- **OS et Conteneurisation :** Enterprise Linux exécutant **Rootless Podman** (alternative sécurisée à Docker ne nécessitant pas de privilèges root).
- **Réseau et Sécurité Zero-Trust :**
  - **Cloudflared Tunnel** : Connexion sortante isolée pour exposer les services web de manière sécurisée sans ouvrir de ports sur votre box/routeur.
  - **Twingate Connector** : Accès à distance de confiance pour l'administration du serveur (ex. Cockpit) sans aucune exposition publique.
- **Services Hébergés :**
  - **Vaultwarden** : Gestionnaire de mots de passe auto-hébergé, sécurisé et routé via Cloudflare.
- **Sauvegarde Automatisée :** Scripts de sauvegarde automatisés via Systemd avec rétention programmée.

---

### Structure du Dépôt

| Fichier / Dossier | Description |
| :--- | :--- |
| [`infrastructure/compose.yaml`](./infrastructure/compose.yaml) | Définition multi-conteneurs de l'infrastructure (IaC) pour les services. |
| [`infrastructure/backup.sh`](./infrastructure/backup.sh) | Script de sauvegarde compressée et de nettoyage de l'historique (rétention de 7 jours). |
| [`infrastructure/.env.example`](./infrastructure/.env.example) | Modèle pour configurer les variables d'environnement et secrets requis. |
| [`.gitignore`](./.gitignore) | Fichiers et dossiers exclus du contrôle de version (sauvegardes, certificats, secrets). |

---

### Prérequis et Déploiement

#### 1. Configuration du Réseau Externe
Les services partagent un réseau virtuel isolé nommé `homelab-net`. Ce réseau doit être créé manuellement avant de démarrer les conteneurs :
```bash
podman network create homelab-net
```

#### 2. Configuration des Variables d'Environnement
Copiez le modèle d'environnement et ajustez-le avec vos configurations et jetons secrets :
```bash
cp infrastructure/.env.example infrastructure/.env
# Éditez le fichier pour renseigner vos tokens Cloudflare et Twingate
nano infrastructure/.env
```

#### 3. Lancement des Services
Pour démarrer tous les conteneurs en mode arrière-plan (detached) :
```bash
podman-compose -f infrastructure/compose.yaml up -d
```

---

### Automatisation des Sauvegardes

Le script de sauvegarde [`infrastructure/backup.sh`](./infrastructure/backup.sh) extrait la base de données Vaultwarden (`db.sqlite3` et clés de chiffrement) ainsi que la configuration compose, les compresse sous format `.tar.gz`, et les stocke dans le dossier de sauvegarde désigné. Il supprime ensuite les archives de plus de 7 jours.

#### Intégration Systemd (Recommandé)
Pour planifier ce script quotidiennement via Systemd sous votre utilisateur rootless :

1. Créez le fichier de service : `~/.config/systemd/user/homelab-backup.service`
   ```ini
   [Unit]
   Description=Sauvegarde de l'infrastructure Homelab
   After=network.target

   [Service]
   Type=oneshot
   ExecStart=/bin/bash /chemin/vers/votre/depot/infrastructure/backup.sh
   ```

2. Créez le déclencheur temporel : `~/.config/systemd/user/homelab-backup.timer`
   ```ini
   [Unit]
   Description=Planification de la sauvegarde Homelab

   [Timer]
   OnCalendar=daily
   Persistent=true

   [Install]
   WantedBy=timers.target
   ```

3. Activez et démarrez le timer :
   ```bash
   systemctl --user daemon-reload
   systemctl --user enable --now homelab-backup.timer
   ```

---

### Posture de Sécurité (Zero-Trust)

- **Aucun port entrant ouvert :** Tout le trafic entrant passe par des tunnels chiffrés sortants établis par Cloudflare et Twingate.
- **Sécurité Rootless :** Podman exécute les conteneurs dans un espace de noms utilisateur isolé (namespaces), empêchant toute élévation de privilèges vers l'hôte en cas de compromission.
- **Gestion stricte des Secrets :** Les secrets, jetons d'accès et chemins d'accès système sont exclusivement gérés via `.env` et ne sont jamais validés dans l'historique Git.

---
---

<a name="english"></a>
## 🇬🇧 English

Welcome to the repository of my modern, secure, and resilient Homelab infrastructure. This project demonstrates best practices in System Administration, DevOps, and Security (Zero-Trust) using a "Separation of Concerns" approach.

### Architecture & Technologies

- **OS & Containerization:** Enterprise Linux running **Rootless Podman** (a daemonless, secure Docker alternative).
- **Zero-Trust Network & Security:**
  - **Cloudflared Tunnel**: Secure, outbound-only tunnel to expose web services without opening inbound router/firewall ports.
  - **Twingate Connector**: Secure remote access for host management (e.g., Cockpit UI) without any public internet exposure.
- **Hosted Services:**
  - **Vaultwarden**: Self-hosted, resource-efficient password manager (Bitwarden compatible), securely routed via Cloudflare.
- **Automated Backup**: Native systemd-triggered backup and retention jobs.

---

### Repository Structure

| File / Folder | Description |
| :--- | :--- |
| [`infrastructure/compose.yaml`](./infrastructure/compose.yaml) | Infrastructure as Code (IaC) container definitions. |
| [`infrastructure/backup.sh`](./infrastructure/backup.sh) | Automated archive backup & cleanup script (7-day retention). |
| [`infrastructure/.env.example`](./infrastructure/.env.example) | Configuration template for environment variables and secrets. |
| [`.gitignore`](./.gitignore) | Files and folders excluded from version control (backups, certificates, secrets). |

---

### Prerequisites & Deployment

#### 1. Create External Network
The services share an isolated bridge network called `homelab-net`. This must be initialized manually before running the services:
```bash
podman network create homelab-net
```

#### 2. Configure Environment Variables
Copy the template file to configure your local keys and backup directories:
```bash
cp infrastructure/.env.example infrastructure/.env
# Edit the file to populate Cloudflare/Twingate tokens and paths
nano infrastructure/.env
```

#### 3. Run the Infrastructure
Start the environment in detached mode:
```bash
podman-compose -f infrastructure/compose.yaml up -d
```

---

### Backup Mechanism

The [`infrastructure/backup.sh`](./infrastructure/backup.sh) script backs up the active Vaultwarden database (`db.sqlite3`, keys) and the `compose.yaml` file into a timestamped `.tar.gz` archive, then cleans up archives older than 7 days.

#### Systemd Integration (Recommended)
To schedule the backup daily under your rootless user:

1. Create service unit: `~/.config/systemd/user/homelab-backup.service`
   ```ini
   [Unit]
   Description=Homelab Backup Service
   After=network.target

   [Service]
   Type=oneshot
   ExecStart=/bin/bash /path/to/your/repo/infrastructure/backup.sh
   ```

2. Create timer unit: `~/.config/systemd/user/homelab-backup.timer`
   ```ini
   [Unit]
   Description=Schedule Homelab Backup Daily

   [Timer]
   OnCalendar=daily
   Persistent=true

   [Install]
   WantedBy=timers.target
   ```

3. Enable and start the timer:
   ```bash
   systemctl --user daemon-reload
   systemctl --user enable --now homelab-backup.timer
   ```

---

### Security Posture & Zero-Trust

- **Zero Inbound Ports:** No ports are forwarded on your router or host firewall. Cloudflared and Twingate use secure outbound-only connections.
- **Rootless Podman:** Container processes run without root privileges, containing any potential compromises to the user space.
- **Strict Secret Isolation:** All sensitive credentials, domains, and tokens are stored in the git-ignored `.env` file to ensure a clean public codebase.
