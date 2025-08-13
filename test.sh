#!/usr/bin/env bash
set -euo pipefail

log(){ echo "[Canvas] $*"; }

########################################
# 1) DPI scaling (giữ y nguyên)
########################################
MIN=1.01
MAX=1.45
RANDOM_DPI=$(awk -v min=$MIN -v max=$MAX 'BEGIN{srand(); printf "%.2f", min+rand()*(max-min)}')
gsettings set org.gnome.desktop.interface text-scaling-factor "$RANDOM_DPI" || true
log "DPI scaling: $RANDOM_DPI"

########################################
# 2) Font: cài thêm gói 'có thật' + fonts.conf tự nhiên
#    - KHÔNG xóa font mặc định
#    - Có thể tắt cài đặt bằng INSTALL_FONTS=0 ./script.sh
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

# Chọn 1 font sans-serif đang có thật để ưu tiên (trông 'tự nhiên')
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
  <!-- Không ép toàn hệ thống về 1 font; chỉ ưu tiên theo cách 'tự nhiên' -->
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

  <!-- Emoji fallback chuẩn -->
  <alias>
    <family>emoji</family>
    <prefer>
      <family>Noto Color Emoji</family>
    </prefer>
  </alias>
</fontconfig>
EOF

# Nạp lại cache (không fail script nếu thiếu)
if command -v fc-cache >/dev/null 2>&1; then
  fc-cache -f >/dev/null 2>&1 || true
fi
log "fonts.conf đã cập nhật (tự nhiên hơn), cache font đã refresh."

########################################
# 3) Wayland-only: random resolution theo danh sách trong ảnh
#    Áp dụng thật bằng monitors.xml (hiệu lực sau đăng xuất/đăng nhập)
########################################
if [[ "${XDG_SESSION_TYPE:-}" != "wayland" ]]; then
  log "Không phải Wayland → bỏ qua đổi resolution (theo yêu cầu Wayland-only)."
  exit 0
fi

# Danh sách giống ảnh Settings ▸ Displays
RES_CHOICES=("1920x1200" "1920x1080" "1918x928" "1856x1392" "1792x1344" "1680x1050" "1600x1200" "1600x900" "1440x900" "1400x1050" "1366x768")

# Lấy connector đang kết nối từ sysfs (máy thật)
DRM_CONNECTED=$(for s in /sys/class/drm/*/status; do
  [[ -f "$s" ]] || continue
  [[ "$(cat "$s")" == "connected" ]] && dirname "$s" | xargs basename
done | head -n1)

if [[ -z "${DRM_CONNECTED:-}" ]]; then
  log "Không phát hiện connector đang kết nối trong /sys/class/drm."
  exit 0
fi

CONNECTOR="${DRM_CONNECTED#card*-}"              # chuyển sang tên GNOME (eDP-1/HDMI-A-1…)
MODES_FILE="/sys/class/drm/${DRM_CONNECTED}/modes"
if [[ ! -f "$MODES_FILE" ]]; then
  log "Không thấy $MODES_FILE để kiểm tra mode khả dụng."
  exit 0
fi

# Các mode thật sự hỗ trợ (WIDTHxHEIGHT)
mapfile -t REAL_MODES < <(sed -e 's/[[:space:]]*$//' "$MODES_FILE" | awk '!seen[$0]++')

# Lọc: chỉ những mode vừa có trong ảnh, vừa thật trên máy
CANDIDATES=()
for r in "${RES_CHOICES[@]}"; do
  if printf "%s\n" "${REAL_MODES[@]}" | grep -qx -- "$r"; then
    CANDIDATES+=("$r")
  fi
done

if ((${#CANDIDATES[@]}==0)); then
  log "Không có độ phân giải nào trong danh sách trùng với mode thật của $CONNECTOR. Giữ nguyên."
  exit 0
fi

PICK="${CANDIDATES[$RANDOM % ${#CANDIDATES[@]}]}"
WIDTH="${PICK%x*}"
HEIGHT="${PICK#*x}"
RATE="60.00"  # GNOME sẽ chọn tần số gần nhất nếu khác

log "Connector: $CONNECTOR"
log "Modes thật: ${REAL_MODES[*]}"
log "Chọn và ghi monitors.xml → ${WIDTH}x${HEIGHT}@${RATE}"

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
      <scale>1</scale>
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

log "Đã ghi $MON_FILE (Wayland đọc file này khi đăng nhập)."
log "→ Hãy đăng xuất/đăng nhập để độ phân giải mới được áp dụng."
