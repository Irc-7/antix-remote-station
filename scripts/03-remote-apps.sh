#!/usr/bin/env bash
# ==============================================================================
# scripts/03-remote-apps.sh
# Instalasi AnyDesk Linux (.deb) Resmi Sesuai Arsitektur & Integrasi FT10/IceWM
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Verifikasi hak akses root
if [[ $EUID -ne 0 ]]; then
    echo -e "\e[31m[ERROR] Skrip 03-remote-apps.sh harus dijalankan sebagai root (sudo)!\e[0m" >&2
    exit 1
fi

TARGET_USER="${SUDO_USER:-}"
if [[ -z "$TARGET_USER" || "$TARGET_USER" == "root" ]]; then
    TARGET_USER="$(awk -F: '$3 >= 1000 && $3 < 60000 {print $1; exit}' /etc/passwd || echo "demo")"
fi
USER_HOME="$(eval echo "~${TARGET_USER}")"
TARGET_GROUP="$(id -gn "$TARGET_USER" 2>/dev/null || echo "$TARGET_USER")"

echo -e "\e[34m[03-REMOTE]\e[0m Memulai instalasi AnyDesk untuk arsitektur sistem..."

export DEBIAN_FRONTEND=noninteractive
ARCH="$(dpkg --print-architecture)"
echo -e "  -> Arsitektur terdeteksi: \e[33m${ARCH}\e[0m"

# Pastikan utilitas pendukung (curl/wget, gnupg) terpasang
apt-get update -y
apt-get install --no-install-recommends -y curl wget gnupg ca-certificates

# 1. Menambahkan GPG Key resmi dan Repository AnyDesk
echo -e "\e[34m[03-REMOTE]\e[0m Menambahkan repository resmi AnyDesk..."
INSTALL_SUCCESS=0

mkdir -p /etc/apt/trusted.gpg.d
if curl -fsSL https://keys.anydesk.com/repos/DEB-GPG-KEY | gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/anydesk.gpg; then
    echo "deb http://deb.anydesk.com/ all main" > /etc/apt/sources.list.d/anydesk-stable.list
    apt-get update -y || true
    if apt-get install --no-install-recommends -y anydesk; then
        INSTALL_SUCCESS=1
    fi
fi

# Fallback: jika repo gagal dijangkau, unduh paket .deb mandiri sesuai arsitektur
if [[ $INSTALL_SUCCESS -eq 0 ]]; then
    echo -e "\e[33m[03-REMOTE] Repo online gagal, mencoba fallback unduhan langsung paket .deb...\e[0m"
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
        echo -e "  -> Mengunduh dari: ${DEB_URL}"
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
    echo -e "\e[31m[ERROR] Gagal memasang AnyDesk. Periksa koneksi jaringan atau repositori.\e[0m" >&2
    exit 1
fi
echo -e "\e[32m[03-REMOTE] AnyDesk berhasil terpasang di sistem.\e[0m"

# 2. Salin dan konfigurasikan file desktop entry
echo -e "\e[34m[03-REMOTE]\e[0m Mengonfigurasi shortcut dan pin taskbar..."
cp "${REPO_ROOT}/desktop-entries/anydesk.desktop" /usr/share/applications/anydesk.desktop
chmod 644 /usr/share/applications/anydesk.desktop

# Shortcut di desktop user
USER_DESKTOP="${USER_HOME}/Desktop"
mkdir -p "$USER_DESKTOP"
cp "${REPO_ROOT}/desktop-entries/anydesk.desktop" "${USER_DESKTOP}/anydesk.desktop"
chmod +x "${USER_DESKTOP}/anydesk.desktop"
chown -R "${TARGET_USER}:${TARGET_GROUP}" "$USER_DESKTOP"

# 3. Pin AnyDesk ke taskbar IceWM toolbar
USER_ICEWM_TOOLBAR="${USER_HOME}/.icewm/toolbar"
mkdir -p "${USER_HOME}/.icewm"
touch "$USER_ICEWM_TOOLBAR"

if ! grep -q "anydesk" "$USER_ICEWM_TOOLBAR"; then
    echo 'prog "AnyDesk" anydesk anydesk' >> "$USER_ICEWM_TOOLBAR"
fi
chown "${TARGET_USER}:${TARGET_GROUP}" "$USER_ICEWM_TOOLBAR"

# 4. Integrasikan ke launcher FT10 / Tint2 jika konfigurasinya ada
FT10_TINT2_CONF="${USER_HOME}/.config/tint2/tint2rc"
if [[ -f "$FT10_TINT2_CONF" ]]; then
    if ! grep -q "anydesk.desktop" "$FT10_TINT2_CONF"; then
        # Sisipkan launcher anydesk sebelum baris end of launchers
        sed -i '/launcher_item_app = /a launcher_item_app = \/usr\/share\/applications\/anydesk.desktop' "$FT10_TINT2_CONF" || true
    fi
fi

# 5. Pembersihan APT Cache
apt-get autoremove --purge -y
apt-get clean
rm -rf /var/lib/apt/lists/*

echo -e "\e[32m[03-REMOTE] Selesai dengan sukses.\e[0m"
