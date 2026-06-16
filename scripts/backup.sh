#!/bin/bash

# ==============================================================================
# Homelab Automated Backup Script
# Description: Performs logical backups of databases (PostgreSQL) and application
#              data (Vaultwarden), then copies them to the external HDD.
# ==============================================================================

# Load environment variables (to get BACKUP_DIR if needed)
# Source the data env file to get DB credentials and path info
set -a
source ../data/.env
set +a

# Ensure BACKUP_DIR is defined in .env (Fail-fast security pattern)
if [ -z "${BACKUP_DIR}" ]; then
    echo "❌ ERROR: BACKUP_DIR is not defined in data/.env! Aborting backup."
    exit 1
fi
DEST_DIR="${BACKUP_DIR}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Ensure backup directory exists
mkdir -p "${DEST_DIR}/postgres"
mkdir -p "${DEST_DIR}/vaultwarden"

echo "================================================================="
echo "Starting Homelab Backup - $(date)"
echo "Destination: ${DEST_DIR}"
echo "================================================================="

# ------------------------------------------------------------------------------
# 1. PostgreSQL Logical Backup (Stage 2)
# ------------------------------------------------------------------------------
echo "[1/2] Backing up PostgreSQL databases..."

# Execute pg_dumpall inside the postgres-db container
# We use gzip to compress the SQL dump on the fly
podman exec postgres-db pg_dumpall -U "${POSTGRES_USER}" | gzip > "${DEST_DIR}/postgres/pg_dumpall_${TIMESTAMP}.sql.gz"

if [ $? -eq 0 ]; then
    echo "✅ PostgreSQL backup successful."
else
    echo "❌ PostgreSQL backup failed!"
fi

# ------------------------------------------------------------------------------
# 2. Vaultwarden Attachments/RSA Keys Backup (Stage 3)
# ------------------------------------------------------------------------------
echo "[2/2] Backing up Vaultwarden static files..."

# Vaultwarden's database is in Postgres, but attachments and config/RSA keys 
# are in the named volume 'vaultwarden_data'.
# We create a temporary container attached to the volume to tar it up.
podman run --rm \
    --volume vaultwarden_data:/data:ro \
    --volume "${DEST_DIR}/vaultwarden":/backup:z \
    docker.io/alpine:latest \
    tar -czf "/backup/vaultwarden_data_${TIMESTAMP}.tar.gz" -C /data .

if [ $? -eq 0 ]; then
    echo "✅ Vaultwarden files backup successful."
else
    echo "❌ Vaultwarden files backup failed!"
fi

echo "================================================================="
echo "Backup Completed - $(date)"
echo "================================================================="

# ------------------------------------------------------------------------------
# Cleanup older backups (Keep last 7 days)
# ------------------------------------------------------------------------------
find "${DEST_DIR}/postgres" -type f -name "*.sql.gz" -mtime +7 -delete
find "${DEST_DIR}/vaultwarden" -type f -name "*.tar.gz" -mtime +7 -delete