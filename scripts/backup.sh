#!/bin/bash

# ==============================================================================
# Script de Sauvegarde Automatisée du Homelab
# Description : Effectue des sauvegardes logiques des bases de données
#               (PostgreSQL) et des volumes applicatifs, puis les copie sur
#               le disque de sauvegarde externe.
#
# Principe directeur : un échec doit être BRUYANT. Aucune archive vide ou
# partielle n'est conservée, et le script sort en code non nul afin que le
# timer systemd marque le service comme « failed ».
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
set -a
source "${SCRIPT_DIR}/../data/.env"
set +a

# pipefail : sans lui, `commande | gzip > fichier` renvoie le code de gzip,
# qui réussit même sur une entrée vide -> archive vide déclarée « réussie »
# (incident du 2026-08-04, voir le runbook des sauvegardes).
set -o pipefail

# Code de sortie global : toute section en échec le fait passer à 1.
EXIT_CODE=0

# Répertoire lu par le collecteur « textfile » de node_exporter :
# permet d'alerter sur une sauvegarde absente, ancienne ou en échec.
METRICS_DIR="${HOME}/.local/share/homelab-metrics"

# S'assurer que BACKUP_DIR est défini dans .env (Pattern de sécurité fail-fast)
if [ -z "${BACKUP_DIR}" ]; then
    echo "❌ ERREUR : BACKUP_DIR n'est pas défini dans data/.env ! Abandon de la sauvegarde."
    exit 1
fi
DEST_DIR="${BACKUP_DIR}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

mkdir -p "${DEST_DIR}/postgres"

echo "================================================================="
echo "Début de la sauvegarde du Homelab - $(date)"
echo "Destination : ${DEST_DIR}"
echo "================================================================="

# ------------------------------------------------------------------------------
# Fonction générique de sauvegarde d'un volume nommé
#
# Usage : backup_volume <nom_du_volume> <sous_repertoire> <libelle> <requis|optionnel>
#
# Le nom du volume n'apparaît qu'UNE SEULE FOIS par appel : c'est la
# duplication d'un même nom à deux endroits (archive et garde-fou) qui avait
# produit une sauvegarde vide silencieuse le 2026-08-03.
# Standard de nommage des volumes : <niveau>_<service>_data.
# ------------------------------------------------------------------------------
backup_volume() {
    local volume="$1" subdir="$2" label="$3" requirement="$4"
    local archive="${subdir}_data_${TIMESTAMP}.tar.gz"

    if ! podman volume exists "${volume}"; then
        if [ "${requirement}" = "requis" ]; then
            echo "❌ Échec : volume ${volume} introuvable alors qu'il est attendu."
            EXIT_CODE=1
        else
            echo "⏭  Volume ${volume} absent (service non déployé) — ${label} ignoré."
        fi
        return
    fi

    mkdir -p "${DEST_DIR}/${subdir}"
    if podman run --rm \
        --volume "${volume}:/data:ro" \
        --volume "${DEST_DIR}/${subdir}:/backup:z" \
        docker.io/alpine:3.22 \
        tar -czf "/backup/${archive}" -C /data . ; then
        echo "✅ Sauvegarde ${label} réussie."
    else
        echo "❌ Échec de la sauvegarde ${label} ! Archive incomplète supprimée."
        rm -f "${DEST_DIR}/${subdir}/${archive}"
        EXIT_CODE=1
    fi
}

# ------------------------------------------------------------------------------
# 1. Sauvegarde logique PostgreSQL (niveau Data)
# ------------------------------------------------------------------------------
echo "[1/4] Sauvegarde des bases de données PostgreSQL..."

if ! podman container exists postgres-db; then
    echo "❌ Échec : le conteneur postgres-db n'existe pas — sauvegarde PostgreSQL ignorée."
    EXIT_CODE=1
else
    PG_DUMP_FILE="${DEST_DIR}/postgres/pg_dumpall_${TIMESTAMP}.sql.gz"
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
# 2-4. Sauvegarde des volumes applicatifs
#
# Note : le volume de Prometheus est volontairement ABSENT de cette liste —
# l'historique de métriques est une donnée remplaçable dont la perte n'a
# aucune conséquence opérationnelle.
# ------------------------------------------------------------------------------
echo "[2/4] Sauvegarde du volume Vaultwarden (pièces jointes, clés RSA)..."
backup_volume apps_vaultwarden_data   vaultwarden  "des fichiers statiques de Vaultwarden" requis

echo "[3/4] Sauvegarde du volume Actual Budget (SQLite)..."
backup_volume apps_actual_budget_data actualbudget "d'Actual Budget"                       requis

echo "[4/5] Sauvegarde du volume Grafana (tableaux de bord)..."
backup_volume apps_grafana_data       grafana      "des tableaux de bord Grafana"          optionnel

echo "[5/6] Sauvegarde du volume ntfy (comptes et jetons)..."
backup_volume apps_ntfy_data          ntfy         "des comptes ntfy"                      optionnel

echo "[6/6] Sauvegarde du volume Forgejo (dépôts Git et SQLite)..."
backup_volume apps_forgejo_data       forgejo      "de Forgejo"                            optionnel

echo "================================================================="
if [ "${EXIT_CODE}" -eq 0 ]; then
    echo "Sauvegarde terminée avec succès - $(date)"
else
    echo "⚠️  Sauvegarde terminée AVEC ERREURS - $(date)"
fi
echo "================================================================="

# ------------------------------------------------------------------------------
# Publication des métriques pour node_exporter (collecteur textfile)
#
# Écriture atomique (fichier temporaire puis renommage) : node_exporter peut
# lire le répertoire à tout instant et ne doit jamais voir un fichier partiel.
# ------------------------------------------------------------------------------
mkdir -p "${METRICS_DIR}"
NOW_EPOCH=$(date +%s)
{
    echo "# HELP homelab_backup_last_run_timestamp_seconds Horodatage de la derniere execution de la sauvegarde."
    echo "# TYPE homelab_backup_last_run_timestamp_seconds gauge"
    echo "homelab_backup_last_run_timestamp_seconds ${NOW_EPOCH}"
    echo "# HELP homelab_backup_last_exit_code Code de sortie de la derniere execution (0 = succes)."
    echo "# TYPE homelab_backup_last_exit_code gauge"
    echo "homelab_backup_last_exit_code ${EXIT_CODE}"
    if [ "${EXIT_CODE}" -eq 0 ]; then
        echo "# HELP homelab_backup_last_success_timestamp_seconds Horodatage de la derniere sauvegarde reussie."
        echo "# TYPE homelab_backup_last_success_timestamp_seconds gauge"
        echo "homelab_backup_last_success_timestamp_seconds ${NOW_EPOCH}"
    fi
} > "${METRICS_DIR}/backup.prom.tmp"
mv "${METRICS_DIR}/backup.prom.tmp" "${METRICS_DIR}/backup.prom"

# ------------------------------------------------------------------------------
# Nettoyage des anciennes sauvegardes (conserver les 7 derniers jours)
#
# Uniquement en cas de succès : une panne silencieuse prolongée ne doit jamais
# finir par supprimer les dernières archives saines.
# ------------------------------------------------------------------------------
if [ "${EXIT_CODE}" -eq 0 ]; then
    find "${DEST_DIR}/postgres" -type f -name "*.sql.gz" -mtime +7 -delete
    for subdir in vaultwarden actualbudget grafana ntfy forgejo; do
        [ -d "${DEST_DIR}/${subdir}" ] && \
            find "${DEST_DIR}/${subdir}" -type f -name "*.tar.gz" -mtime +7 -delete
    done
else
    echo "Rotation des anciennes sauvegardes ignorée (échec détecté)."
fi

# Code de sortie non nul en cas d'échec : le timer systemd marque le service
# comme « failed » au lieu de masquer le problème.
exit "${EXIT_CODE}"
