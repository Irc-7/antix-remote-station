#!/usr/bin/env bash
# ==============================================================================
# install.sh - Master Automation Script: antiX Remote Station (RAM 1 GB)
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
    log_error "Skrip ini wajib dijalankan dengan hak akses root!"
    echo -e "Silakan jalankan: ${COLOR_YELLOW}sudo ./install.sh${COLOR_RESET}\n"
    exit 1
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

log_title "antiX Remote Station - Post-Install Automation (RAM 1 GB)"
log_info "Memulai konfigurasi otomatis antiX Linux menjadi stasiun kerja remote..."
log_info "Direktori sumber: ${REPO_DIR}"

# 2. Deteksi Pengguna Target
TARGET_USER="${SUDO_USER:-}"
if [[ -z "$TARGET_USER" || "$TARGET_USER" == "root" ]]; then
    TARGET_USER="$(awk -F: '$3 >= 1000 && $3 < 60000 {print $1; exit}' /etc/passwd || echo "demo")"
fi
USER_HOME="$(eval echo "~${TARGET_USER}")"
log_info "Target non-root user: ${COLOR_YELLOW}${TARGET_USER}${COLOR_RESET} (Home: ${USER_HOME})"

# 3. Beri izin eksekusi pada seluruh modul skrip
chmod +x "${REPO_DIR}/scripts/"*.sh
chmod +x "${REPO_DIR}/hermes/run-hermes.sh"

# 4. Eksekusi Modular: Tahap 01 - Kernel & Resource Tuning
log_title "Tahap 1/4: Kernel Tuning, zRAM, EarlyOOM & Zero-Bloat Purge"
if "${REPO_DIR}/scripts/01-tuning.sh"; then
    log_success "Tahap 01 selesai."
else
    log_error "Tahap 01 gagal!"
    exit 1
fi

# 5. Eksekusi Modular: Tahap 02 - Desktop & UI Theme
log_title "Tahap 2/4: IceWM Desktop, FT10 Module & Papirus Theme"
if "${REPO_DIR}/scripts/02-desktop-theme.sh"; then
    log_success "Tahap 02 selesai."
else
    log_error "Tahap 02 gagal!"
    exit 1
fi

# 6. Eksekusi Modular: Tahap 03 - Remote Desktop Native (AnyDesk)
log_title "Tahap 3/4: Instalasi Native AnyDesk & Integrasi Taskbar"
if "${REPO_DIR}/scripts/03-remote-apps.sh"; then
    log_success "Tahap 03 selesai."
else
    log_error "Tahap 03 gagal!"
    exit 1
fi

# 7. Eksekusi Modular: Tahap 04 - Hermes Agent Client CLI
log_title "Tahap 4/4: Setup Virtualenv Hermes & Client-API CLI"
if "${REPO_DIR}/scripts/04-hermes-setup.sh"; then
    log_success "Tahap 04 selesai."
else
    log_error "Tahap 04 gagal!"
    exit 1
fi

# 8. Pembersihan Akhir Sistem (Zero-Bloat Total Cleanup)
log_title "Pembersihan Akhir & Optimasi Disk"
log_info "Menjalankan pembersihan cache APT dan file sementara..."
export DEBIAN_FRONTEND=noninteractive
apt-get autoremove --purge -y >/dev/null 2>&1 || true
apt-get clean >/dev/null 2>&1 || true
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* 2>/dev/null || true
log_success "Pembersihan total cache selesai."

# 9. Ringkasan & Panduan Pasca-Instalasi
log_title "INSTALASI SELESAI DENGAN SUKSES"
echo -e "${COLOR_GREEN}Sistem antiX Remote Station siap digunakan!${COLOR_RESET}"
echo -e ""
echo -e "Komponen Terpasang:"
echo -e "  [x] zRAM (zstd 100% RAM) & EarlyOOM (<5% RAM, <10% Swap safeguard)"
echo -e "  [x] sysctl low-ram tuning (swappiness=150, vfs_cache_pressure=50, overcommit_memory=2)"
echo -e "  [x] IceWM + FT10 taskbar styling + Papirus icon theme"
echo -e "  [x] AnyDesk native binary + desktop & taskbar pin"
echo -e "  [x] Hermes Agent CLI isolated client (~/.venv/hermes, ulimit 400MB)"
echo -e ""
echo -e "${COLOR_YELLOW}Langkah Selanjutnya:${COLOR_RESET}"
echo -e "1. Konfigurasi API Key Hermes:"
echo -e "   ${COLOR_BOLD}nano ${USER_HOME}/.config/hermes/.env${COLOR_RESET}"
echo -e "   (Isi HERMES_API_KEY dengan API key Anda)"
echo -e ""
echo -e "2. Jalankan Hermes Agent dari terminal atau shortcut desktop:"
echo -e "   ${COLOR_BOLD}run-hermes.sh${COLOR_RESET}"
echo -e ""
echo -e "3. Reboot sistem untuk menerapkan konfigurasi zRAM dan kernel secara penuh:"
echo -e "   ${COLOR_BOLD}sudo reboot${COLOR_RESET}"
echo -e ""
