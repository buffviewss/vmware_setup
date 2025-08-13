#!/usr/bin/env bash
set -euo pipefail

log(){ echo "[Canvas] $*"; }

########################################
# 1) DPI scaling: mốc phổ biến, map sang Wayland scale tương ứng
#    - Có thể override bằng: TEXT_SCALE=1.25 ./script.sh
########################################
TEXT_SCALE="${TEXT_SCALE:-auto}"
if [[ "$TEXT_SCALE" == "auto" ]]; then
  # Ưu tiên các mốc người dùng hay dùng; 1.00/1.25 xuất hiện nhiều hơn
  SCALES=(1.00 1.00 1.10 1.15 1.20 1.25 1.25 1.33 1.50)
  RANDOM_DPI="${SCALES[$RANDOM % ${#SCALES[@]}]}"
else
  RANDOM_DPI="$TEXT_SCALE"
fi

# Áp dụng text scale cho GNOME
gsettings set org.gnome.desktop.interface text-scaling-factor "$RANDOM_DPI" || true
log "Text scaling factor: $RANDOM_DPI"

# Map DPI → Wayland UI scale gần nhất (1, 1.25, 1.5, 1.75, 2.0)
WAYLAND_SCALE=$(awk -v v="$RANDOM_DPI" 'BEGIN{
  a[1]=1.00; a[2]=1.25; a[3]=1.50; a[4]=1.75; a[5]=2.00;
  best=a[1]; d=(v-a[1]); if(d<0)d=-d;
  for(i=2;i<=5;i++){ dd=(v-a[i]); if(dd<0)dd=-dd; if(dd<d){d=dd; best=a[i]} }
  printf "%.2f", best;
}')
log "Wayland scale (for monitors.xml): $WAYLAND_SCALE"

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

# Chọn 1 sans-serif đang có thật để ưu tiên (giống người dùng chỉnh)
PREF_SANS_CANDIDATES=("Ubuntu" "Noto Sans" "DejaVu Sans" "Liberation Sans" "Cantarell" "Roboto")
if ! command -v fc-list >/dev/null 2>&1; then
  sudo apt-get install -y fontconfig >/dev/null 2>&1 || true
fi

PREF_HEAD="Ubuntu"
if command -v fc-list >/dev/null 2>&1; then
  INSTALLED_SANS=()
  for f in "${PREF_SANS_CANDIDATES[@]}"; do
    if fc-list | grep -qi -- "$f"; then
      INSTALLED_SANS+=("$f")
    fi
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
# 3) Wayland-only: random resolution theo danh sách (VMware/Virtual-1 OK)
#    - Áp dụng thật qua monitors.xml
#    - Lấy đúng refresh rate bằng modetest
########################################
if [[ "${XDG_SESSION_TYPE:-}" != "wayland" ]]; then
  log "Không phải Wayland → bỏ qua đổi resolution."
  exit 0
fi

# Danh sách như ảnh Settings ▸ Displays
RES_CHOICES=("1920x1200" "1920x1080" "1918x928" "1856x1392" "1792x1344" "1680x1050" "1600x1200" "1600x900" "1440x900" "1400x1050" "1366x768")

# 1) Xác định connector đang connected (VD: card0-Virtual-1)
DRM_CONNECTED=$(for s in /sys/class/drm/*/status; do
  [[ -f "$s" ]] || continue
  [[ "$(cat "$s")" == "connected" ]] && dirname "$s" | xargs -I{} basename {}
done | head -n1)

if [[ -z "${DRM_CONNECTED:-}" ]]; then
  log "Không phát hiện connector đang kết nối trong /sys/class/drm."
  exit 0
fi

CONNECTOR="${DRM_CONNECTED#card*-}"     # -> Virtual-1 / eDP-1 / HDMI-A-1 ...
MODES_FILE="/sys/class/drm/${DRM_CONNECTED}/modes"
if [[ ! -f "$MODES_FILE" ]]; then
  log "Không thấy $MODES_FILE để kiểm tra mode khả dụng."
  exit 0
fi

# 2) Lọc các mode thật sự hỗ trợ
mapfile -t REAL_MODES < <(sed -e 's/[[:space:]]*$//' "$MODES_FILE" | awk '!seen[$0]++')

CANDIDATES=()
for r in "${RES_CHOICES[@]}"; do
  if printf "%s\n" "${REAL_MODES[@]}" | grep -qx -- "$r"; then
    CANDIDATES+=("$r")
  fi
done

if ((${#CANDIDATES[@]}==0)); then
  log "Không có độ phân giải nào trong danh sách trùng với mode thật của $CONNECTOR."
  exit 0
fi

# 3) Chọn 1 mode hợp lệ + tìm refresh rate khớp bằng modetest
PICK="${CANDIDATES[$RANDOM % ${#CANDIDATES[@]}]}"
WIDTH="${PICK%x*}"
HEIGHT="${PICK#*x}"

# Đảm bảo modetest có sẵn
if ! command -v modetest >/dev/null 2>&1; then
  sudo apt-get update -y || true
  sudo apt-get install -y libdrm-tests || true
fi

# Lấy đúng refresh cho WIDTHxHEIGHT trên CONNECTOR (ví dụ 60.00 / 59.94 …)
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

log "Connector: $CONNECTOR"
log "Modes thật: ${REAL_MODES[*]}"
log "Chọn ${WIDTH}x${HEIGHT}@${RATE}, scale=${WAYLAND_SCALE}"

# 4) Ghi monitors.xml với scale khớp DPI (WAYLAND_SCALE)
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
