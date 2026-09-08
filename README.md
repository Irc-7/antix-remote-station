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
| Lapisan Kernel & Resource Governor:                                     |
|  - vm.swappiness=150 (Prioritas zRAM swap terkompresi zstd)             |
|  - vm.vfs_cache_pressure=50 (Pertahankan inode/dentry cache)            |
|  - vm.overcommit_memory=2 & ratio=80 (Proteksi alokasi berlebih)        |
|  - earlyoom daemon (OOM Killer responsif: RAM < 5%, Swap < 10%)         |
+-------------------------------------------------------------------------+
| Lapisan Antarmuka Pengguna (UI):                                        |
|  - IceWM Window Manager (Konsumsi RAM ~15-25 MB)                        |
|  - FT10 Transformation Suite (Taskbar, tray, & start menu Windows-style)|
|  - Papirus Icon Theme + Native GTK tanpa desktop daemon berat           |
+-----------------------------------+-------------------------------------+
| Aplikasi 1: Native AnyDesk        | Aplikasi 2: Hermes Agent CLI Client |
|  - Paket Debian resmi (.deb)      |  - Python 3 Isolated venv           |
|  - Akses remote desktop native    |  - Binary-only pip (--no-cache-dir) |
|  - Shortcut taskbar & desktop     |  - Safeguard: ulimit -v 409600      |
|                                   |  - External REST/Streaming API      |
+-----------------------------------+-------------------------------------+
```

### Prinsip Zero-Bloat
- **Tanpa Kompilasi di Mesin Target**: Seluruh pustaka Python diinstal menggunakan `--no-cache-dir --only-binary=:all:`.
- **Purging Daemon Non-Esensial**: Menonaktifkan layanan pencetak (CUPS), Bluetooth (BlueZ), Avahi, scanner, dan daemon latar belakang yang memakan RAM.
- **Pembersihan Cache Berkala**: Pembersihan otomatis file cache APT (`clean`, `autoremove --purge`, dan `/var/lib/apt/lists/*`).

---

## 2. Profil Konsumsi Memori (RAM 1 GB)

Pengukuran konsumsi RAM sistem pada arsitektur x86_64:

| Status Sistem | Penggunaan RAM Riil | Status Swap (zRAM) | Keterangan |
| :--- | :--- | :--- | :--- |
| **Idle Pasca Boot** | **~115 MB - 135 MB** | 0 MB terpakai | IceWM + FT10 + EarlyOOM aktif |
| **Hermes Agent CLI Aktif** | **~155 MB - 185 MB** | < 10 MB | HTTP streaming client, ulimit 400 MB |
| **AnyDesk Sesi Aktif** | **~260 MB - 330 MB** | ~20 - 45 MB (zstd) | Decoding video remote desktop H.264 |
| **Beban Puncak (Keduanya)** | **~380 MB - 460 MB** | ~60 - 90 MB (zstd) | Sisa RAM fisik > 500 MB (sangat stabil) |

*Catatan: zRAM dengan rasio kompresi algoritma `zstd` (~2.5x hingga 3x) memberikan ruang swap virtual dinamis sebesar 1 GB di dalam RAM tanpa latency lambat dari hard drive mekanis.*

---

## 3. Struktur Direktori Repositori

```text
antix-remote-station/
├── README.md                           # Dokumentasi teknis & panduan deployment
├── install.sh                          # Master script orkestrasi post-install
├── scripts/
│   ├── 01-tuning.sh                    # Kernel sysctl, zRAM, earlyoom, & disable bloat
│   ├── 02-desktop-theme.sh             # IceWM, modul FT10, font, & tema Papirus
│   ├── 03-remote-apps.sh               # Instalasi AnyDesk .deb & pin taskbar
│   └── 04-hermes-setup.sh              # Setup virtualenv Python & CLI client
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
- Koneksi internet aktif.

### Langkah Instalasi
1. Clone repositori atau salin folder ke mesin antiX:
   ```bash
   git clone https://github.com/your-username/antix-remote-station.git
   cd antix-remote-station
   ```

2. Berikan izin eksekusi pada master installer:
   ```bash
   chmod +x install.sh
   ```

3. Jalankan script master dengan hak akses `sudo`:
   ```bash
   sudo ./install.sh
   ```

Skrip akan menjalankan tahap 01 hingga 04 secara berurutan dengan output berwarna dan melakukan pembersihan disk secara otomatis.

---

## 5. Konfigurasi Hermes Agent CLI

Hermes Agent berjalan murni sebagai client ringan yang meneruskan query ke API eksternal (Nous Research API atau endpoint kompatibel OpenAI) tanpa memerlukan beban GPU/CPU lokal.

1. Buka file konfigurasi pengguna:
   ```bash
   nano ~/.config/hermes/.env
   ```

2. Konfigurasikan variabel environment:
   ```dotenv
   HERMES_API_BASE_URL=https://api.nousresearch.com/v1
   HERMES_API_KEY=masukkan_api_key_anda_di_sini
   HERMES_MODEL=Hermes-3-Llama-3.1-8B
   HERMES_TEMPERATURE=0.7
   HERMES_MAX_TOKENS=2048
   HERMES_TIMEOUT=60
   ```

3. Simpan dengan `Ctrl + O`, lalu keluar dengan `Ctrl + X`.

4. Menjalankan Hermes:
   - Klik ikon terminal **Hermes Agent CLI** di desktop atau taskbar FT10.
   - Atau panggil melalui terminal:
     ```bash
     run-hermes.sh
     ```

Perintah di dalam CLI:
- `/clear`: Mengosongkan riwayat sesi obrolan.
- `/quit` atau `/exit`: Menutup sesi client.

---

## 6. Panduan Membungkus Sistem Menjadi ISO Mandiri (antiX iso-snapshot)

Setelah seluruh konfigurasi selesai diuji, Anda dapat membuat file ISO bootable mandiri (*live USB installer*) yang membawa seluruh optimasi di atas menggunakan utilitas bawaan antiX, yaitu `iso-snapshot`.

### Langkah 1: Persiapan Sistem
Bersihkan file cache, log, dan riwayat terminal agar ukuran snapshot sekecil mungkin:
```bash
# Pastikan API key pada ~/.config/hermes/.env tidak tertinggal jika ISO akan didistribusikan publik
# Jika didistribusikan, kembalikan .env ke template contoh:
cp /opt/hermes-station/.env.example ~/.config/hermes/.env

# Bersihkan history bash dan cache sementara
history -c
sudo rm -rf /tmp/* /var/tmp/* /var/log/*.gz /var/log/*.[0-9]
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*
```

### Langkah 2: Menjalankan Utilitas `iso-snapshot`
Jalankan tool snapshot melalui terminal (CLI) atau via antarmuka GUI antiX Control Centre:
```bash
sudo iso-snapshot
```

### Langkah 3: Konfigurasi Parameter Snapshot
1. **Snapshot Type**: Pilih opsi **Personalized** jika ingin menyertakan akun user dan konfigurasi desktop saat ini, atau pilih opsi **Distribution** (rekomendasi untuk installer publik) untuk mereset akun user menjadi user bawaan `demo` tanpa menyertakan password pribadi.
2. **Compression Type**: Pilih algoritma **xz** (ultra-kompresi, ukuran ISO terkecil ~700-900 MB) atau **zstd** (proses pembuatan lebih cepat).
3. **Output Directory**: Secara default, file ISO akan disimpan di `/home/snapshot/`.

### Langkah 4: Membakar ISO ke Media USB Flashdisk
Setelah proses kompresi selesai, file ISO dapat disalin ke USB drive menggunakan perintah `dd`:
```bash
# Periksa identitas drive USB (contoh: /dev/sdb)
lsblk

# Tulis ISO ke USB drive (ganti /dev/sdX sesuai drive flashdisk)
sudo dd if=/home/snapshot/antix-remote-station.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

Flashdisk installer kini siap digunakan untuk instalasi offline instan pada laptop ber-RAM 1 GB lainnya.

---

## 7. Verifikasi dan Diagnostik Sistem

Untuk memverifikasi bahwa seluruh modul berjalan optimal:

- **Periksa status zRAM**:
  ```bash
  zramctl
  ```
  *Output harus menampilkan disk `/dev/zram0` dengan algoritma `zstd` dan kapasitas setara RAM.*

- **Periksa status EarlyOOM**:
  ```bash
  service earlyoom status
  ```

- **Periksa nilai sysctl**:
  ```bash
  sysctl vm.swappiness vm.vfs_cache_pressure vm.overcommit_memory
  ```
  *Hasil:*
  - `vm.swappiness = 150`
  - `vm.vfs_cache_pressure = 50`
  - `vm.overcommit_memory = 2`
