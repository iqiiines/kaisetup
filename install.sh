#!/usr/bin/env bash
# =============================================================================
# KAI LoketBox - Setup Printer Thermal (one-click)
# Mengotomasi panduan "Setting Printer Loket KAI" + "Usecase Multiple Print Ticket"
#
# Jalankan sebagai USER KIOSK (bukan root). Script memanggil sudo sendiri.
#   ./install.sh                       # auto-detect printer (jika hanya ada 1)
#   ./install.sh --printer S31         # tentukan nama printer
#   ./install.sh --printer S31 --paper 72x200 --scale 80
#   ./install.sh --dry-run             # hanya tampilkan apa yang akan dilakukan
# =============================================================================
set -euo pipefail

# ---------- Default (bisa di-override lewat argumen) ----------
PRINTER=""
PAPER="72x200"            # lebar x tinggi dalam mm
SCALE="80"                # persen
SERVICE="kai-chrome-kiosk.service"
CHROME_PROFILE_DIR="${CHROME_PROFILE_DIR:-$HOME/.config/google-chrome/Default}"
DO_CHROME=1
DO_USB_UNIDIR=1
DRY_RUN=0

# ---------- Helper ----------
log()  { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '[dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
  cat <<'EOF'

Opsi:
  --printer NAMA     Nama printer di CUPS (lihat: lpstat -p)
  --paper WxH        Ukuran kertas mm, default 72x200
  --scale N          Skala Chrome dalam persen, default 80
  --service NAMA     Nama service kiosk, default kai-chrome-kiosk.service
  --chrome-profile DIR  Folder profil Chrome yang dipakai kiosk
  --no-chrome        Lewati pengaturan profil Chrome
  --no-usb-unidir    Lewati usb-unidir-default (multiple print)
  --dry-run          Simulasi, tidak mengubah apa pun
  -h, --help         Bantuan
EOF
}

# ---------- Parse argumen ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --printer)        PRINTER="${2:?nilai --printer kosong}"; shift 2 ;;
    --paper)          PAPER="${2:?nilai --paper kosong}"; shift 2 ;;
    --scale)          SCALE="${2:?nilai --scale kosong}"; shift 2 ;;
    --service)        SERVICE="${2:?nilai --service kosong}"; shift 2 ;;
    --chrome-profile) CHROME_PROFILE_DIR="${2:?nilai kosong}"; shift 2 ;;
    --no-chrome)      DO_CHROME=0; shift ;;
    --no-usb-unidir)  DO_USB_UNIDIR=0; shift ;;
    --dry-run)        DRY_RUN=1; shift ;;
    -h|--help)        usage; exit 0 ;;
    *) die "Argumen tidak dikenal: $1 (gunakan --help)" ;;
  esac
done

[[ "$PAPER" =~ ^[0-9]+x[0-9]+$ ]] || die "Format --paper harus WxH dalam mm, contoh 72x200"
[[ "$SCALE" =~ ^[0-9]+$ ]]        || die "--scale harus angka, contoh 80"
PAPER_W="${PAPER%x*}"
PAPER_H="${PAPER#*x}"

# ---------- Pre-flight ----------
[[ $EUID -ne 0 ]] || die "Jangan jalankan sebagai root. Jalankan sebagai user kiosk (script akan memanggil sudo sendiri)."
command -v lpstat  >/dev/null || die "CUPS belum terpasang (lpstat tidak ditemukan)."
command -v lpadmin >/dev/null || die "lpadmin tidak ditemukan."
command -v systemctl >/dev/null || die "systemctl tidak ditemukan."

log "Meminta akses sudo (sekali di awal)..."
[[ $DRY_RUN -eq 1 ]] || sudo -v

# ---------- Deteksi nama printer ----------
if [[ -z "$PRINTER" ]]; then
  mapfile -t PRINTERS < <(lpstat -p 2>/dev/null | awk '/^printer /{print $2}')
  case "${#PRINTERS[@]}" in
    0) die "Tidak ada printer terdeteksi. Cek koneksi USB dan jalankan: lpstat -p" ;;
    1) PRINTER="${PRINTERS[0]}"; log "Printer terdeteksi otomatis: $PRINTER" ;;
    *) die "Lebih dari satu printer (${PRINTERS[*]}). Tentukan dengan --printer NAMA" ;;
  esac
fi
lpstat -p "$PRINTER" >/dev/null 2>&1 || die "Printer '$PRINTER' tidak ditemukan di CUPS."

# ---------- Langkah 1: hentikan service kiosk (dan pastikan selalu dijalankan lagi) ----------
KIOSK_WAS_STOPPED=0
restart_kiosk() {
  if [[ $KIOSK_WAS_STOPPED -eq 1 ]]; then
    log "Menjalankan kembali service kiosk..."
    run systemctl --user restart "$SERVICE" || warn "Gagal restart $SERVICE, jalankan manual."
  fi
}
trap restart_kiosk EXIT

log "Menghentikan sementara service kiosk ($SERVICE)..."
if run systemctl --user stop "$SERVICE"; then
  KIOSK_WAS_STOPPED=1
else
  warn "Service $SERVICE tidak bisa dihentikan (mungkin belum ada). Lanjut."
fi

# ---------- Langkah 2-6: setting Chrome (profil pengguna) ----------
configure_chrome() {
  local pref="$CHROME_PROFILE_DIR/Preferences"
  if [[ ! -f "$pref" ]]; then
    warn "File Preferences tidak ditemukan di $pref"
    warn "Buka Chrome sekali, atau set --chrome-profile. Bagian Chrome dilewati."
    return 0
  fi

  if ! command -v jq >/dev/null; then
    log "jq belum ada, memasang via apt..."
    run sudo apt-get install -y jq || { warn "Gagal memasang jq. Bagian Chrome dilewati."; return 0; }
  fi

  if pgrep -u "$USER" -x chrome >/dev/null 2>&1 || pgrep -u "$USER" -x google-chrome >/dev/null 2>&1; then
    warn "Chrome masih berjalan; perubahan Preferences bisa tertimpa. Tutup Chrome lalu jalankan ulang."
    return 0
  fi

  local backup="$pref.bak.$(date +%Y%m%d-%H%M%S)"
  log "Backup Preferences -> $backup"
  run cp -p "$pref" "$backup"

  log "Mengatur Chrome: Landscape, margin None, scale ${SCALE}%, kertas ${PAPER_W}x${PAPER_H}mm, destination $PRINTER"
  local tmp
  tmp="$(mktemp)"
  # marginsType: 1 = None | scalingType: 3 = Custom
  jq --arg dest "$PRINTER" \
     --arg scale "$SCALE" \
     --arg label "${PAPER_W}mmx${PAPER_H}mm" \
     --argjson w "$((PAPER_W * 1000))" \
     --argjson h "$((PAPER_H * 1000))" '
     .printing.print_preview_sticky_settings.appState =
       ( ((.printing.print_preview_sticky_settings.appState // "{}") | fromjson)
         + {
             version: 2,
             isLandscapeEnabled: true,
             marginsType: 1,
             scaling: $scale,
             scalingType: 3,
             isHeaderFooterEnabled: false,
             selectedDestinationId: $dest,
             mediaSize: {
               name: "CUSTOM",
               width_microns: $w,
               height_microns: $h,
               custom_display_name: $label,
               is_default: false
             }
           }
         | tojson )
     ' "$pref" > "$tmp"

  if jq empty "$tmp" 2>/dev/null; then
    if [[ $DRY_RUN -eq 1 ]]; then
      printf '[dry-run] tulis Preferences baru ke %s\n' "$pref"
      rm -f "$tmp"
    else
      cat "$tmp" > "$pref"
      rm -f "$tmp"
      ok "Preferences Chrome diperbarui."
    fi
  else
    rm -f "$tmp"
    die "Hasil edit Preferences tidak valid; file asli tidak diubah (backup: $backup)."
  fi
}

if [[ $DO_CHROME -eq 1 ]]; then
  configure_chrome
else
  log "Melewati pengaturan Chrome (--no-chrome)."
fi

# ---------- Langkah 8-14: CUPS (orientasi + media size) ----------
log "Mengatur CUPS untuk printer $PRINTER..."

# Pilih nama media: pakai pilihan driver jika ada (mis. 72mmx200mm), jika tidak pakai Custom.
MEDIA="Custom.${PAPER_W}x${PAPER_H}mm"
if lpoptions -p "$PRINTER" -l 2>/dev/null | grep -Eq "(^|[ /])${PAPER_W}mmx${PAPER_H}mm([ /]|\$)"; then
  MEDIA="${PAPER_W}mmx${PAPER_H}mm"
fi
log "Media size CUPS: $MEDIA"

LPADMIN_OPTS=(-o "orientation-requested-default=4" -o "media=$MEDIA")
[[ $DO_USB_UNIDIR -eq 1 ]] && LPADMIN_OPTS+=(-o "usb-unidir-default=true")

run sudo lpadmin -p "$PRINTER" "${LPADMIN_OPTS[@]}"
ok "Opsi CUPS diterapkan."

# ---------- Multiple print: restart CUPS ----------
if [[ $DO_USB_UNIDIR -eq 1 ]]; then
  log "Restart layanan CUPS (untuk usb-unidir)..."
  run sudo systemctl restart cups
fi

# ---------- Verifikasi ----------
if [[ $DRY_RUN -eq 0 ]]; then
  log "Verifikasi opsi printer:"
  lpoptions -p "$PRINTER" | tr ' ' '\n' \
    | grep -E '^(orientation-requested|media|usb-unidir)' | sed 's/^/   /' || true
fi

# Service kiosk dijalankan kembali oleh trap EXIT
ok "Selesai. Printer '$PRINTER' sudah dikonfigurasi."
