#!/usr/bin/env bash
# ==============================================================================
# scripts/02-desktop-theme.sh
# Konfigurasi IceWM Windows-Friendly, Modul FT10, Font, dan Papirus Icon Theme
# Refactored: Preservasi Hak Akses User-Space (Anti Permission-Trap)
# ==============================================================================
set -euo pipefail

# 1. Verifikasi Hak Akses Root
if [[ $EUID -ne 0 ]]; then
    echo -e "\e[31m[ERROR] Skrip 02-desktop-theme.sh harus dijalankan sebagai root (sudo)!\e[0m" >&2
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

echo -e "\e[34m[02-THEME]\e[0m Mengonfigurasi antarmuka untuk pengguna: \e[33m${TARGET_USER}\e[0m"
echo -e "  -> Home target: \e[33m${TARGET_HOME}\e[0m"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y

# 3. Instalasi Paket Tema di Level Sistem
echo -e "\e[34m[02-THEME]\e[0m Memasang papirus-icon-theme dan font sans di level sistem..."
apt-get install --no-install-recommends -y \
    papirus-icon-theme \
    fonts-liberation \
    fonts-dejavu-core

# Periksa paket FT10 dari repository antiX
echo -e "\e[34m[02-THEME]\e[0m Memeriksa dan menginstal paket modul FT10 antiX..."
if apt-cache search "^ft10-transformation" | grep -q "ft10-transformation"; then
    apt-get install --no-install-recommends -y ft10-transformation || true
elif apt-cache search "^ft10" | grep -q "^ft10"; then
    apt-get install --no-install-recommends -y ft10 || true
fi

# 4. Fungsi Konfigurasi File Lingkungan GTK & IceWM
apply_theme_configs() {
    local target_dir="$1"
    local owner="$2"
    local group="$3"

    mkdir -p "${target_dir}/.icewm"
    mkdir -p "${target_dir}/.config/gtk-3.0"

    # Konfigurasi GTK 2.0
    cat << 'EOF' > "${target_dir}/.gtkrc-2.0"
# antiX Remote Station - Low RAM GTK2 Configuration
gtk-icon-theme-name="Papirus"
gtk-font-name="Liberation Sans 10"
gtk-toolbar-style=GTK_TOOLBAR_ICONS
gtk-toolbar-icon-size=GTK_ICON_SIZE_SMALL_TOOLBAR
gtk-button-images=1
gtk-menu-images=1
gtk-enable-event-sounds=0
gtk-enable-input-feedback-sounds=0
EOF

    # Konfigurasi GTK 3.0
    cat << 'EOF' > "${target_dir}/.config/gtk-3.0/settings.ini"
[Settings]
gtk-icon-theme-name=Papirus
gtk-font-name=Liberation Sans 10
gtk-application-prefer-dark-theme=0
gtk-toolbar-style=GTK_TOOLBAR_ICONS
gtk-toolbar-icon-size=GTK_ICON_SIZE_SMALL_TOOLBAR
gtk-button-images=1
gtk-menu-images=1
gtk-enable-event-sounds=0
gtk-enable-input-feedback-sounds=0
EOF

    # Konfigurasi IceWM Preferences (Taskbar bawah gaya Windows)
    local icewm_pref="${target_dir}/.icewm/preferences"
    if [[ ! -f "$icewm_pref" && -f "/etc/X11/icewm/preferences" ]]; then
        cp "/etc/X11/icewm/preferences" "$icewm_pref"
    fi

    cat << 'EOF' >> "${target_dir}/.icewm/preferences"

# --- antiX Remote Station Low-RAM Overrides ---
TaskBarAtTop=0
TaskBarShowClock=1
TaskBarShowTray=1
TaskBarShowWindowListMenu=0
TaskBarShowWorkspacesButtons=0
TaskBarShowShowDesktopButton=1
TaskBarShowAPMStatus=0
TaskBarShowMailBoxStatus=0
TaskBarShowMEMStatus=1
TaskBarShowCPUStatus=1
TaskBarShowNetStatus=0
ClockFormat="%H:%M"
IconPath="/usr/share/icons/Papirus/48x48/apps:/usr/share/icons/Papirus/24x24/apps:/usr/share/icons/Papirus/16x16/apps:/usr/share/pixmaps"
MenuMouseTracking=1
ShowThemesMenu=0
ShowHelp=0
EOF

    # Hook startup FT10 pada IceWM
    local startup_file="${target_dir}/.icewm/startup"
    touch "$startup_file"
    if ! grep -q "ft10" "$startup_file"; then
        cat << 'EOF' >> "$startup_file"

# Aktifkan FT10 Taskbar jika terpasang
if command -v ft10-enable >/dev/null 2>&1; then
    ft10-enable &
elif command -v ft10 >/dev/null 2>&1; then
    ft10 &
fi
EOF
    fi
    chmod 755 "$startup_file"

    if [[ -n "$owner" && -n "$group" ]]; then
        chown -R "${owner}:${group}" \
            "${target_dir}/.gtkrc-2.0" \
            "${target_dir}/.config" \
            "${target_dir}/.icewm"
    fi
}

# 5. Terapkan ke Akun Target User dan Template /etc/skel
echo -e "\e[34m[02-THEME]\e[0m Menerapkan konfigurasi tema ke ${TARGET_HOME}..."
apply_theme_configs "$TARGET_HOME" "$TARGET_USER" "$TARGET_GROUP"

echo -e "\e[34m[02-THEME]\e[0m Menerapkan template ke /etc/skel..."
apply_theme_configs "/etc/skel" "root" "root"

# 6. Aktifkan FT10 via konteks user murni
if command -v ft10-enable >/dev/null 2>&1; then
    echo -e "\e[34m[02-THEME]\e[0m Mengaktifkan modul FT10 melalui sudo -u ${TARGET_USER}..."
    sudo -u "$TARGET_USER" ft10-enable 2>/dev/null || true
fi

# 7. Pembersihan Cache APT
apt-get autoremove --purge -y
apt-get clean
rm -rf /var/lib/apt/lists/*

echo -e "\e[32m[02-THEME] Selesai dengan sukses.\e[0m"
