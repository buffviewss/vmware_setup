#!/usr/bin/env bash
set -euo pipefail

log(){ echo "[Canvas] $*"; }

# ── Không cho chạy bằng root (để monitors.xml vào HOME thật của bạn)
if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
  echo "[Canvas] Đừng chạy bằng sudo/root. Chạy với user thường."; exit 1
fi

# ── 1) DPI (text) : random mốc tự nhiên, không ưu tiên
TEXT_SCALE="${TEXT_SCALE:-auto}"
if [[ "$TEXT_SCALE" == "auto" ]]; then
  SCALES=(1.0 1.1 1.25 1.33 1.5 1.75 2.0)
  RANDOM_DPI="${SCALES[$RANDOM % ${#SCALES[@]}]}"
else
  RANDOM_DPI="$TEXT_SCALE"
fi
gsettings set org.gnome.desktop.interface text-scaling-factor "$RANDOM_DPI" || true
log "Text scaling factor: $RANDOM_DPI"

# ── 1.1) Wayland UI scale: random đều; có thể FORCE_WAYLAND_SCALE=1.25
UI_SCALES=(1.00 1.25 1.50 1.75 2.00)
WAYLAND_SCALE_MODE="${WAYLAND_SCALE_MODE:-uniform}"
if [[ -n "${FORCE_WAYLAND_SCALE:-}" ]]; then
  WAYLAND_SCALE=$(printf "%.2f" "$FORCE_WAYLAND_SCALE")
else
  # uniform = random đều; near = gần RANDOM_DPI (60% gần nhất, 20% hai lân cận)
  if [[ "$WAYLAND_SCALE_MODE" == "near" ]]; then
    nearest=0; best=9e9
    for i in "${!UI_SCALES[@]}"; do
      d=$(awk -v a="${UI_SCALES[$i]}" -v b="$RANDOM_DPI" 'BEGIN{d=a-b; if(d<0)d=-d; print d}')
      awk -v d="$d" -v b="$best" 'BEGIN{exit !(d<b)}' && { nearest=$i; best=$d; }
    done
    cands=($nearest); ((nearest>0)) && cands+=($((nearest-1))); ((nearest<${#UI_SCALES[@]}-1)) && cands+=($((nearest+1)))
    r=$((RANDOM%10)); if ((r<6)); then pick="${cands[0]}"; elif ((r<8)); then pick="${cands[1]:-${cands[0]}}"; else pick="${cands[2]:-${cands[0]}}"; fi
    WAYLAND_SCALE=$(printf "%.2f" "${UI_SCALES[$pick]}")
  else
    WAYLAND_SCALE=$(printf "%.2f" "${UI_SCALES[$RANDOM % ${#UI_SCALES[@]}]}")
  fi
fi
log "Wayland UI scale: $WAYLAND_SCALE (mode=$WAYLAND_SCALE_MODE)"

# ── Bật fractional scaling nếu scale ≠ 1 hoặc 2 (GNOME cần flag này cho 1.25/1.5/1.75)
if [[ "$WAYLAND_SCALE" != "1.00" && "$WAYLAND_SCALE" != "2.00" ]]; then
  gsettings set org.gnome.mutter experimental-features "['scale-monitor-framebuffer']" || true
  log "Enabled GNOME fractional scaling feature."
fi

# ── 2) Fonts: cài bộ font có thật + fonts.conf tự nhiên (không xóa gì)
INSTALL_FONTS="${INSTALL_FONTS:-1}"
if [[ "$INSTALL_FONTS" == "1" ]]; then
  sudo apt-get update -y || true
  sudo apt-get install -y \
    fontconfig \
    fonts-ubuntu fonts-dejavu-core fonts-dejavu-extra \
    fonts-liberation2 fonts-liberation \
    fonts-noto-core fonts-noto-extra fonts-noto-mono fonts-noto-color-emoji \
    fonts-cantarell fonts-freefont-ttf \
    fonts-hack-ttf fonts-firacode \
    fonts-roboto \
    >/dev/null 2>&1 || true
  log "Đã cài thêm font phổ biến."
fi

PREF_SANS_CANDIDATES=("Ubuntu" "Noto Sans" "DejaVu Sans" "Liberation Sans" "Cantarell" "Roboto")
command -v fc-list >/dev/null 2>&1 || sudo apt-get install -y fontconfig >/dev/null 2>&1 || true
PREF_HEAD="Ubuntu"
if command -v fc-list >/dev/null 2>&1; then
  INSTALLED_SANS=()
  for f in "${PREF_SANS_CANDIDATES[@]}"; do fc-list | grep -qi -- "$f" && INSTALLED_SANS+=("$f"); done
  ((${#INSTALLED_SANS[@]})) && PREF_HEAD=${INSTALLED_SANS[$RANDOM % ${#INSTALLED_SANS[@]}]}
fi
mkdir -p ~/.config/fontconfig
cat > ~/.config/fontconfig/fonts.conf <<EOF
<?xml version='1.0'?>
<!DOCTYPE fontconfig SYSTEM 'fonts.dtd'>
<fontconfig>
  <alias>
    <family>sans-serif</family>
    <prefer>
      <family>${PREF_HEAD}</family>
      <family>Ubuntu</family>
      <family>Noto Sans</family>
      <family>DejaVu Sans</family>
      <family>Liberation Sans</family>
      <family>Cantarell</family>
      <family>Roboto</family>
      <family>Noto Color Emoji</family>
    </prefer>
  </alias>
  <alias>
    <family>serif</family>
    <prefer>
      <family>Noto Serif</family>
      <family>DejaVu Serif</family>
      <family>Liberation Serif</family>
    </prefer>
  </alias>
  <alias>
    <family>monospace</family>
    <prefer>
      <family>Ubuntu Mono</family>
      <family>DejaVu Sans Mono</family>
      <family>Liberation Mono</family>
      <family>Fira Code</family>
    </prefer>
  </alias>
  <alias>
    <family>emoji</family>
    <prefer><family>Noto Color Emoji</family></prefer>
  </alias>
</fontconfig>
EOF
command -v fc-cache >/dev/null 2>&1 && fc-cache -f >/dev/null 2>&1 || true
log "fonts.conf cập nhật & cache làm mới."

# ── 3) Wayland: chọn resolution từ modes thật rồi ghi monitors.xml
if [[ "${XDG_SESSION_TYPE:-}" != "wayland" ]]; then
  log "Không phải Wayland → bỏ qua đổi resolution."
  exit 0
fi

DRM_CONNECTED=$(for s in /sys/class/drm/*/status; do
  [[ -f "$s" ]] || continue
  [[ "$(cat "$s")" == "connected" ]] && dirname "$s" | xargs -I{} basename {}
done | head -n1)
[[ -z "${DRM_CONNECTED:-}" ]] && { log "Không thấy connector connected"; exit 0; }

CONNECTOR="${DRM_CONNECTED#card*-}"
MODES_FILE="/sys/class/drm/${DRM_CONNECTED}/modes"
[[ ! -f "$MODES_FILE" ]] && { log "Không có $MODES_FILE"; exit 0; }

# Danh sách modes thật (loại trùng, tối thiểu 800x600)
mapfile -t REAL_MODES < <(awk -Fx '{ if ($1>=800 && $2>=600) print $0 }' "$MODES_FILE" | awk '!seen[$0]++')
log "Modes thật: ${REAL_MODES[*]}"

# Chọn ngẫu nhiên hoặc FORCE_RES
if [[ -n "${FORCE_RES:-}" ]] && printf "%s\n" "${REAL_MODES[@]}" | grep -qx -- "$FORCE_RES"; then
  PICK="$FORCE_RES"
else
  PICK="${REAL_MODES[$RANDOM % ${#REAL_MODES[@]}]}"
fi
WIDTH="${PICK%x*}"
HEIGHT="${PICK#*x}"

# Lấy refresh đúng
if ! command -v modetest >/dev/null 2>&1; then
  sudo apt-get update -y || true
  sudo apt-get install -y libdrm-tests || true
fi
RATE="$(modetest -c 2>/dev/null | awk -v c="$CONNECTOR" -v w="$WIDTH" -v h="$HEIGHT" '
  $0 ~ "^Connector .*\\(" c "\\):" {in=1; next}
  in && /^Connector / {in=0}
  in && $1 ~ /^[0-9]+x[0-9]+$/ { split($1,xy,"x"); if (xy[1]==w && xy[2]==h) { print $2; exit } }')"
[[ -z "$RATE" ]] && RATE="60.00"

log "Apply: ${WIDTH}x${HEIGHT}@${RATE}, scale=${WAYLAND_SCALE}, connector=${CONNECTOR}"

MON_DIR="$HOME/.config"; MON_FILE="$MON_DIR/monitors.xml"
mkdir -p "$MON_DIR"
[[ -f "$MON_FILE" ]] && cp -f "$MON_FILE" "$MON_FILE.bak" && log "Đã sao lưu: $MON_FILE.bak"
cat > "$MON_FILE" <<EOF
<monitors version="2">
  <configuration>
    <logicalmonitor>
      <x>0</x><y>0</y>
      <scale>${WAYLAND_SCALE}</scale>
      <transform>normal</transform>
      <monitor>
        <monitorspec>
          <connector>${CONNECTOR}</connector>
          <vendor>unknown</vendor><product>unknown</product><serial>unknown</serial>
        </monitorspec>
        <mode>
          <width>${WIDTH}</width>
          <height>${HEIGHT}</height>
          <rate>${RATE}</rate>
        </mode>
      </monitor>
      <primary>yes</primary>
    </logicalmonitor>
  </configuration>
</monitors>
EOF

log "Đã ghi $MON_FILE. Đăng xuất/đăng nhập để áp dụng."
log "Gợi ý: gnome-session-quit --logout --no-prompt"
