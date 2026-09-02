#!/usr/bin/env bash
# ==============================================================================
# scripts/homelab-sync.sh — Synchronisation GitOps et déploiement continu
#
# Vérifie l'existence de nouveaux commits sur 'main', applique les mises à jour,
# recharge le démon systemd utilisateur et redémarre les conteneurs modifiés.
# ==============================================================================

set -euo pipefail

REPO_DIR="${HOME}/homelab"
QUADLET_DEST="${HOME}/.config/containers/systemd"

if [ ! -d "${REPO_DIR}/.git" ]; then
    echo "❌ Répertoire Git introuvable : ${REPO_DIR}"
    exit 1
fi

cd "${REPO_DIR}"

# 1. Vérification des mises à jour distantes
git fetch origin main -q

LOCAL_HASH=$(git rev-parse HEAD)
REMOTE_HASH=$(git rev-parse origin/main)

if [ "${LOCAL_HASH}" = "${REMOTE_HASH}" ]; then
    echo "✅ Homelab est déjà synchronisé sur le commit ${LOCAL_HASH:0:7}."
    exit 0
fi

echo "🔄 Nouveaux commits détectés : ${LOCAL_HASH:0:7} -> ${REMOTE_HASH:0:7}"

# 2. Identifier précisément les fichiers modifiés par cette mise à jour
CHANGED_FILES=$(git diff --name-only "${LOCAL_HASH}" "${REMOTE_HASH}")

# 3. Récupération des modifications Git (Fast-Forward uniquement)
git pull origin main --ff-only

RESTARTED_SERVICES=()
QUADLET_UPDATED=0

# 4. Traitement STRICTEMENT CIBLÉ uniquement sur les fichiers modifiés
for file in ${CHANGED_FILES}; do
    case "${file}" in
        apps/quadlet/*.container|data/quadlet/*.container|infra/quadlet/*.container|\
        apps/quadlet/*.volume|data/quadlet/*.volume|infra/quadlet/*.volume|\
        infra/quadlet/*.network)
            filename=$(basename "${file}")
            svc=$(basename "${file}" | sed -E 's/\.(container|volume|network)$//')
            
            echo "📦 Mise à jour ciblée : ${file} -> ${QUADLET_DEST}/${filename}"
            cp "${REPO_DIR}/${file}" "${QUADLET_DEST}/${filename}"
            QUADLET_UPDATED=1
            RESTARTED_SERVICES+=("${svc}")
            ;;
        apps/glance/glance.yml)
            echo "🚀 Configuration Glance modifiée — redémarrage ciblé de glance"
            RESTARTED_SERVICES+=("glance")
            ;;
        apps/monitoring/prometheus/*)
            echo "🚀 Configuration Prometheus modifiée — redémarrage ciblé de prometheus"
            RESTARTED_SERVICES+=("prometheus")
            ;;
    esac
done

# 5. Rechargement de systemd UNIQUEMENT si au moins un fichier Quadlet a été modifié
if [ "${QUADLET_UPDATED}" -eq 1 ]; then
    echo "⚙️ Rechargement du démon systemd utilisateur (Quadlet generator)..."
    systemctl --user daemon-reload
fi

# 6. Redémarrage ciblé STRICTEMENT limité aux seuls services impactés
if [ ${#RESTARTED_SERVICES[@]} -gt 0 ]; then
    UNIQUE_SERVICES=$(echo "${RESTARTED_SERVICES[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' ')
    for svc in ${UNIQUE_SERVICES}; do
        echo "🚀 Redémarrage du service impacté : ${svc}"
        systemctl --user restart "${svc}" || true
    done
    MSG="Homelab mis à jour (${REMOTE_HASH:0:7}) - Services redémarrés : ${UNIQUE_SERVICES}"
else
    MSG="Homelab mis à jour (${REMOTE_HASH:0:7}) - Aucun service à redémarrer."
fi

echo "✅ ${MSG}"

# 7. Notification ntfy (si configuré)
if [ -n "${NTFY_TOPIC:-}" ]; then
    NTFY_URL="${NTFY_SERVER_URL:-https://ntfy.sh}/${NTFY_TOPIC}"
    curl -s -H "Title: 🚀 Homelab GitOps Sync" -d "${MSG}" "${NTFY_URL}" || true
fi
