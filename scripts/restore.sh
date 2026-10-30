#!/usr/bin/env bash
# ==============================================================================
# Disaster Recovery & Restore Script for Homelab
# Restores PostgreSQL dumps, application volumes, and starts Quadlet services.
# ==============================================================================
set -euo pipefail

BACKUP_VAULT="/mnt/backup_vault"
HOMELAB_DIR="${HOME}/homelab"
QUADLET_DEST="${HOME}/.config/containers/systemd"

echo "=============================================================================="
echo "🚀 Homelab Disaster Recovery & Restoration Starting..."
echo "=============================================================================="

# 0. Safety Checks
if [ ! -d "${BACKUP_VAULT}/postgres" ]; then
    echo "❌ Error: ${BACKUP_VAULT}/postgres not found. Is /mnt/backup_vault mounted?" >&2
    exit 1
fi

if [ ! -f "${HOMELAB_DIR}/data/postgres.env" ]; then
    echo "❌ Error: ${HOMELAB_DIR}/data/postgres.env missing! Please copy your .env files first." >&2
    exit 1
fi

mkdir -p "${QUADLET_DEST}"

# 1. State Volumes to Restore (Volume Name : Subdirectory : Label)
ARCHIVE_VOLUMES=(
    "apps_vaultwarden_data:vaultwarden:Vaultwarden"
    "apps_actual_budget_data:actualbudget:Actual Budget"
    "apps_nextcloud_html:nextcloud:Nextcloud HTML"
    "apps_forgejo_data:forgejo:Forgejo"
    "apps_linkding_data:linkding:Linkding"
    "apps_ntfy_data:ntfy:ntfy"
    "apps_grafana_data:grafana:Grafana"
    "apps_wakapi_data:wakapi:Wakapi"
    "apps_diun_data:diun:Diun"
)

echo "==> [1/6] Restoring state volumes from tar.gz archives..."
for entry in "${ARCHIVE_VOLUMES[@]}"; do
    IFS=":" read -r volume subdir label <<< "${entry}"
    latest_archive=$(ls -t "${BACKUP_VAULT}/${subdir}"/*.tar.gz 2>/dev/null | head -1 || true)
    
    if [ -n "${latest_archive}" ] && [ -f "${latest_archive}" ]; then
        echo "📦 Restoring ${label} (${volume}) from $(basename "${latest_archive}")..."
        podman volume create "${volume}" >/dev/null 2>&1 || true
        podman run --rm \
            --security-opt label=disable \
            --volume "${volume}:/data:z" \
            --volume "${BACKUP_VAULT}/${subdir}:/backup:ro" \
            docker.io/alpine:3.22 \
            tar -xzf "/backup/$(basename "${latest_archive}")" -C /data
        echo "✓ ${label} restored."
    else
        echo "⏭️  No archive found for ${label} in ${subdir}/ — creating clean volume."
        podman volume create "${volume}" >/dev/null 2>&1 || true
    fi
done

# 2. Large Media Volumes (rsync)
INCREMENTAL_VOLUMES=(
    "apps_nextcloud_data:nextcloud_data:Nextcloud Data"
    "apps_immich_library:immich_library:Immich Library"
)

echo "==> [2/6] Restoring large media volumes (rsync)..."
for entry in "${INCREMENTAL_VOLUMES[@]}"; do
    IFS=":" read -r volume subdir label <<< "${entry}"
    source_dir="${BACKUP_VAULT}/${subdir}/current"
    
    if [ -d "${source_dir}" ]; then
        echo "📂 Restoring ${label} (${volume}) from ${source_dir}..."
        podman volume create "${volume}" >/dev/null 2>&1 || true
        podman run --rm \
            --security-opt label=disable \
            --volume "${volume}:/data:z" \
            --volume "${source_dir}:/backup:ro" \
            docker.io/alpine:3.22 \
            sh -c "apk add --no-cache rsync >/dev/null 2>&1 && rsync -a --delete /backup/ /data/"
        echo "✓ ${label} restored."
    else
        echo "⏭️  Directory ${source_dir} not present — creating clean volume."
        podman volume create "${volume}" >/dev/null 2>&1 || true
    fi
done

# 3. Deploy Quadlet Units
echo "==> [3/6] Deploying Quadlet units into ~/.config/containers/systemd/..."
cp -r "${HOMELAB_DIR}"/infra/quadlet/* "${QUADLET_DEST}/" 2>/dev/null || true
cp -r "${HOMELAB_DIR}"/data/quadlet/* "${QUADLET_DEST}/" 2>/dev/null || true
cp -r "${HOMELAB_DIR}"/apps/quadlet/* "${QUADLET_DEST}/" 2>/dev/null || true

systemctl --user daemon-reload
echo "✓ Systemd user daemon reloaded with Quadlet generator."

# 4. Start PostgreSQL and Restore Database Dump
echo "==> [4/6] Initializing PostgreSQL and restoring logical dump..."
systemctl --user start postgres.service

echo "⏳ Waiting for PostgreSQL container to become ready..."
for i in {1..30}; do
    if podman container exists postgres-db && [ "$(podman inspect postgres-db --format '{{.State.Health.Status}}' 2>/dev/null)" = "healthy" ]; then
        echo "✓ PostgreSQL is healthy."
        break
    fi
    sleep 2
done

LATEST_PG_DUMP=$(ls -t "${BACKUP_VAULT}/postgres"/pg_dumpall_*.sql.gz 2>/dev/null | head -1 || true)
if [ -n "${LATEST_PG_DUMP}" ]; then
    echo "📥 Injecting $(basename "${LATEST_PG_DUMP}") into PostgreSQL..."
    PG_USER=$(podman exec postgres-db printenv POSTGRES_USER || echo "postgres")
    zcat "${LATEST_PG_DUMP}" | podman exec -i postgres-db psql -U "${PG_USER}" >/dev/null 2>&1 || true
    echo "✓ Central PostgreSQL dump restored."
else
    echo "⚠️  No PostgreSQL dump found in ${BACKUP_VAULT}/postgres/ !"
fi

# 4b. Restore Immich PostgreSQL (if dump exists)
LATEST_IMMICH_DUMP=$(ls -t "${BACKUP_VAULT}/immich"/immich_db_*.sql.gz 2>/dev/null | head -1 || true)
if [ -n "${LATEST_IMMICH_DUMP}" ] && [ -f "${HOMELAB_DIR}/apps/quadlet/immich-postgres.container" ]; then
    echo "📥 Restoring Immich Vector Database..."
    systemctl --user start immich-postgres.service || true
    sleep 5
    zcat "${LATEST_IMMICH_DUMP}" | podman exec -i immich-postgres psql -U postgres >/dev/null 2>&1 || true
    echo "✓ Immich database restored."
fi

# 5. Start Core Services
echo "==> [5/6] Starting application services..."
SERVICES=(
    "homelab-network"
    "cloudflared"
    "twingate-connector"
    "twingate-host"
    "vaultwarden"
    "actual-budget"
    "nextcloud-redis"
    "nextcloud"
    "glance"
    "linkding"
    "forgejo"
    "ntfy"
    "prometheus"
    "grafana"
    "node-exporter"
    "podman-exporter"
)

for svc in "${SERVICES[@]}"; do
    if systemctl --user list-unit-files "${svc}.service" >/dev/null 2>&1; then
        echo "🚀 Starting ${svc}..."
        systemctl --user start "${svc}" || echo "⚠️  Could not start ${svc}"
    fi
done

# 6. Enable Automation Timers
echo "==> [6/6] Installing automated backup & sync timers..."
mkdir -p "${HOME}/.config/systemd/user"
cp -r "${HOMELAB_DIR}"/scripts/systemd/*.service "${HOME}/.config/systemd/user/" 2>/dev/null || true
cp -r "${HOMELAB_DIR}"/scripts/systemd/*.timer "${HOME}/.config/systemd/user/" 2>/dev/null || true
systemctl --user daemon-reload
systemctl --user enable --now backup.timer || true
systemctl --user enable --now homelab-sync.timer || true
systemctl --user enable --now nextcloud-cron.timer || true

echo ""
echo "=============================================================================="
echo "🎉 Full Homelab Restoration Complete!"
echo "Check running containers with: podman ps"
echo "Check Glance dashboard or Cockpit at: https://192.168.1.18:9090"
echo "=============================================================================="
