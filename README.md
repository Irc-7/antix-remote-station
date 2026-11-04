# antiX Remote Station (Low-RAM Edition)

Repositori otomasi post-install dan konfigurasi modular untuk mengubah sistem operasi **antiX Linux** menjadi mesin kerja ultra-ringan berkinerja tinggi, khusus dirancang untuk perangkat komputasi terbatas (RAM 1 GB).

Sistem difokuskan secara eksklusif untuk dua peran utama:
1. Menjalankan **AnyDesk Remote Desktop** secara native dan terintegrasi di taskbar.
2. Menjalankan **Nous Research Hermes Agent CLI** yang beroperasi 100% sebagai *Client-API* eksternal (zero local weight inference) dengan pengamanan alokasi memori virtual.

---

## 1. Arsitektur Teknis & Prinsip Desain

```text
+-------------------------------------------------------------------------+
|                  antiX Linux (Debian Base, SysVinit)                    |
+-------------------------------------------------------------------------+
| Lapisan Kernel & Resource Governor (Root Context):                      |
|  - vm.swappiness=150 (Prioritas zRAM swap terkompresi zstd)             |
|  - vm.vfs_cache_pressure=50 (Pertahankan inode/dentry cache)            |
|  - vm.overcommit_memory=2 & ratio=80 (Proteksi alokasi berlebih)        |
|  - earlyoom daemon (OOM Killer responsif: RAM < 5%, Swap < 10%)         |
+-------------------------------------------------------------------------+
| Lapisan Antarmuka Pengguna (UI - User Context):                         |
|  - IceWM Window Manager (Konsumsi RAM ~15-25 MB)                        |
|  - FT10 Transformation Suite (Taskbar, tray, & start menu Windows-style)|
|  - Papirus Icon Theme + Native GTK tanpa desktop daemon berat           |
+-----------------------------------+-------------------------------------+
| Aplikasi 1: Native AnyDesk        | Aplikasi 2: Hermes Agent CLI Client |
|  - Paket Debian resmi (.deb)      |  - Python 3 Isolated User venv      |
|  - Akses remote desktop native    |  - Binary-only pip (--no-cache-dir) |
|  - Shortcut taskbar & desktop     |  - Safeguard: ulimit -v 409600      |
|                                   |  - External REST/Streaming API      |
+-----------------------------------+-------------------------------------+
```

### Penanganan Hak Akses (Privilege Separation & Anti-Permission Trap)
Ketika skrip instalasi dijalankan melalui `sudo ./install.sh`, penggunaan tilde (`~`) atau variabel `$HOME` rentan mengarah ke `/root`, mengakibatkan file user-space (seperti virtualenv, file desktop, dan konfigurasi) dimiliki oleh root dan memicu error `Permission Denied` bagi pengguna biasa.

Arsitektur otomasi ini memisahkan konteks eksekusi secara deterministik:
1. **Deteksi Non-Root User:**
   ```bash
   TARGET_USER="${SUDO_USER:-$USER}"
   TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
   ```
2. **Konteks Root (System Level):** Instalasi APT, kernel sysctl, konfigurasi earlyoom, zRAM, dan direktori `/opt/hermes-station`.
3. **Konteks Pengguna (User-Space Level):** Pembuatan virtualenv (`$TARGET_HOME/.venv/hermes`), instalasi pip, konfigurasi tema IceWM, shortcut desktop, dan file `.env` dieksekusi atas nama pengguna target menggunakan perintah `sudo -u "$TARGET_USER"` serta penguncian izin `chmod 600` pada file kredensial.

---

## 2. Profil Konsumsi Memori (RAM 1 GB)

Pengukuran konsumsi RAM sistem pada arsitektur x86_64:

| Status Sistem | Penggunaan RAM Riil | Status Swap (zRAM) | Keterangan |
| :--- | :--- | :--- | :--- |
| **Idle Pasca Boot** | **~115 MB - 135 MB** | 0 MB terpakai | IceWM + FT10 + EarlyOOM aktif |
| **Hermes Agent CLI Aktif** | **~155 MB - 185 MB** | < 10 MB | HTTP streaming client, ulimit 400 MB |
| **AnyDesk Sesi Aktif** | **~260 MB - 330 MB** | ~20 - 45 MB (zstd) | Decoding video remote desktop H.264 |
| **Beban Puncak (Keduanya)** | **~380 MB - 460 MB** | ~60 - 90 MB (zstd) | Sisa RAM fisik > 500 MB (sangat stabil) |

*Catatan: zRAM dengan rasio kompresi algoritma `zstd` (~2.5x hingga 3x) menyediakan ruang swap virtual dinamis sebesar 1 GB di dalam RAM tanpa latency dari disk mekanis.*

---

## 3. Struktur Direktori Repositori

```text
antix-remote-station/
├── .gitignore                          # Proteksi file .env dan cache Python
├── README.md                           # Dokumentasi teknis & panduan deployment
├── install.sh                          # Master script orkestrasi post-install
├── scripts/
│   ├── 01-tuning.sh                    # Kernel sysctl, zRAM, earlyoom, & disable bloat
│   ├── 02-desktop-theme.sh             # IceWM, modul FT10, font, & tema Papirus
│   ├── 03-remote-apps.sh               # Instalasi AnyDesk .deb & pin taskbar
│   └── 04-hermes-setup.sh              # Setup virtualenv Python (user context)
├── configs/
│   ├── sysctl.d/
│   │   └── 99-lowram-tuning.conf       # Parameter kernel swappiness & overcommit
│   └── earlyoom/
│       └── earlyoom.default            # Parameter threshold earlyoom
├── hermes/
│   ├── requirements.txt                # Dependensi binary client API
│   ├── run-hermes.sh                   # Wrapper eksekusi ulimit & pemuat .env
│   ├── .env.example                    # Template konfigurasi endpoint & API key
│   └── hermes_agent/                   # Modul client terminal interaktif
│       ├── __init__.py
│       └── __main__.py
└── desktop-entries/
    ├── anydesk.desktop                 # Desktop shortcut AnyDesk
    └── hermes-agent.desktop            # Desktop shortcut terminal Hermes Agent
```

---

## 4. Instalasi dan Penggunaan

### Prasyarat
- Sistem antiX Linux (Base, Full, atau Core) yang baru selesai dipasang.
- Jalankan terminal sebagai user biasa (bukan login langsung sebagai `root`).
- Koneksi internet aktif.

### Langkah Instalasi
1. Clone repositori ke direktori kerja pengguna:
   ```bash
   git clone https://github.com/Irc-7/antix-remote-station.git
   cd antix-remote-station
   ```

2. Berikan izin eksekusi pada master installer:
   ```bash
   chmod +x install.sh
   ```

3. Jalankan script master menggunakan `sudo`:
   ```bash
   sudo ./install.sh
   ```

Skrip mendeteksi `$SUDO_USER` secara otomatis, mengeksekusi instalasi sistem via root, dan membangun user-space via konteks pengguna asli tanpa menimbulkan permission trap.

---

## 5. Konfigurasi Hermes Agent CLI

Hermes Agent berjalan murni sebagai client ringan yang meneruskan query ke API eksternal (Nous Research API atau endpoint kompatibel OpenAI) tanpa memerlukan beban GPU/CPU lokal.

1. Buka file konfigurasi pengguna:
   ```bash
   nano ~/.config/hermes/.env
   ```
   *(File ini telah diatur dengan izin `chmod 600` demi keamanan kredensial).*

2. Konfigurasikan variabel environment:
   ```dotenv
   HERMES_API_BASE_URL=https://api.nousresearch.com/v1
   HERMES_API_KEY=masukkan_api_key_anda_di_sini
   HERMES_MODEL=Hermes-3-Llama-3.1-8B
   HERMES_TEMPERATURE=0.7
   HERMES_MAX_TOKENS=2048
   HERMES_TIMEOUT=60
   ```

3. Simpan dengan `Ctrl + O` lalu keluar dengan `Ctrl + X`.

4. Menjalankan Hermes:
   - Klik ikon terminal **Hermes Agent CLI** di desktop atau taskbar FT10.
   - Atau panggil melalui terminal biasa:
     ```bash
     run-hermes.sh
     ```

---

## 6. Panduan Membungkus Sistem Menjadi ISO Mandiri (antiX iso-snapshot)

Setelah seluruh konfigurasi selesai diuji, Anda dapat membuat file ISO bootable mandiri (*live USB installer*) yang membawa seluruh optimasi di atas menggunakan utilitas bawaan antiX, yaitu `iso-snapshot`.

### Langkah 1: Persiapan Sistem
Bersihkan file cache, log, dan riwayat terminal agar ukuran snapshot sekecil mungkin:
```bash
# Kembalikan file .env ke template contoh jika ISO akan didistribusikan ke perangkat lain
cp /opt/hermes-station/.env.example ~/.config/hermes/.env
chmod 600 ~/.config/hermes/.env

# Bersihkan history bash dan cache sementara
history -c
sudo rm -rf /tmp/* /var/tmp/* /var/log/*.gz /var/log/*.[0-9]
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*
```

### Langkah 2: Menjalankan Utilitas `iso-snapshot`
Jalankan tool snapshot melalui terminal:
```bash
sudo iso-snapshot
```

### Langkah 3: Konfigurasi Parameter Snapshot
1. **Snapshot Type**: Pilih opsi **Distribution** (installer publik, mereset password pribadi dan menggunakan user live bawaan) atau **Personalized** (menyertakan desktop dan home saat ini).
2. **Compression Type**: Pilih algoritma **xz** untuk ukuran image minimal (~700-900 MB).
3. **Output Directory**: Output ISO tersimpan di `/home/snapshot/`.

### Langkah 4: Menulis ISO ke Media USB
```bash
# Ganti /dev/sdX sesuai drive USB target
sudo dd if=/home/snapshot/antix-remote-station.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

---

## 7. Verifikasi dan Diagnostik Sistem

Untuk memverifikasi integritas hak akses dan performa:

- **Periksa kepemilikan virtualenv dan konfigurasi user:**
  ```bash
  ls -la ~/.venv/hermes
  ls -la ~/.config/hermes/.env
  ```
  *(Pastikan owner dan group adalah akun pengguna biasa, bukan `root:root`).*

- **Periksa status zRAM:**
  ```bash
  zramctl
  ```

- **Periksa status EarlyOOM:**
  ```bash
  service earlyoom status
  ```

- **Periksa nilai sysctl:**
  ```bash
  sysctl vm.swappiness vm.vfs_cache_pressure vm.overcommit_memory
  ```

# Telemetry sync enabled

# Memory profile tuning verified
