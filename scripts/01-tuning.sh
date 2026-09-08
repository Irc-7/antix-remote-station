#!/usr/bin/env bash
# ==============================================================================
# scripts/01-tuning.sh
# Tuning Kernel, zRAM, EarlyOOM, dan Pembersihan Bloat Daemon (RAM 1 GB)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Pengecekan hak akses root
if [[ $EUID -ne 0 ]]; then
    echo -e "\e[31m[ERROR] Skrip 01-tuning.sh harus dijalankan dengan hak akses root (sudo)!\e[0m" >&2
    exit 1
fi

echo -e "\e[34m[01-TUNING]\e[0m Memulai proses kernel tuning dan optimasi low-RAM..."

# 1. Update paket database minimal
export DEBIAN_FRONTEND=noninteractive
apt-get update -y

# 2. Instalasi zram-tools dan earlyoom dengan zero-bloat flag
echo -e "\e[34m[01-TUNING]\e[0m Memasang zram-tools dan earlyoom..."
apt-get install --no-install-recommends -y zram-tools earlyoom

# 3. Konfigurasi sysctl low-RAM
echo -e "\e[34m[01-TUNING]\e[0m Menerapkan parameter kernel di /etc/sysctl.d/99-lowram-tuning.conf..."
cp "${REPO_ROOT}/configs/sysctl.d/99-lowram-tuning.conf" /etc/sysctl.d/99-lowram-tuning.conf
chmod 644 /etc/sysctl.d/99-lowram-tuning.conf
sysctl -p /etc/sysctl.d/99-lowram-tuning.conf || sysctl --system

# 4. Konfigurasi EarlyOOM
echo -e "\e[34m[01-TUNING]\e[0m Mengonfigurasi /etc/default/earlyoom..."
cp "${REPO_ROOT}/configs/earlyoom/earlyoom.default" /etc/default/earlyoom
chmod 644 /etc/default/earlyoom

# 5. Konfigurasi zRAM (zramswap)
echo -e "\e[34m[01-TUNING]\e[0m Mengonfigurasi zramswap (/etc/default/zramswap)..."
cat << 'EOF' > /etc/default/zramswap
# Konfigurasi zramswap antiX Remote Station
ALGO=zstd
PERCENT=100
PRIORITY=100
EOF
chmod 644 /etc/default/zramswap

# 6. Helper multi-init untuk menghentikan dan menonaktifkan service (SysVinit, Runit, systemd)
disable_and_stop_service() {
    local svc="$1"
    echo -e "  -> Mendisposisi service: ${svc}..."

    # Systemd handling (jika aktif)
    if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
        systemctl stop "${svc}" 2>/dev/null || true
        systemctl disable "${svc}" 2>/dev/null || true
        systemctl mask "${svc}" 2>/dev/null || true
    fi

    # SysVinit handling
    if [[ -x "/etc/init.d/${svc}" ]]; then
        "/etc/init.d/${svc}" stop 2>/dev/null || true
        update-rc.d -f "${svc}" remove 2>/dev/null || true
        # Berikan status non-executable agar tidak dieksekusi saat boot
        chmod -x "/etc/init.d/${svc}" 2>/dev/null || true
    fi

    # Runit handling (antiX runit edition)
    if [[ -d "/etc/runit/runsvdir/current/${svc}" ]]; then
        if command -v sv >/dev/null 2>&1; then
            sv down "${svc}" 2>/dev/null || true
        fi
        rm -f "/etc/runit/runsvdir/current/${svc}" 2>/dev/null || true
    fi
}

start_and_enable_service() {
    local svc="$1"
    echo -e "  -> Mengaktifkan service: ${svc}..."

    # Systemd
    if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
        systemctl unmask "${svc}" 2>/dev/null || true
        systemctl enable "${svc}" 2>/dev/null || true
        systemctl restart "${svc}" 2>/dev/null || true
        return
    fi

    # SysVinit
    if [[ -f "/etc/init.d/${svc}" ]]; then
        chmod +x "/etc/init.d/${svc}" 2>/dev/null || true
        update-rc.d "${svc}" defaults 2>/dev/null || true
        service "${svc}" restart 2>/dev/null || "/etc/init.d/${svc}" restart 2>/dev/null || true
    fi

    # Runit
    if [[ -d "/etc/sv/${svc}" && -d "/etc/runit/runsvdir/current" ]]; then
        ln -sf "/etc/sv/${svc}" "/etc/runit/runsvdir/current/${svc}"
        if command -v sv >/dev/null 2>&1; then
            sv up "${svc}" 2>/dev/null || true
        fi
    fi
}

# 7. Nonaktifkan daemon bloat yang tidak diperlukan
echo -e "\e[34m[01-TUNING]\e[0m Mematikan daemon printer, bluetooth, dan scanner..."
SERVICES_TO_KILL=(
    "cups"
    "cups-browsed"
    "bluetooth"
    "bluez"
    "saned"
    "avahi-daemon"
    "modemmanager"
    "smartmontools"
    "rpcbind"
)

for s in "${SERVICES_TO_KILL[@]}"; do
    disable_and_stop_service "$s"
done

# 8. Start & Enable service zramswap dan earlyoom
echo -e "\e[34m[01-TUNING]\e[0m Mengaktifkan layanan zramswap dan earlyoom..."
start_and_enable_service "zramswap"
start_and_enable_service "earlyoom"

# 9. Pembersihan total cache APT (Zero-Bloat Cleanup)
echo -e "\e[34m[01-TUNING]\e[0m Melakukan pembersihan total APT cache..."
apt-get autoremove --purge -y
apt-get clean
rm -rf /var/lib/apt/lists/*

echo -e "\e[32m[01-TUNING] Selesai dengan sukses.\e[0m"
