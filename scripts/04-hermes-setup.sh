#!/usr/bin/env bash
# ==============================================================================
# scripts/04-hermes-setup.sh
# Isolasi Virtualenv Python, Zero-Compilation Pip, dan Integrasi Hermes Agent CLI
# Refactored: Eksekusi User-Space Terisolasi (Anti Permission-Trap)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 1. Verifikasi Hak Akses Root
if [[ $EUID -ne 0 ]]; then
    echo -e "\e[31m[ERROR] Skrip 04-hermes-setup.sh harus dijalankan sebagai root (sudo)!\e[0m" >&2
    exit 1
fi

# 2. Deteksi Deterministik Target Non-Root User & Home
TARGET_USER="${TARGET_USER:-${SUDO_USER:-$USER}}"
if [[ "$TARGET_USER" == "root" ]]; then
    REGULAR_USER="$(awk -F: '$3 >= 1000 && $3 < 60000 {print $1; exit}' /etc/passwd || true)"
    if [[ -n "$REGULAR_USER" ]]; then
        TARGET_USER="$REGULAR_USER"
    else
        echo -e "\e[31m[ERROR] Tidak dapat menentukan non-root user reguler!\e[0m" >&2
        exit 1
    fi
fi

TARGET_HOME="${TARGET_HOME:-$(getent passwd "$TARGET_USER" | cut -d: -f6)}"
TARGET_GROUP="${TARGET_GROUP:-$(id -gn "$TARGET_USER" 2>/dev/null || echo "$TARGET_USER")}"

echo -e "\e[34m[04-HERMES]\e[0m Menyiapkan environment Hermes Agent CLI untuk: \e[33m${TARGET_USER}\e[0m"
echo -e "  -> Home target: \e[33m${TARGET_HOME}\e[0m"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y

# 3. Instalasi Runtime Python3 & Terminal di Level Sistem (Root Level)
echo -e "\e[34m[04-HERMES]\e[0m Memasang paket sistem Python3, venv, pip, dan roxterm..."
apt-get install --no-install-recommends -y \
    python3 \
    python3-venv \
    python3-pip \
    roxterm \
    nano

# 4. Penyiapan Direktori Aplikasi Sistem (/opt/hermes-station)
APP_DIR="/opt/hermes-station"
mkdir -p "$APP_DIR"
cp -r "${REPO_ROOT}/hermes/"* "$APP_DIR/"
chmod 755 "${APP_DIR}"
chmod 755 "${APP_DIR}/run-hermes.sh"
chown -R root:root "$APP_DIR"
# Modul python dan aset dapat dibaca oleh seluruh user
find "$APP_DIR" -type d -exec chmod 755 {} +
find "$APP_DIR" -type f -exec chmod 644 {} +
chmod 755 "${APP_DIR}/run-hermes.sh"

# 5. Penyiapan Direktori Konfigurasi User & File .env (User-Space)
USER_CONFIG_DIR="${TARGET_HOME}/.config/hermes"
sudo -u "$TARGET_USER" mkdir -p "$USER_CONFIG_DIR"

if [[ ! -f "${USER_CONFIG_DIR}/.env" ]]; then
    echo -e "\e[34m[04-HERMES]\e[0m Menyiapkan template .env untuk pengguna..."
    sudo -u "$TARGET_USER" cp "${APP_DIR}/.env.example" "${USER_CONFIG_DIR}/.env"
fi

# Kunci izin file konfigurasi hanya dapat dibaca/ditulis oleh target user (chmod 600)
chmod 600 "${USER_CONFIG_DIR}/.env"
chown "${TARGET_USER}:${TARGET_GROUP}" "${USER_CONFIG_DIR}/.env"

# 6. Pembuatan Virtual Environment Python (User Context Murni)
VENV_DIR="${TARGET_HOME}/.venv/hermes"
echo -e "\e[34m[04-HERMES]\e[0m Membuat virtual environment di: \e[33m${VENV_DIR}\e[0m..."
sudo -u "$TARGET_USER" mkdir -p "${TARGET_HOME}/.venv"

if [[ ! -f "${VENV_DIR}/bin/activate" ]]; then
    sudo -u "$TARGET_USER" python3 -m venv "${VENV_DIR}"
fi

# 7. Instalasi Dependensi Pip di Bawah Konteks User (Zero-Compilation & No-Cache)
echo -e "\e[34m[04-HERMES]\e[0m Memasang pustaka Python ke user virtualenv (--only-binary=:all: --no-cache-dir)..."
REQUIREMENTS_FILE="${APP_DIR}/requirements.txt"

sudo -u "$TARGET_USER" "${VENV_DIR}/bin/pip" install --no-cache-dir --upgrade pip
sudo -u "$TARGET_USER" "${VENV_DIR}/bin/pip" install --no-cache-dir --only-binary=:all: -r "${REQUIREMENTS_FILE}"

# 8. Pasang Wrapper Global di /usr/local/bin/run-hermes.sh dan ~/.local/bin/
echo -e "\e[34m[04-HERMES]\e[0m Memasang wrapper eksekusi sistem..."
cat << 'EOF' > /usr/local/bin/run-hermes.sh
#!/usr/bin/env bash
# Wrapper eksekusi Hermes Agent CLI dengan pemulihan konteks user aktif
set -e

# Batasi virtual memory 400 MB (409600 KB) untuk mengamankan RAM 1 GB
ulimit -v 409600

CURRENT_USER="$(id -un)"
CURRENT_HOME="$(eval echo "~${CURRENT_USER}")"
VENV_DIR="${CURRENT_HOME}/.venv/hermes"
CONFIG_FILE="${CURRENT_HOME}/.config/hermes/.env"
APP_DIR="/opt/hermes-station"

# Validasi ketersediaan virtualenv
if [[ ! -f "${VENV_DIR}/bin/activate" ]]; then
    echo -e "\e[31m[ERROR] Virtual environment tidak ditemukan di: ${VENV_DIR}\e[0m" >&2
    echo -e "Silakan jalankan ulang master instalasi: sudo /path/to/install.sh" >&2
    read -rp "Tekan Enter untuk keluar..."
    exit 1
fi

# Aktifkan virtualenv user
source "${VENV_DIR}/bin/activate"

# Validasi file konfigurasi .env
if [[ ! -f "$CONFIG_FILE" ]]; then
    mkdir -p "${CURRENT_HOME}/.config/hermes"
    if [[ -f "${APP_DIR}/.env.example" ]]; then
        cp "${APP_DIR}/.env.example" "$CONFIG_FILE"
        chmod 600 "$CONFIG_FILE"
        echo -e "\e[33mFile konfigurasi baru dibuat di: ${CONFIG_FILE}\e[0m"
        echo -e "Silakan edit dan isi HERMES_API_KEY Anda."
    else
        echo -e "\e[31mFile konfigurasi ${CONFIG_FILE} tidak ditemukan!\e[0m" >&2
        read -rp "Tekan Enter untuk keluar..."
        exit 1
    fi
fi

# Muat environment
set -a
# shellcheck disable=SC1090
source "$CONFIG_FILE"
set +a

# Pastikan direktori modul hermes_agent ada di PYTHONPATH
export PYTHONPATH="${APP_DIR}:${PYTHONPATH:-}"

echo -e "\e[36m==========================================================\e[0m"
echo -e "\e[1;32m      Nous Research Hermes Agent (Client-API CLI)         \e[0m"
echo -e "\e[36m==========================================================\e[0m"
echo -e "Endpoint : \e[33m${HERMES_API_BASE_URL:-https://api.nousresearch.com/v1}\e[0m"
echo -e "Model    : \e[33m${HERMES_MODEL:-Hermes-3-Llama-3.1-8B}\e[0m"
echo -e "Ulimit -v: \e[33m409600 KB (Memory Safeguard)\e[0m"
echo -e "Config   : \e[33m${CONFIG_FILE}\e[0m"
echo -e "\e[36m----------------------------------------------------------\e[0m"

python3 -m hermes_agent
EOF

chmod 755 /usr/local/bin/run-hermes.sh

# Pasang symlink di ~/.local/bin/ jika path user menggunakan PATH lokal
sudo -u "$TARGET_USER" mkdir -p "${TARGET_HOME}/.local/bin"
sudo -u "$TARGET_USER" ln -sf /usr/local/bin/run-hermes.sh "${TARGET_HOME}/.local/bin/run-hermes.sh"

# 9. Shortcut Desktop Entry (Sistem dan Pengguna)
echo -e "\e[34m[04-HERMES]\e[0m Memasang file desktop entry..."
cp "${REPO_ROOT}/desktop-entries/hermes-agent.desktop" /usr/share/applications/hermes-agent.desktop
chmod 644 /usr/share/applications/hermes-agent.desktop

# Pasang di Desktop user
USER_DESKTOP="${TARGET_HOME}/Desktop"
sudo -u "$TARGET_USER" mkdir -p "$USER_DESKTOP"
cp "${REPO_ROOT}/desktop-entries/hermes-agent.desktop" "${USER_DESKTOP}/hermes-agent.desktop"
chmod 755 "${USER_DESKTOP}/hermes-agent.desktop"
chown "${TARGET_USER}:${TARGET_GROUP}" "${USER_DESKTOP}/hermes-agent.desktop"

# Pasang di ~/.local/share/applications
USER_APPS="${TARGET_HOME}/.local/share/applications"
sudo -u "$TARGET_USER" mkdir -p "$USER_APPS"
cp "${REPO_ROOT}/desktop-entries/hermes-agent.desktop" "${USER_APPS}/hermes-agent.desktop"
chmod 644 "${USER_APPS}/hermes-agent.desktop"
chown "${TARGET_USER}:${TARGET_GROUP}" "${USER_APPS}/hermes-agent.desktop"

# Pin ke taskbar IceWM toolbar pengguna
USER_ICEWM_TOOLBAR="${TARGET_HOME}/.icewm/toolbar"
sudo -u "$TARGET_USER" mkdir -p "${TARGET_HOME}/.icewm"
sudo -u "$TARGET_USER" touch "$USER_ICEWM_TOOLBAR"
if ! grep -q "hermes-agent" "$USER_ICEWM_TOOLBAR" && ! grep -q "Hermes Agent" "$USER_ICEWM_TOOLBAR"; then
    echo 'prog "Hermes Agent" utilities-terminal roxterm --title="Hermes Agent CLI" -e /usr/local/bin/run-hermes.sh' >> "$USER_ICEWM_TOOLBAR"
    chown "${TARGET_USER}:${TARGET_GROUP}" "$USER_ICEWM_TOOLBAR"
fi

# Pastikan kepemilikan total user-space valid
chown -R "${TARGET_USER}:${TARGET_GROUP}" \
    "${TARGET_HOME}/.venv" \
    "${TARGET_HOME}/.config" \
    "${TARGET_HOME}/.local" \
    "${TARGET_HOME}/.icewm" \
    "${TARGET_HOME}/Desktop"

# 10. Pembersihan APT Cache (Zero-Bloat)
apt-get autoremove --purge -y
apt-get clean
rm -rf /var/lib/apt/lists/*

echo -e "\e[32m[04-HERMES] Selesai dengan sukses tanpa permission trap.\e[0m"
