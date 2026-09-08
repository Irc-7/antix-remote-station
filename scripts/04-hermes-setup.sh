#!/usr/bin/env bash
# ==============================================================================
# scripts/04-hermes-setup.sh
# Isolasi Virtualenv Python, Zero-Compilation Pip, dan Integrasi Hermes Agent CLI
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Verifikasi hak akses root
if [[ $EUID -ne 0 ]]; then
    echo -e "\e[31m[ERROR] Skrip 04-hermes-setup.sh harus dijalankan sebagai root (sudo)!\e[0m" >&2
    exit 1
fi

TARGET_USER="${SUDO_USER:-}"
if [[ -z "$TARGET_USER" || "$TARGET_USER" == "root" ]]; then
    TARGET_USER="$(awk -F: '$3 >= 1000 && $3 < 60000 {print $1; exit}' /etc/passwd || echo "demo")"
fi
USER_HOME="$(eval echo "~${TARGET_USER}")"
TARGET_GROUP="$(id -gn "$TARGET_USER" 2>/dev/null || echo "$TARGET_USER")"

echo -e "\e[34m[04-HERMES]\e[0m Menyiapkan environment Hermes Agent CLI untuk: \e[33m${TARGET_USER}\e[0m..."

export DEBIAN_FRONTEND=noninteractive
apt-get update -y

# 1. Pasang runtime Python3, venv, pip, dan terminal roxterm
echo -e "\e[34m[04-HERMES]\e[0m Memasang paket Python3, venv, pip, dan roxterm..."
apt-get install --no-install-recommends -y \
    python3 \
    python3-venv \
    python3-pip \
    roxterm \
    nano

# 2. Siapkan direktori kerja aplikasi di sistem (/opt/hermes-station)
APP_DIR="/opt/hermes-station"
mkdir -p "$APP_DIR"
cp -r "${REPO_ROOT}/hermes/"* "$APP_DIR/"
chmod +x "${APP_DIR}/run-hermes.sh"

# Siapkan direktori konfigurasi user
USER_CONFIG_DIR="${USER_HOME}/.config/hermes"
mkdir -p "$USER_CONFIG_DIR"
if [[ ! -f "${USER_CONFIG_DIR}/.env" ]]; then
    cp "${APP_DIR}/.env.example" "${USER_CONFIG_DIR}/.env"
fi

# 3. Buat Virtual Environment terisolasi di ~/.venv/hermes
VENV_DIR="${USER_HOME}/.venv/hermes"
echo -e "\e[34m[04-HERMES]\e[0m Membuat virtual environment di: \e[33m${VENV_DIR}\e[0m..."
su - "$TARGET_USER" -c "mkdir -p '${USER_HOME}/.venv'"
if [[ ! -f "${VENV_DIR}/bin/activate" ]]; then
    su - "$TARGET_USER" -c "python3 -m venv '${VENV_DIR}'"
fi

# 4. Instalasi dependensi dengan aturan mutlak: ZERO COMPILATION & NO CACHE
echo -e "\e[34m[04-HERMES]\e[0m Memasang pustaka Python (--only-binary=:all: --no-cache-dir)..."
REQUIREMENTS_FILE="${APP_DIR}/requirements.txt"
su - "$TARGET_USER" -c "'${VENV_DIR}/bin/pip' install --no-cache-dir --upgrade pip"
su - "$TARGET_USER" -c "'${VENV_DIR}/bin/pip' install --no-cache-dir --only-binary=:all: -r '${REQUIREMENTS_FILE}'"

# 5. Pasang wrapper sistem global di /usr/local/bin/run-hermes.sh
cat << 'EOF' > /usr/local/bin/run-hermes.sh
#!/usr/bin/env bash
set -e
# Menjalankan runner Hermes Station dengan isolasi ulimit
export APP_DIR="/opt/hermes-station"
cd "$APP_DIR"
exec bash "${APP_DIR}/run-hermes.sh" "$@"
EOF
chmod +x /usr/local/bin/run-hermes.sh

# 6. Salin desktop entry dan integrasikan ke taskbar / desktop
echo -e "\e[34m[04-HERMES]\e[0m Memasang desktop entry dan pin shortcut..."
cp "${REPO_ROOT}/desktop-entries/hermes-agent.desktop" /usr/share/applications/hermes-agent.desktop
chmod 644 /usr/share/applications/hermes-agent.desktop

USER_DESKTOP="${USER_HOME}/Desktop"
mkdir -p "$USER_DESKTOP"
cp "${REPO_ROOT}/desktop-entries/hermes-agent.desktop" "${USER_DESKTOP}/hermes-agent.desktop"
chmod +x "${USER_DESKTOP}/hermes-agent.desktop"

# Pin ke taskbar IceWM
USER_ICEWM_TOOLBAR="${USER_HOME}/.icewm/toolbar"
mkdir -p "${USER_HOME}/.icewm"
touch "$USER_ICEWM_TOOLBAR"
if ! grep -q "hermes-agent" "$USER_ICEWM_TOOLBAR" && ! grep -q "Hermes Agent" "$USER_ICEWM_TOOLBAR"; then
    echo 'prog "Hermes Agent" utilities-terminal roxterm --title="Hermes Agent CLI" -e /usr/local/bin/run-hermes.sh' >> "$USER_ICEWM_TOOLBAR"
fi

# Set kepemilikan file user
chown -R "${TARGET_USER}:${TARGET_GROUP}" \
    "$USER_CONFIG_DIR" \
    "$USER_DESKTOP" \
    "${USER_HOME}/.venv" \
    "${USER_HOME}/.icewm"
chown -R "${TARGET_USER}:${TARGET_GROUP}" "$APP_DIR"

# 7. Pembersihan APT Cache
apt-get autoremove --purge -y
apt-get clean
rm -rf /var/lib/apt/lists/*

echo -e "\e[32m[04-HERMES] Selesai dengan sukses.\e[0m"
