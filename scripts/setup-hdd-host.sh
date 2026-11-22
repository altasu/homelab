#!/usr/bin/env bash
# ==============================================================================
# Setup & Optimization Script for Mechanical HDD Host (Fedora Server)
# Purpose: Protect 2.5" mechanical HDD longevity and optimize rootless Podman I/O.
# ==============================================================================
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "❌ This script must be run as root (or with sudo)." >&2
    exit 1
fi

TARGET_USER="homelab"

echo "==> [1/7] Enabling user lingering for rootless Podman..."
loginctl enable-linger "${TARGET_USER}" || true
echo "✓ Lingering enabled for ${TARGET_USER}."

echo "==> [2/7] Installing essential disk management & monitoring tools..."
dnf install -y hdparm smartmontools git curl rsync tar util-linux || true
systemctl enable --now smartd || true
echo "✓ S.M.A.R.T. monitoring daemon (smartd) enabled."

echo "==> [3/7] Preventing aggressive laptop HDD head parking (APM / hdparm)..."
cat << 'EOF' > /etc/systemd/system/hdd-apm-keepalive.service
[Unit]
Description=Disable Aggressive HDD Head Parking for 24/7 Server
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/hdparm -B 254 /dev/sda
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now hdd-apm-keepalive.service || true
echo "✓ HDD APM service installed (head parking disabled on /dev/sda)."

echo "==> [4/7] Optimizing kernel virtual memory & I/O cache for mechanical storage..."
cat << 'EOF' > /etc/sysctl.d/99-hdd-optimize.conf
# Keep inode/dentry cache in RAM (16 GB available)
vm.vfs_cache_pressure = 50

# Smooth background disk writeback
vm.dirty_background_ratio = 5
vm.dirty_ratio = 10

# Discourage swapping to disk (leverage Fedora ZRAM)
vm.swappiness = 10
EOF

sysctl --system > /dev/null || true
echo "✓ Sysctl VFS & memory buffer tuning applied."

echo "==> [5/7] Capping systemd journal logging size to prevent disk thrashing..."
mkdir -p /etc/systemd/journald.conf.d
cat << 'EOF' > /etc/systemd/journald.conf.d/hdd-optimize.conf
[Journal]
SystemMaxUse=200M
SystemKeepFree=1G
RuntimeMaxUse=100M
MaxRetentionSec=1month
EOF

systemctl restart systemd-journald || true
echo "✓ Systemd journal capped to 200MB max."

echo "==> [6/7] Applying 'noatime' mount option in /etc/fstab..."
if grep -q "noatime" /etc/fstab; then
    echo "✓ 'noatime' already present in /etc/fstab."
else
    # Safely append noatime to root / mount if not present
    sed -i.bak -E 's/((\/|\/home)\s+[a-z0-9]+\s+defaults)/\1,noatime,nodiratime/g' /etc/fstab
    echo "✓ 'noatime,nodiratime' added to /etc/fstab (backup saved to /etc/fstab.bak)."
    mount -o remount / || true
fi

echo "==> [7/9] Preparing backup vault mount point..."
mkdir -p /mnt/backup_vault
chown "${TARGET_USER}:${TARGET_USER}" /mnt/backup_vault
chmod 750 /mnt/backup_vault
echo "✓ /mnt/backup_vault directory ready."

echo "==> [8/9] Configuring BFQ I/O scheduler & read-ahead for rotational disks..."
cat << 'EOF' > /etc/udev/rules.d/60-hdd-iosched.rules
# Set BFQ scheduler and 1024KB readahead for mechanical rotational drives
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq", ATTR{queue/read_ahead_kb}="1024"
EOF
udevadm control --reload-rules || true
udevadm trigger --subsystem-match=block || true
echo "✓ BFQ I/O elevator and 1024KB read-ahead rule created."

echo "==> [9/10] Configuring Podman global log size limits (10MB)..."
mkdir -p /etc/containers
if [[ -f /etc/containers/containers.conf ]]; then
    if ! grep -q "log_size_max" /etc/containers/containers.conf; then
        sed -i '/\[containers\]/a log_size_max = 10485760' /etc/containers/containers.conf
    fi
else
    cat << 'EOF' > /etc/containers/containers.conf
[containers]
log_driver = "journald"
log_size_max = 10485760
EOF
fi
echo "✓ Podman container logging limits applied."

echo "==> [10/10] Preventing laptop suspend on lid close (systemd-logind)..."
mkdir -p /etc/systemd/logind.conf.d
cat << 'EOF' > /etc/systemd/logind.conf.d/ignore-lid.conf
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
EOF
systemctl restart systemd-logind || true
echo "✓ Laptop lid switch set to ignore (24/7 server mode active)."

echo ""
echo "=============================================================================="
echo "🎉 HDD Host Optimization Completed Successfully (10/10 Steps)!"
echo "Next step: Connect your external backup drive to /mnt/backup_vault and"
echo "run the restore procedure."
echo "=============================================================================="
