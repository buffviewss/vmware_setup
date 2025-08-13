#!/usr/bin/env bash
set -euo pipefail

log(){ echo "[Canvas] $*"; }

# --- Không cho chạy bằng root/sudo (để monitors.xml nằm đúng HOME của bạn) ---
if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
  echo "[Canvas] Đừng chạy script bằng sudo/root. Hãy chạy với user thường."; exit 1
fi

########################################
# 1) DPI scaling (chữ): mốc phổ biến, random tự nhiên (không ưu tiên)
#    - Override: TEXT_SCALE=1.25 ./script.sh
########################################
TEXT_SCALE="${TEXT_SCALE:-auto}"
if [[ "$TEXT_SCALE" == "auto" ]]; then
  SCALES=(1.0 1.1 1.25 1.33 1.5 1.75 2.0)
  RANDOM_DPI="${SCALES[$RANDOM % ${#SCALES[@]}]}"
else
  RANDOM_DPI="$TEXT_SCALE"
fi
gsettings set org.gnome.desktop.interface text-scaling-factor "$RANDOM_DPI" || true
log "Text scaling factor: $RANDOM_DPI"

########################################
# 1.1) UI scale Wayland: random tự nhiên (không ưu tiên mốc nào)
#      - Override: FORCE_WAYLAND_SCALE=1.25
#      - Hoặc: WAYLAND_SCALE_MODE=near (chọn lân cận DPI chữ theo tỉ lệ 0.6/0.2/0.2)
########################################
UI_SCALES=(1.00 1.25 1.50 1.75 2.00)
WAYLAND_SCALE_MODE="${WAYLAND_SCALE_MODE:-uniform}"

pick_uniform_scale() {
  echo "${UI_SCALES[$RANDOM % ${#UI_SCALES[@]}]}"
}

pick_near_scale() {
  # Chọn mốc gần nhất với RANDOM_DPI nhưng có “nhiễu” người dùng: 60% gần nhất, 20% mỗi lân cận
  # Tìm index gần nhất
  nearest=0; bestdiff=9e9
  for i in "${!UI_SCALES[@]}"; do
    diff=$(awk -v a="${UI_SCALES[$i]}" -v b="$RANDOM_DPI" 'BEGIN{d=a-b; if(d<0)d=-d; print d}')
    awk -v d="$diff" -v bd="$bestdiff" 'BEGIN{exit !(d<bd)}' && { nearest="$i"; bestdiff="$diff"; }
  done
  # Lấy 3 ứng viên: nearest, neighbor-
  cands=("$nearest")
  (( nearest>0 )) && cands+=($((nearest-1)))
  (( nearest<${#UI_SCALES[@]}-1 )) && cands+=($((nearest+1)))

  # Trọng số 60/20/20 theo thứ tự cands
  r=$((RANDOM % 10))
  if (( r < 6 )); then idx="${cands[0]}"
  elif (( r < 8 )); then idx="${cands[1]:-${cands[0]}}"
  else idx="${cands[2]:-${cands[0]}}"
  fi
  echo "${UI_SCALES[$idx]}"
}

if [[ -n "${FORCE_WAYLAND_SCALE:-}" ]]; then
  WAYLAND_SCALE=$(printf "%.2f" "$FORCE_WAYLAND_SCALE")
elif [[ "$WAYLAND_SCALE_MODE" == "near" ]]; then
  WAYLAND_SCALE=$(pick_near_scale)
else
  WAYLAND_SCALE=$(pick_uniform_scale)
fi
log "Wayland UI scale: $WAYLAND_SCALE (mode=${WAYLAND_SCALE_MODE})"

########################################
# 2) Font: cài thêm gói có thật + fonts.conf “tự nhiên”
#    - KHÔNG xóa font mặc định; tắt cài bằng INSTALL_FONTS=0
########################################
INSTALL_FONTS="${INSTALL_FONTS:-1}"

safe_install_fonts() {
  if [[ "$INSTALL_FONTS" = "1" ]]; then
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
    log "Đã cài thêm bộ font phổ biến (không xóa gì)."
  else
    log "Bỏ qua bước cài thêm font (INSTALL_FONTS=0)."
  fi
}
safe_install_fonts

PREF_SANS_CANDIDATES=("Ubuntu" "Noto Sans" "DejaVu Sans" "Liberation Sans" "Cantarell" "Roboto")
if ! command -v fc-list >/dev/null 2>&1; then
  sudo apt-get install -y fontconfig >/dev/null 2>&1 || true
fi

PREF_HEAD="Ubuntu"
if command -v fc-list >/dev/null 2>&1; then
  INSTALLED_SANS=()
  for f in "${PREF_SANS_CANDIDATES[@]}"; do
    if fc-list | grep -qi -- "$f"; then INSTALLED_SANS+=("$f"); fi
  done
  if ((${#INSTALLED_SANS[@]})); then
    PREF_HEAD=${INSTALLED_SANS[$RANDOM % ${#INSTALLED_SANS[@]}]}
  fi
fi
log "Ưu tiên sans-serif: $PREF_HEAD"

mkdir -p ~/.config/fontconfig
cat > ~/.config/fontconfig/fonts.conf <<EOF
<?xml version='1.0'?>
<!DOCTYPE fontconfig SYSTEM 'fonts.dtd'>
<fontconfig>
  <!-- Không ép toàn hệ thống; chỉ ưu tiên để trông tự nhiên -->
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
    <prefer>
      <family>Noto Color Emoji</family>
    </prefer>
  </alias>
</fontconfig>
EOF

if command -v fc-cache >/dev/null 2>&1; then
  fc-cache -f >/dev/null 2>&1 || true
fi
log "fonts.conf đã cập nhật (tự nhiên hơn), cache font đã refresh."

########################################
# 3) Wayland-only: random/forced resolution (VMware/Virtual-1 OK)
#    - Áp dụng thật qua monitors.xml
#    - Lấy đúng refresh rate bằng modetest
########################################
if [[ "${XDG_SESSION_TYPE:-}" != "wayland" ]]; then
  log "Không phải Wayland → bỏ qua đổi resolution."
  exit 0
fi

RES_CHOICES=("1920x1200" "1920x1080" "1918x928" "1856x1392" "1792x1344" "1680x1050" "1600x1200" "1600x900" "1440x900" "1400x1050" "1366x768")

DRM_CONNECTED=$(for s in /sys/class/drm/*/status; do
  [[ -f "$s" ]] || continue
  [[ "$(cat "$s")" == "connected" ]] && dirname "$s" | xargs -I{} basename {}
done | head -n1)

if [[ -z "${DRM_CONNECTED:-}" ]]; then
  log "Không phát hiện connector đang kết nối trong /sys/class/drm."
  exit 0
fi

CONNECTOR="${DRM_CONNECTED#card*-}"
MODES_FILE="/sys/class/drm/${DRM_CONNECTED}/modes"
if [[ ! -f "$MODES_FILE" ]]; then
  log "Không thấy $MODES_FILE để kiểm tra mode khả dụng."
  exit 0
fi

mapfile -t REAL_MODES < <(sed -e 's/[[:space:]]*$//' "$MODES_FILE" | awk '!seen[$0]++')
log "Modes vật lý: ${REAL_MODES[*]}"

CANDIDATES=()
for r in "${RES_CHOICES[@]}"; do
  if printf "%s\n" "${REAL_MODES[@]}" | grep -qx -- "$r"; then CANDIDATES+=("$r"); fi
done

if ((${#CANDIDATES[@]}==0)); then
  log "Không có độ phân giải nào trong danh sách trùng với mode thật của $CONNECTOR. Giữ nguyên."
  exit 0
fi

if [[ -n "${FORCE_RES:-}" ]] && printf "%s\n" "${CANDIDATES[@]}" | grep -qx -- "$FORCE_RES"; then
  PICK="$FORCE_RES"
else
  PICK="${CANDIDATES[$RANDOM % ${#CANDIDATES[@]}]}"
fi
WIDTH="${PICK%x*}"
HEIGHT="${PICK#*x}"

if ! command -v modetest >/dev/null 2>&1; then
  sudo apt-get update -y || true
  sudo apt-get install -y libdrm-tests || true
fi

RATE="$(modetest -c 2>/dev/null \
  | awk -v c="$CONNECTOR" -v w="$WIDTH" -v h="$HEIGHT" '
      $0 ~ "^Connector .*\\(" c "\\):" {in=1; next}
      in && /^Connector / {in=0}
      in && $1 ~ /^[0-9]+x[0-9]+$/ {
        split($1,xy,"x");
        if (xy[1]==w && xy[2]==h) { print $2; exit }
      }
    ')"
[[ -z "$RATE" ]] && RATE="60.00"

log "Chọn ${WIDTH}x${HEIGHT}@${RATE}, scale=${WAYLAND_SCALE}, connector=${CONNECTOR}"

MON_DIR="$HOME/.config"
MON_FILE="$MON_DIR/monitors.xml"
mkdir -p "$MON_DIR"
[[ -f "$MON_FILE" ]] && cp -f "$MON_FILE" "$MON_FILE.bak" && log "Đã sao lưu: $MON_FILE.bak"

cat > "$MON_FILE" <<EOF
<monitors version="2">
  <configuration>
    <logicalmonitor>
      <x>0</x>
      <y>0</y>
      <scale>${WAYLAND_SCALE}</scale>
      <transform>normal</transform>
      <monitor>
        <monitorspec>
          <connector>${CONNECTOR}</connector>
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

log "Đã ghi $MON_FILE — Wayland sẽ nạp khi đăng nhập mới."
log "→ Chạy: gnome-session-quit --logout --no-prompt"