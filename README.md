# kaisetup - Setup Printer Thermal KAI LoketBox

Script otomatis untuk mengatur printer thermal pada kiosk KAI LoketBox (Ubuntu).
Menggantikan langkah manual di dokumen *Setting Printer Loket KAI* dan *Usecase Multiple Print Ticket KAI*.

## Yang dilakukan script

1. Menghentikan sementara service `kai-chrome-kiosk.service` (otomatis dijalankan lagi di akhir, juga saat script gagal).
2. Mengatur print settings Chrome pada profil user: Landscape, margin None, scale 80%, kertas 72x200mm, destination sesuai printer. Preferences lama di-backup terlebih dulu.
3. Mengatur CUPS: orientasi Landscape, media size, dan `usb-unidir-default=true` (mengurangi jeda antar cetakan).
4. Restart CUPS dan menampilkan hasil verifikasi.

## Prasyarat

- Ubuntu dengan CUPS terpasang dan printer sudah terdeteksi (`lpstat -p`).
- Dijalankan sebagai **user kiosk** (bukan root) yang punya hak `sudo`.
- `jq` (dipasang otomatis via apt jika ada internet).
- `curl` atau `wget` untuk mengunduh script.

## Cara pakai

### Opsi A: download, cek, lalu jalankan (disarankan)

```bash
curl -fsSLO https://raw.githubusercontent.com/iqiiines/kaisetup/main/install.sh
bash install.sh --dry-run             # simulasi, tidak mengubah apa pun
bash install.sh --printer S31         # eksekusi
```

### Opsi B: satu perintah

```bash
curl -fsSL https://raw.githubusercontent.com/iqiiines/kaisetup/main/install.sh | bash -s -- --printer S31
```

Tanpa `curl`:

```bash
wget -qO- https://raw.githubusercontent.com/iqiiines/kaisetup/main/install.sh | bash -s -- --printer S31
```

### Opsi C: git clone

```bash
git clone https://github.com/iqiiines/kaisetup.git
cd kaisetup
bash install.sh --printer S31
```

> Untuk rollout ke banyak device, gunakan versi tetap (tag) agar semua device menjalankan script yang sama,
> misalnya `.../kaisetup/v1.0.0/install.sh`, bukan `main`.

## Opsi

| Opsi | Keterangan | Default |
|---|---|---|
| `--printer NAMA` | Nama printer di CUPS (lihat `lpstat -p`). Jika hanya ada satu printer, terdeteksi otomatis | auto |
| `--paper WxH` | Ukuran kertas dalam mm | `72x200` |
| `--scale N` | Skala Chrome (persen) | `80` |
| `--service NAMA` | Nama service kiosk | `kai-chrome-kiosk.service` |
| `--chrome-profile DIR` | Folder profil Chrome yang dipakai kiosk | `~/.config/google-chrome/Default` |
| `--no-chrome` | Lewati pengaturan Chrome | - |
| `--no-usb-unidir` | Lewati `usb-unidir-default` | - |
| `--dry-run` | Simulasi saja | - |
| `-h`, `--help` | Bantuan | - |

## Verifikasi setelah selesai

```bash
lpoptions -p S31 | tr ' ' '\n' | grep -E 'orientation|media|usb-unidir'
```

Lalu buka Chrome, tekan **Ctrl + P**, dan pastikan Landscape, 72x200mm, margin None, dan scale 80 sudah terisi.
Terakhir, lakukan test cetak tiket dari LoketBox.

## Troubleshooting

| Masalah | Penyebab / solusi |
|---|---|
| `bad interpreter: /bin/bash^M` | File memakai line ending Windows (CRLF). Pastikan `.gitattributes` ada di repo, atau jalankan `sed -i 's/\r$//' install.sh` |
| `Tidak ada printer terdeteksi` | Cek kabel USB dan `lpstat -p`. Pastikan printer sudah ditambahkan di CUPS |
| `Lebih dari satu printer` | Tentukan dengan `--printer NAMA` |
| Bagian Chrome dilewati ("Preferences tidak ditemukan") | Kiosk mungkin memakai `--user-data-dir` khusus. Gunakan `--chrome-profile <folder>` |
| Setting Chrome tidak berubah | Chrome masih berjalan saat script dieksekusi, atau struktur Preferences berbeda antar versi Chrome. Tutup Chrome lalu jalankan ulang |
| Service kiosk tidak naik | `systemctl --user status kai-chrome-kiosk.service` dan `journalctl --user -u kai-chrome-kiosk.service` |

## Rollback

- Chrome: backup tersimpan di `<profil>/Preferences.bak.<timestamp>`. Matikan Chrome, lalu salin kembali ke `Preferences`.
- CUPS: ubah kembali dengan `sudo lpadmin -p NAMA -o orientation-requested-default=3` (Portrait).
  Opsi lain dapat diatur ulang lewat `http://localhost:631`.

## Catatan

- Script bersifat idempotent: aman dijalankan berulang kali.
- Jangan menyimpan password, token, atau data sensitif lain di repo ini.
