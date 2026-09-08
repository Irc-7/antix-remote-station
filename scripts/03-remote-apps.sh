#!/usr/bin/env bash
# ==============================================================================
# scripts/03-remote-apps.sh
# Instalasi AnyDesk Linux (.deb) Resmi Sesuai Arsitektur & Integrasi FT10/IceWM
# Refactored: Preservasi Hak Akses User-Space (Anti Permission-Trap)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 1. Verifikasi Hak Akses Root
if [[ $EUID -ne 0 ]]; then
    echo -e "\e[31m[ERROR] Skrip 03-remote-apps.sh harus dijalankan sebagai root (sudo)!\e[0m" >&2
    exit 1
fi

# 2. Deteksi Deterministik Target Non-Root User & Home
TARGET_USER="${TARGET_USER:-${SUDO_USER:-$USER}}"
if [[ "$TARGET_USER" == "root" ]]; then
    REGULAR_USER="$(awk -F: '$3 >= 1000 && $3 < 60000 {print $1; exit}' /etc/passwd || true)"
    if [[ -n "$REGULAR_USER" ]]; then
        TARGET_USER="$REGULAR_USER"
    else
        echo -e "\e[31m[ERROR] Tidak ditemukan user reguler pada sistem!\e[0m" >&2
        exit 1
    fi
fi

TARGET_HOME="${TARGET_HOME:-$(getent passwd "$TARGET_USER" | cut -d: -f6)}"
TARGET_GROUP="${TARGET_GROUP:-$(id -gn "$TARGET_USER" 2>/dev/null || echo "$TARGET_USER")}"

echo -e "\e[34m[03-REMOTE]\e[0m Memulai instalasi AnyDesk untuk: \e[33m${TARGET_USER}\e[0m"
echo -e "  -> Home target: \e[33m${TARGET_HOME}\e[0m"

export DEBIAN_FRONTEND=noninteractive
ARCH="$(dpkg --print-architecture)"
echo -e "  -> Arsitektur CPU terdeteksi: \e[33m${ARCH}\e[0m"

# Pastikan paket dependensi instalasi tersedia di level sistem
apt-get update -y
apt-get install --no-install-recommends -y curl wget gnupg ca-certificates

# 3. Instalasi AnyDesk di Level Sistem (Root Context)
echo -e "\e[34m[03-REMOTE]\e[0m Memasang repository AnyDesk..."
INSTALL_SUCCESS=0

mkdir -p /etc/apt/trusted.gpg.d
if curl -fsSL https://keys.anydesk.com/repos/DEB-GPG-KEY | gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/anydesk.gpg; then
    echo "deb http://deb.anydesk.com/ all main" > /etc/apt/sources.list.d/anydesk-stable.list
    apt-get update -y || true
    if apt-get install --no-install-recommends -y anydesk; then
        INSTALL_SUCCESS=1
    fi
fi

# Fallback: Unduhan langsung jika repository APT gagal
if [[ $INSTALL_SUCCESS -eq 0 ]]; then
    echo -e "\e[33m[03-REMOTE] Repository resmi tidak merespons, mencoba unduh binary langsung...\e[0m"
    TEMP_DIR="$(mktemp -d)"
    DEB_URL=""
    if [[ "$ARCH" == "amd64" ]]; then
        DEB_URL="https://download.anydesk.com/linux/anydesk_6.3.3-1_amd64.deb"
    elif [[ "$ARCH" == "i386" ]]; then
        DEB_URL="https://download.anydesk.com/linux/anydesk_6.3.3-1_i386.deb"
    elif [[ "$ARCH" == "armhf" ]]; then
        DEB_URL="https://download.anydesk.com/linux/anydesk_6.3.3-1_armhf.deb"
    elif [[ "$ARCH" == "arm64" ]]; then
        DEB_URL="https://download.anydesk.com/linux/anydesk_6.3.3-1_arm64.deb"
    fi

    if [[ -n "$DEB_URL" ]]; then
        if curl -fsSL "$DEB_URL" -o "${TEMP_DIR}/anydesk.deb"; then
            apt-get install --no-install-recommends -y "${TEMP_DIR}/anydesk.deb" || {
                dpkg -i "${TEMP_DIR}/anydesk.deb" || true
                apt-get install -f --no-install-recommends -y
            }
            INSTALL_SUCCESS=1
        fi
    fi
    rm -rf "$TEMP_DIR"
fi

if ! command -v anydesk >/dev/null 2>&1; then
    echo -e "\e[31m[ERROR] Instalasi AnyDesk gagal. Periksa koneksi internet!\e[0m" >&2
    exit 1
fi
echo -e "\e[32m[03-REMOTE] AnyDesk berhasil terpasang di sistem.\e[0m"

# 4. Desktop Entry Sistem (/usr/share/applications/)
cp "${REPO_ROOT}/desktop-entries/anydesk.desktop" /usr/share/applications/anydesk.desktop
chmod 644 /usr/share/applications/anydesk.desktop

# 5. Integrasi Shortcut Pengguna (User-Space)
USER_DESKTOP="${TARGET_HOME}/Desktop"
sudo -u "$TARGET_USER" mkdir -p "$USER_DESKTOP"
cp "${REPO_ROOT}/desktop-entries/anydesk.desktop" "${USER_DESKTOP}/anydesk.desktop"
chmod 755 "${USER_DESKTOP}/anydesk.desktop"
chown "${TARGET_USER}:${TARGET_GROUP}" "${USER_DESKTOP}/anydesk.desktop"

# Shortcut di ~/.local/share/applications
USER_APPS="${TARGET_HOME}/.local/share/applications"
sudo -u "$TARGET_USER" mkdir -p "$USER_APPS"
cp "${REPO_ROOT}/desktop-entries/anydesk.desktop" "${USER_APPS}/anydesk.desktop"
chmod 644 "${USER_APPS}/anydesk.desktop"
chown "${TARGET_USER}:${TARGET_GROUP}" "${USER_APPS}/anydesk.desktop"

# Pin ke taskbar IceWM toolbar
USER_ICEWM_TOOLBAR="${TARGET_HOME}/.icewm/toolbar"
sudo -u "$TARGET_USER" mkdir -p "${TARGET_HOME}/.icewm"
sudo -u "$TARGET_USER" touch "$USER_ICEWM_TOOLBAR"

if ! grep -q "anydesk" "$USER_ICEWM_TOOLBAR"; then
    echo 'prog "AnyDesk" anydesk anydesk' >> "$USER_ICEWM_TOOLBAR"
fi
chown "${TARGET_USER}:${TARGET_GROUP}" "$USER_ICEWM_TOOLBAR"

# Integrasi ke launcher FT10 / Tint2 jika file tint2rc ada
FT10_TINT2_CONF="${TARGET_HOME}/.config/tint2/tint2rc"
if [[ -f "$FT10_TINT2_CONF" ]]; then
    if ! grep -q "anydesk.desktop" "$FT10_TINT2_CONF"; then
        sed -i '/launcher_item_app = /a launcher_item_app = \/usr\/share\/applications\/anydesk.desktop' "$FT10_TINT2_CONF" || true
        chown "${TARGET_USER}:${TARGET_GROUP}" "$FT10_TINT2_CONF"
    fi
fi

# 6. Pembersihan APT Cache
apt-get autoremove --purge -y
apt-get clean
rm -rf /var/lib/apt/lists/*

echo -e "\e[32m[03-REMOTE] Selesai dengan sukses.\e[0m"
