#!/bin/bash

# Arrêter le script en cas d'erreur
set -e

# Charger les variables d'environnement depuis le fichier .env
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/.env"

# Génération dynamique du nom de la sauvegarde avec la date du jour
BACKUP_NAME="homelab_backup_$(date +%Y%m%d_%H%M%S).tar.gz"

#1. Créez un dossier de sauvegarde dans XFS Vault (s'il n'en existe pas)
mkdir -p "$BACKUP_DIR"

# 2. Compressez et archivez l'infrastructure et la base de données de mots de passe
tar -czf "${BACKUP_DIR}/${BACKUP_NAME}" \
    -C "$SOURCE_COMPOSE" compose.yaml \
    -C "$SOURCE_VAULTWARDEN" db.sqlite3 rsa_key.pem rsa_key.pub.pem

# 3. Nettoyage : Suppression des sauvegardes de plus de 7 jours (Empêche le disque de se remplir)
find "$BACKUP_DIR" -type f -name "homelab_backup_*.tar.gz" -mtime +7 -delete

echo "Sauvegarde terminée avec succès : ${BACKUP_DIR}/${BACKUP_NAME}"