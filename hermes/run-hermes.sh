#!/usr/bin/env bash
# ==============================================================================
# Hermes Agent Launcher (Ultra-Low RAM Edition)
# Membatasi alokasi memori virtual dan mengeksekusi Client-API eksternal
# ==============================================================================
set -e

# 1. Batasi alokasi virtual memory ke 400 MB (409600 KB) untuk stabilitas RAM 1 GB
ulimit -v 409600

# 2. Inisialisasi path direktori kerja dan virtual environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${HOME}/.venv/hermes"
ENV_FILE="${SCRIPT_DIR}/.env"

# Fallback lokasi .env jika skrip ditaruh di direktori instalasi global
if [[ ! -f "$ENV_FILE" && -f "${HOME}/.config/hermes/.env" ]]; then
    ENV_FILE="${HOME}/.config/hermes/.env"
fi

# 3. Verifikasi ketersediaan Virtual Environment
if [[ ! -f "${VENV_DIR}/bin/activate" ]]; then
    echo -e "\e[31m[ERROR] Virtual environment tidak ditemukan di: ${VENV_DIR}\e[0m"
    echo -e "Silakan jalankan skrip instalasi terlebih dahulu: sudo /path/to/install.sh"
    echo ""
    read -rp "Tekan Enter untuk keluar..."
    exit 1
fi

# Aktifkan virtual environment Python
source "${VENV_DIR}/bin/activate"

# 4. Verifikasi dan muat file .env
if [[ ! -f "$ENV_FILE" ]]; then
    echo -e "\e[33m[PERINGATAN] File .env belum ditemukan di ${ENV_FILE}\e[0m"
    if [[ -f "${SCRIPT_DIR}/.env.example" ]]; then
        echo -e "Menyalin ${SCRIPT_DIR}/.env.example -> ${ENV_FILE}..."
        cp "${SCRIPT_DIR}/.env.example" "$ENV_FILE"
        echo -e "\e[32mTemplate .env berhasil disiapkan.\e[0m"
        echo -e "Harap isi HERMES_API_KEY Anda di: ${ENV_FILE}"
    else
        echo -e "\e[31mTemplate .env.example tidak ditemukan. Silakan buat ${ENV_FILE} secara manual.\e[0m"
    fi
    echo ""
    read -rp "Tekan 'e' untuk mengedit sekarang dengan nano, atau Enter untuk keluar: " CHOICE
    if [[ "$CHOICE" == "e" || "$CHOICE" == "E" ]]; then
        nano "$ENV_FILE"
    else
        exit 1
    fi
fi

# Muat konfigurasi dari .env
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

# Validasi nilai API Key
if [[ -z "${HERMES_API_KEY:-}" || "${HERMES_API_KEY}" == "your_api_key_here" ]]; then
    echo -e "\e[31m[ERROR] HERMES_API_KEY belum diisi pada file ${ENV_FILE}!\e[0m"
    echo -e "Buka file tersebut dan masukkan API Key valid Anda."
    echo ""
    read -rp "Tekan Enter untuk menutup..."
    exit 1
fi

# 5. Header informasi sesi
echo -e "\e[36m==========================================================\e[0m"
echo -e "\e[1;32m      Nous Research Hermes Agent (Client-API CLI)         \e[0m"
echo -e "\e[36m==========================================================\e[0m"
echo -e "Endpoint : \e[33m${HERMES_API_BASE_URL:-https://api.nousresearch.com/v1}\e[0m"
echo -e "Model    : \e[33m${HERMES_MODEL:-Hermes-3-Llama-3.1-8B}\e[0m"
echo -e "Ulimit -v: \e[33m409600 KB (RAM Safeguard)\e[0m"
echo -e "\e[36m----------------------------------------------------------\e[0m"
echo -e "Ketik \e[1;31m/exit\e[0m atau \e[1;31m/quit\e[0m untuk keluar, \e[1;33m/clear\e[0m untuk reset percakapan."
echo ""

# Pastikan modul client lokal dapat diakses jika modul sistem belum terpasang
export PYTHONPATH="${SCRIPT_DIR}:${PYTHONPATH:-}"

# Eksekusi Hermes Agent Client CLI
python3 -m hermes_agent

EXIT_CODE=$?
if [[ $EXIT_CODE -ne 0 ]]; then
    echo ""
    echo -e "\e[31mProses Hermes Agent keluar dengan kode status: ${EXIT_CODE}\e[0m"
    read -rp "Tekan Enter untuk menutup jendela..."
fi
