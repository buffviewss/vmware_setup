
#!/bin/bash
set -e

echo "[FP-MAX] Fingerprint Randomizer 10/10 – Ubuntu/Lubuntu 24.04"

# =============================
# # 1. WebGL – GPU + Mesa + Vulkan
# # =============================
# VMX_FILE="$HOME/.vmware/your_vm.vmx"
# GPU_VENDOR=("0x10de" "0x8086" "0x1002" "0x1414" "0x1043")
# GPU_DEVICE=("0x1eb8" "0x1d01" "0x6810" "0x0000" "0x6780")
# GPU_VRAM=("134217728" "67108864" "268435456" "536870912")
# RANDOM_VENDOR=${GPU_VENDOR[$RANDOM % ${#GPU_VENDOR[@]}]}
# RANDOM_DEVICE=${GPU_DEVICE[$RANDOM % ${#GPU_DEVICE[@]}]}
# RANDOM_VRAM=${GPU_VRAM[$RANDOM % ${#GPU_VRAM[@]}]}

# mkdir -p "$(dirname "$VMX_FILE")"
# cat > "$VMX_FILE" <<EOF
# svga.present = "TRUE"
# svga.vramSize = "$RANDOM_VRAM"
# svga.vendorID = "$RANDOM_VENDOR"
# svga.deviceID = "$RANDOM_DEVICE"
# EOF
# echo "[WebGL] GPU ID/VRAM: $RANDOM_VENDOR / $RANDOM_DEVICE / $RANDOM_VRAM"

# # Random Mesa version từ PPA
# sudo add-apt-repository -y ppa:kisak/kisak-mesa
# sudo apt update
# sudo apt install -y mesa-utils mesa-vulkan-drivers

# # Xóa thư mục .drirc nếu tồn tại để tạo file mới
# [ -d "$HOME/.drirc" ] && rm -rf "$HOME/.drirc"

# # Mesa shader precision config (file .drirc)
# cat > "$HOME/.drirc" <<EOF
# <?xml version="1.0"?>
# <!DOCTYPE driinfo SYSTEM "driinfo.dtd">
# <driconf>
#  <device>
#   <application name="all">
#     <option name="disable_glsl_line_smooth" value="$(shuf -e true false -n1)"/>
#     <option name="vblank_mode" value="$(shuf -e 0 1 2 -n1)"/>
#     <option name="mesa_glthread" value="$(shuf -e true false -n1)"/>
#   </application>
#  </device>
# </driconf>
# EOF

# # Vulkan layer random capability
# mkdir -p ~/.config/vulkan/implicit_layer.d
# cat > ~/.config/vulkan/implicit_layer.d/fp_random.json <<EOF
# {
#     "file_format_version": "1.0.0",
#     "layer": {
#         "name": "FP_RANDOM_LAYER",
#         "type": "INSTANCE",
#         "library_path": "libVkLayer_random.so",
#         "api_version": "1.2.154",
#         "implementation_version": 1,
#         "description": "Random Vulkan Capabilities"
#     }
# }
# EOF
# echo "[WebGL] Mesa + Vulkan config applied."

# =============================
# 2. Canvas – Font, DPI, Fallback
# =============================

#!/usr/bin/env bash
set -euo pipefail

log(){ echo "[Canvas] $*"; }

########################################
# 1.1) DPI scaling: mốc phổ biến, map sang Wayland scale tương ứng
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
# 1.2) Font: cài thêm gói có thật + fonts.conf “tự nhiên”
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
# 1.3) Wayland-only: random resolution theo danh sách (VMware/Virtual-1 OK)
#    - Áp dụng thật qua monitors.xml
#    - Lấy đúng refresh rate bằng modetest
########################################
if [[ "${XDG_SESSION_TYPE:-}" != "wayland" ]]; then
  log "Không phải Wayland → bỏ qua đổi resolution."
  exit 0
fi

# Danh sách như ảnh Settings ▸ Displays
RES_CHOICES=("1920x1200" "1920x1080" "1918x928" "1856x1392" "1792x1344" "1680x1050" "1600x1200" "1600x900" "1440x900" "1400x1050" "1366x768")

# 1.4) Xác định connector đang connected (VD: card0-Virtual-1)
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

# 1.5) Lọc các mode thật sự hỗ trợ
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

# 1.6) Chọn 1 mode hợp lệ + tìm refresh rate khớp bằng modetest
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

# 1.7) Ghi monitors.xml với scale khớp DPI (WAYLAND_SCALE)
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


# =============================
# 3. Audio – Driver & DSP plugin
# =============================
sudo apt install -y pulseaudio-utils sox libsox-fmt-all ladspa-sdk

if systemctl --user is-active pipewire >/dev/null 2>&1; then
    systemctl --user stop pipewire pipewire-pulse wireplumber || true
elif command -v pulseaudio >/dev/null 2>&1; then
    pulseaudio -k || true
fi

sudo modprobe -r snd_ens1371 snd_hda_intel snd_usb_audio || true

AUDIO_DRIVERS=("snd_ens1371" "snd_hda_intel" "snd_usb_audio")
TARGET_AUDIO=${AUDIO_DRIVERS[$RANDOM % ${#AUDIO_DRIVERS[@]}]}
sudo modprobe "$TARGET_AUDIO" || true

DSP_PLUGINS=("noise" "equalizer_1901" "reverb_1433")
DSP_PLUGIN=${DSP_PLUGINS[$RANDOM % ${#DSP_PLUGINS[@]}]}
FILTER_LEVEL=$(shuf -i 1-3 -n1)

mkdir -p ~/.config/pulse
cat > ~/.config/pulse/default.pa <<EOF
.include /etc/pulse/default.pa
load-module module-ladspa-sink sink_name=dsp_out plugin=$DSP_PLUGIN source_port=output control=$FILTER_LEVEL
set-default-sink dsp_out
EOF

if systemctl --user is-active pipewire >/dev/null 2>&1; then
    systemctl --user start pipewire wireplumber pipewire-pulse
elif command -v pulseaudio >/dev/null 2>&1; then
    pulseaudio --start
fi
echo "[Audio] Driver: $TARGET_AUDIO | DSP: $DSP_PLUGIN | Level: $FILTER_LEVEL"

# =============================
# 4. ClientRects – Metrics change
# =============================
HINTING_OPTIONS=("true" "false")
ANTIALIAS_OPTIONS=("true" "false")
SUBPIXEL_OPTIONS=("rgb" "bgr" "vrgb" "vbgr" "none")
RANDOM_HINTING=${HINTING_OPTIONS[$RANDOM % ${#HINTING_OPTIONS[@]}]}
RANDOM_ANTIALIAS=${ANTIALIAS_OPTIONS[$RANDOM % ${#ANTIALIAS_OPTIONS[@]}]}
RANDOM_SUBPIXEL=${SUBPIXEL_OPTIONS[$RANDOM % ${#SUBPIXEL_OPTIONS[@]}]}

cat > ~/.config/fontconfig/render.conf <<EOF
<?xml version='1.0'?>
<!DOCTYPE fontconfig SYSTEM 'fonts.dtd'>
<fontconfig>
  <match target="font">
    <edit name="hinting" mode="assign"><bool>$RANDOM_HINTING</bool></edit>
    <edit name="antialias" mode="assign"><bool>$RANDOM_ANTIALIAS</bool></edit>
    <edit name="rgba" mode="assign"><const>$RANDOM_SUBPIXEL</const></edit>
    <edit name="ascent" mode="assign"><double>$(shuf -i 750-850 -n1)</double></edit>
    <edit name="descent" mode="assign"><double>$(shuf -i 150-250 -n1)</double></edit>
    <edit name="leading" mode="assign"><double>$(shuf -i 50-120 -n1)</double></edit>
  </match>
</fontconfig>
EOF
fc-cache -fv >/dev/null
echo "[ClientRects] hinting=$RANDOM_HINTING, antialias=$RANDOM_ANTIALIAS, subpixel=$RANDOM_SUBPIXEL"

# =============================
# Summary
# =============================
echo "-----------------------------------"
echo "TÓM TẮT:"
# echo "WebGL: Vendor=$RANDOM_VENDOR, Device=$RANDOM_DEVICE, VRAM=$RANDOM_VRAM"
echo "Canvas: DPI=$RANDOM_DPI, Font=$RANDOM_FONT"
echo "Audio: Driver=$TARGET_AUDIO, DSP=$DSP_PLUGIN, Level=$FILTER_LEVEL"
echo "ClientRects: hinting=$RANDOM_HINTING, antialias=$RANDOM_ANTIALIAS, subpixel=$RANDOM_SUBPIXEL"
echo "Hãy reboot VM để các thay đổi áp dụng hoàn toàn."
