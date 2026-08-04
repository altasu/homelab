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

# pipefail : sans lui, `commande | gzip > fichier` renvoie le code de gzip,
# qui réussit même sur une entrée vide -> archive vide déclarée « réussie »
# (incident du 2026-08-04, voir le runbook des sauvegardes).
set -o pipefail

# Code de sortie global : toute section en échec le fait passer à 1, afin que
# `systemctl --user status backup.service` signale réellement l'échec.
EXIT_CODE=0

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

# Garde-fou : sans conteneur en cours d'exécution, ne pas créer d'archive vide
if ! podman container exists postgres-db; then
    echo "❌ Échec : le conteneur postgres-db n'existe pas — sauvegarde PostgreSQL ignorée."
    EXIT_CODE=1
else
    PG_DUMP_FILE="${DEST_DIR}/postgres/pg_dumpall_${TIMESTAMP}.sql.gz"
    # Exécuter pg_dumpall à l'intérieur du conteneur, compression à la volée.
    # Grâce à `set -o pipefail`, un échec de pg_dumpall est bien détecté ici.
    if podman exec postgres-db pg_dumpall -U "${POSTGRES_USER}" | gzip > "${PG_DUMP_FILE}"; then
        # Double contrôle : une archive valide mais vide reste un échec
        if [ "$(gzip -dc "${PG_DUMP_FILE}" | head -c 1 | wc -c)" -eq 0 ]; then
            echo "❌ Échec : le dump PostgreSQL est vide — archive supprimée."
            rm -f "${PG_DUMP_FILE}"
            EXIT_CODE=1
        else
            echo "✅ Sauvegarde de PostgreSQL réussie."
        fi
    else
        echo "❌ Échec de la sauvegarde de PostgreSQL ! Archive incomplète supprimée."
        rm -f "${PG_DUMP_FILE}"
        EXIT_CODE=1
    fi
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
    EXIT_CODE=1
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
        EXIT_CODE=1
    fi
else
    echo "[3/3] Volume apps_actual_budget_data absent — sauvegarde Actual Budget ignorée."
fi

echo "================================================================="
if [ "${EXIT_CODE}" -eq 0 ]; then
    echo "Sauvegarde terminée avec succès - $(date)"
else
    echo "⚠️  Sauvegarde terminée AVEC ERREURS - $(date)"
fi
echo "================================================================="

# ------------------------------------------------------------------------------
# Nettoyage des anciennes sauvegardes (Conserver les 7 derniers jours)
# ------------------------------------------------------------------------------
# Uniquement si tout s'est bien passé : ne jamais supprimer d'anciennes
# sauvegardes valides lorsque celles du jour ont échoué.
if [ "${EXIT_CODE}" -eq 0 ]; then
    find "${DEST_DIR}/postgres" -type f -name "*.sql.gz" -mtime +7 -delete
    find "${DEST_DIR}/vaultwarden" -type f -name "*.tar.gz" -mtime +7 -delete
    find "${DEST_DIR}/actualbudget" -type f -name "*.tar.gz" -mtime +7 -delete 2>/dev/null
else
    echo "Rotation des anciennes sauvegardes ignorée (échec détecté)."
fi

# Code de sortie non nul en cas d'échec : le timer systemd marque le service
# comme « failed » au lieu de masquer le problème.
exit "${EXIT_CODE}"