#!/usr/bin/env bash
# ==============================================================================
# install.sh - Master Automation Script: antiX Remote Station (RAM 1 GB)
# Refactored: Robust Non-Root User Detection & Privilege Separation
# ==============================================================================
set -euo pipefail

# ANSI Color Codes
COLOR_RESET="\e[0m"
COLOR_BOLD="\e[1m"
COLOR_RED="\e[31m"
COLOR_GREEN="\e[32m"
COLOR_YELLOW="\e[33m"
COLOR_BLUE="\e[34m"
COLOR_CYAN="\e[36m"

log_title() {
    echo -e "\n${COLOR_CYAN}${COLOR_BOLD}======================================================================${COLOR_RESET}"
    echo -e "${COLOR_BOLD} $1 ${COLOR_RESET}"
    echo -e "${COLOR_CYAN}${COLOR_BOLD}======================================================================${COLOR_RESET}"
}

log_info() {
    echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $1"
}

log_success() {
    echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_RESET} $1"
}

log_warn() {
    echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $1"
}

log_error() {
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $1" >&2
}

# 1. Pengecekan Hak Akses Root
if [[ $EUID -ne 0 ]]; then
    log_error "Skrip master harus dijalankan menggunakan hak akses root via sudo!"
    echo -e "Silakan jalankan dari akun pengguna biasa: ${COLOR_YELLOW}sudo ./install.sh${COLOR_RESET}\n"
    exit 1
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

log_title "antiX Remote Station - Post-Install Automation (RAM 1 GB)"
log_info "Memulai konfigurasi otomatis antiX Linux..."
log_info "Direktori sumber: ${REPO_DIR}"

# 2. Deteksi Deterministik Non-Root Target User & Target Home
TARGET_USER="${SUDO_USER:-$USER}"

if [[ "$TARGET_USER" == "root" ]]; then
    # Jika login murni root tanpa sudo, cari akun reguler pertama (UID >= 1000)
    REGULAR_USER="$(awk -F: '$3 >= 1000 && $3 < 60000 {print $1; exit}' /etc/passwd || true)"
    if [[ -n "$REGULAR_USER" ]]; then
        log_warn "Dijalankan langsung oleh root tanpa SUDO_USER."
        log_warn "Mengarahkan konfigurasi user-space ke akun reguler: ${COLOR_YELLOW}${REGULAR_USER}${COLOR_RESET}"
        TARGET_USER="$REGULAR_USER"
    else
        log_error "Tidak ditemukan user reguler (UID >= 1000) pada sistem!"
        log_error "Buat user biasa terlebih dahulu atau jalankan 'sudo ./install.sh' dari akun biasa."
        exit 1
    fi
fi

TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
TARGET_GROUP="$(id -gn "$TARGET_USER" 2>/dev/null || echo "$TARGET_USER")"

if [[ -z "$TARGET_HOME" || ! -d "$TARGET_HOME" ]]; then
    log_error "Direktori home untuk user '${TARGET_USER}' (${TARGET_HOME}) tidak valid atau tidak ditemukan!"
    exit 1
fi

# Ekspor variabel agar diwariskan ke sub-skrip
export TARGET_USER
export TARGET_HOME
export TARGET_GROUP

log_info "Target Pengguna : ${COLOR_YELLOW}${TARGET_USER}${COLOR_RESET} (Grup: ${TARGET_GROUP})"
log_info "Direktori Home  : ${COLOR_YELLOW}${TARGET_HOME}${COLOR_RESET}"
log_info "Model Eksekusi  : Privilege Separation (Root -> Sistem, sudo -u ${TARGET_USER} -> User-space)"

# 3. Berikan izin eksekusi pada modul skrip
chmod +x "${REPO_DIR}/scripts/"*.sh
chmod +x "${REPO_DIR}/hermes/run-hermes.sh"

# 4. Tahap 01: Tuning Sistem & Kernel (Root Level)
log_title "Tahap 1/4: Kernel Tuning, zRAM, EarlyOOM & Zero-Bloat Purge"
if "${REPO_DIR}/scripts/01-tuning.sh"; then
    log_success "Tahap 01 selesai."
else
    log_error "Tahap 01 gagal!"
    exit 1
fi

# 5. Tahap 02: Desktop & Theme (Root + User-space)
log_title "Tahap 2/4: IceWM Desktop, FT10 Module & Papirus Theme"
if "${REPO_DIR}/scripts/02-desktop-theme.sh"; then
    log_success "Tahap 02 selesai."
else
    log_error "Tahap 02 gagal!"
    exit 1
fi

# 6. Tahap 03: Remote Apps (Root + User-space)
log_title "Tahap 3/4: Instalasi Native AnyDesk & Integrasi Taskbar"
if "${REPO_DIR}/scripts/03-remote-apps.sh"; then
    log_success "Tahap 03 selesai."
else
    log_error "Tahap 03 gagal!"
    exit 1
fi

# 7. Tahap 04: Hermes Client Setup (Root + User-space terisolasi)
log_title "Tahap 4/4: Setup Virtualenv Hermes & Client-API CLI"
if "${REPO_DIR}/scripts/04-hermes-setup.sh"; then
    log_success "Tahap 04 selesai."
else
    log_error "Tahap 04 gagal!"
    exit 1
fi

# 8. Verifikasi Akhir Kepemilikan User-Space
log_title "Verifikasi Integritas Hak Akses Pengguna"
log_info "Memastikan seluruh direktori di ${TARGET_HOME} bebas dari kepemilikan root..."
chown -R "${TARGET_USER}:${TARGET_GROUP}" \
    "${TARGET_HOME}/.venv" \
    "${TARGET_HOME}/.config" \
    "${TARGET_HOME}/.local" \
    "${TARGET_HOME}/.icewm" \
    "${TARGET_HOME}/Desktop" 2>/dev/null || true

# Pastikan permission file rahasia .env terkunci 600
if [[ -f "${TARGET_HOME}/.config/hermes/.env" ]]; then
    chmod 600 "${TARGET_HOME}/.config/hermes/.env"
    chown "${TARGET_USER}:${TARGET_GROUP}" "${TARGET_HOME}/.config/hermes/.env"
    log_success "File ${TARGET_HOME}/.config/hermes/.env terkunci aman (mode 600)."
fi

# 9. Pembersihan Akhir Sistem (Zero-Bloat Cleanup)
log_title "Pembersihan Akhir & Optimasi Disk"
log_info "Membersihkan cache paket dan file sementara..."
export DEBIAN_FRONTEND=noninteractive
apt-get autoremove --purge -y >/dev/null 2>&1 || true
apt-get clean >/dev/null 2>&1 || true
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* 2>/dev/null || true
log_success "Pembersihan total cache selesai."

# 10. Ringkasan Hasil
log_title "INSTALASI SELESAI TANPA PERMISSION TRAP"
echo -e "${COLOR_GREEN}Sistem antiX Remote Station siap digunakan!${COLOR_RESET}"
echo -e ""
echo -e "Status Akun Target:"
echo -e "  - User: ${COLOR_YELLOW}${TARGET_USER}${COLOR_RESET}"
echo -e "  - Home: ${COLOR_YELLOW}${TARGET_HOME}${COLOR_RESET}"
echo -e "  - Virtualenv: ${COLOR_YELLOW}${TARGET_HOME}/.venv/hermes${COLOR_RESET} (Milik: ${TARGET_USER})"
echo -e "  - Konfigurasi: ${COLOR_YELLOW}${TARGET_HOME}/.config/hermes/.env${COLOR_RESET} (Izin: 600)"
echo -e ""
echo -e "${COLOR_YELLOW}Langkah Selanjutnya:${COLOR_RESET}"
echo -e "1. Konfigurasikan API Key Hermes:"
echo -e "   ${COLOR_BOLD}nano ${TARGET_HOME}/.config/hermes/.env${COLOR_RESET}"
echo -e ""
echo -e "2. Jalankan Hermes Agent CLI (bisa dari desktop atau terminal):"
echo -e "   ${COLOR_BOLD}run-hermes.sh${COLOR_RESET}"
echo -e ""
echo -e "3. Reboot sistem untuk menerapkan konfigurasi kernel dan zRAM:"
echo -e "   ${COLOR_BOLD}sudo reboot${COLOR_RESET}"
echo -e ""
