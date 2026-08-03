#!/bin/bash

# ==============================================================================
# Script de Sauvegarde Automatisée du Homelab
# Description : Effectue des sauvegardes logiques des bases de données (PostgreSQL)
#               et des données d'application (Vaultwarden, Actual Budget),
#               puis les copie sur le HDD externe.
# ==============================================================================

# Charger les variables d'environnement (pour obtenir BACKUP_DIR si nécessaire)
# Charger le fichier env de data pour obtenir les identifiants DB et les chemins
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
set -a
source "${SCRIPT_DIR}/../data/.env"
set +a

# S'assurer que BACKUP_DIR est défini dans .env (Pattern de sécurité fail-fast)
if [ -z "${BACKUP_DIR}" ]; then
    echo "❌ ERREUR : BACKUP_DIR n'est pas défini dans data/.env ! Abandon de la sauvegarde."
    exit 1
fi
DEST_DIR="${BACKUP_DIR}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# S'assurer que le répertoire de sauvegarde existe
mkdir -p "${DEST_DIR}/postgres"
mkdir -p "${DEST_DIR}/vaultwarden"

echo "================================================================="
echo "Début de la sauvegarde du Homelab - $(date)"
echo "Destination : ${DEST_DIR}"
echo "================================================================="

# ------------------------------------------------------------------------------
# 1. Sauvegarde Logique PostgreSQL (Niveau 2)
# ------------------------------------------------------------------------------
echo "[1/3] Sauvegarde des bases de données PostgreSQL..."

# Exécuter pg_dumpall à l'intérieur du conteneur postgres-db
# Nous utilisons gzip pour compresser le dump SQL à la volée
podman exec postgres-db pg_dumpall -U "${POSTGRES_USER}" | gzip > "${DEST_DIR}/postgres/pg_dumpall_${TIMESTAMP}.sql.gz"

if [ $? -eq 0 ]; then
    echo "✅ Sauvegarde de PostgreSQL réussie."
else
    echo "❌ Échec de la sauvegarde de PostgreSQL !"
fi

# ------------------------------------------------------------------------------
# 2. Sauvegarde des Fichiers Statiques Vaultwarden (Niveau 3)
# ------------------------------------------------------------------------------
echo "[2/3] Sauvegarde des fichiers statiques de Vaultwarden (pièces jointes, clés RSA)..."

# Archiver l'intégralité du volume contenant les données non-DB
# ATTENTION : podman-compose préfixe les volumes nommés avec le nom du
# répertoire (apps/compose.yml -> apps_vaultwarden_data). Un nom sans
# préfixe créerait silencieusement un volume vide et produirait une
# archive vide (incident corrigé le 2026-08-03, voir
# docs/runbooks/sauvegardes-verification-restauration.md).
podman run --rm \
    --volume apps_vaultwarden_data:/data:ro \
    --volume "${DEST_DIR}/vaultwarden":/backup:z \
    docker.io/alpine:3.22 \
    tar -czf "/backup/vaultwarden_data_${TIMESTAMP}.tar.gz" -C /data .

if [ $? -eq 0 ]; then
    echo "✅ Sauvegarde des fichiers statiques de Vaultwarden réussie."
else
    echo "❌ Échec de la sauvegarde des fichiers statiques de Vaultwarden !"
fi

# ------------------------------------------------------------------------------
# 3. Sauvegarde des Données Actual Budget (Niveau 3)
# ------------------------------------------------------------------------------
# Volume géré par Quadlet. STANDARD DE NOMMAGE : <tier>_<service>_data
# (VolumeName= explicite aligné sur la convention compose, ex. apps_vaultwarden_data),
# le garde-fou ci-dessous DOIT référencer exactement le même nom que l'archive.
# SEULE persistance d'Actual Budget : fichiers SQLite (pas de backend PostgreSQL).
# Garde-fou : ignoré tant que le service n'est pas déployé (Étape 2 du plan).
if podman volume exists apps_actual_budget_data; then
    echo "[3/3] Sauvegarde des données Actual Budget (SQLite)..."
    mkdir -p "${DEST_DIR}/actualbudget"
    podman run --rm \
        --volume apps_actual_budget_data:/data:ro \
        --volume "${DEST_DIR}/actualbudget":/backup:z \
        docker.io/alpine:3.22 \
        tar -czf "/backup/actualbudget_data_${TIMESTAMP}.tar.gz" -C /data .

    if [ $? -eq 0 ]; then
        echo "✅ Sauvegarde d'Actual Budget réussie."
    else
        echo "❌ Échec de la sauvegarde d'Actual Budget !"
    fi
else
    echo "[3/3] Volume apps_actual_budget_data absent — sauvegarde Actual Budget ignorée."
fi

echo "================================================================="
echo "Sauvegarde terminée - $(date)"
echo "================================================================="

# ------------------------------------------------------------------------------
# Nettoyage des anciennes sauvegardes (Conserver les 7 derniers jours)
# ------------------------------------------------------------------------------
find "${DEST_DIR}/postgres" -type f -name "*.sql.gz" -mtime +7 -delete
find "${DEST_DIR}/vaultwarden" -type f -name "*.tar.gz" -mtime +7 -delete
find "${DEST_DIR}/actualbudget" -type f -name "*.tar.gz" -mtime +7 -delete 2>/dev/null