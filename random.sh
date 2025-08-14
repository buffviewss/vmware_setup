
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
# Ubuntu 24.04 + Wayland — Random fingerprint MỖI LẦN CHẠY (100% dựa trên phần cứng)
# Fix: tránh dùng biến 'in' trong awk (mawk coi là keyword) → đổi thành 'inside'

set -u -o pipefail
[[ "${DEBUG:-0}" == "1" ]] && set -x
shopt -s nullglob

log() { printf '[%(%F %T)T] %s\n' -1 "$*"; }

TEXT_SCALE="${TEXT_SCALE:-auto}"
INSTALL_FONTS="${INSTALL_FONTS:-1}"

POPULAR_SCALES=(1.00 1.00 1.10 1.15 1.20 1.25 1.25 1.33 1.50)
WAYLAND_STEPS=(1.00 1.25 1.50 1.75 2.00)

float_absdiff() { awk -v x="$1" -v y="$2" 'BEGIN{d=x-y; if(d<0)d=-d; print d}'; }
float_lt()      { awk -v a="$1" -v b="$2" 'BEGIN{print (a<b)?1:0}'; }

nearest_wayland_scale() {
  local v="$1" best="${WAYLAND_STEPS[0]}" bestd
  bestd="$(float_absdiff "$v" "${WAYLAND_STEPS[0]}")"
  for s in "${WAYLAND_STEPS[@]:1}"; do
    local d; d="$(float_absdiff "$v" "$s")"
    if [[ "$(float_lt "$d" "$bestd")" == "1" ]]; then
      best="$s"; bestd="$d"
    fi
  done
  printf "%.2f" "$best"
}

# 0) Info
command -v lsb_release >/dev/null 2>&1 && log "Distro: $(lsb_release -ds)"
log "Session type: ${XDG_SESSION_TYPE:-unknown}"

# 1) Fonts
if [[ "$INSTALL_FONTS" == "1" ]]; then
  sudo apt-get update -y >/dev/null 2>&1 || true
  sudo apt-get install -y \
    fontconfig \
    fonts-ubuntu fonts-cantarell \
    fonts-dejavu-core fonts-dejavu-extra \
    fonts-liberation2 \
    fonts-noto-core fonts-noto-extra fonts-noto-mono fonts-noto-color-emoji \
    fonts-hack-ttf fonts-firacode \
    fonts-roboto \
    >/dev/null 2>&1 || true
  log "Đã cài thêm bộ font phổ biến (không xóa gì)."
else
  log "Bỏ qua cài font (INSTALL_FONTS=0)."
fi

command -v fc-list >/dev/null 2>&1 || sudo apt-get install -y fontconfig >/dev/null 2>&1 || true
PREF_SANS_CANDIDATES=("Ubuntu" "Noto Sans" "DejaVu Sans" "Liberation Sans" "Cantarell" "Roboto")
INSTALLED_SANS=()
if command -v fc-list >/dev/null 2>&1; then
  for f in "${PREF_SANS_CANDIDATES[@]}"; do
    fc-list | grep -qi -- "$f" && INSTALLED_SANS+=("$f")
  done
fi
[[ ${#INSTALLED_SANS[@]} -eq 0 ]] && INSTALLED_SANS=("Ubuntu")

FC_FILE="$HOME/.config/fontconfig/fonts.conf"
LAST_PREF_HEAD=""
if [[ -r "$FC_FILE" ]]; then
  LAST_PREF_HEAD="$(sed -n '/<family>sans-serif<\/family>/,/<\/prefer>/p' "$FC_FILE" \
    | sed -n 's/ *<family>\(.*\)<\/family>.*/\1/p' | head -n1 || true)"
fi
CANDS=("${INSTALLED_SANS[@]}")
if [[ -n "$LAST_PREF_HEAD" && ${#CANDS[@]} -gt 1 ]]; then
  tmp=(); for s in "${CANDS[@]}"; do [[ "$s" != "$LAST_PREF_HEAD" ]] && tmp+=("$s"); done; CANDS=("${tmp[@]}")
fi
PREF_HEAD="${CANDS[$((RANDOM % ${#CANDS[@]}))]}"

mkdir -p ~/.config/fontconfig
cat > "$FC_FILE" <<EOF
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
    <prefer>
      <family>Noto Color Emoji</family>
    </prefer>
  </alias>
</fontconfig>
EOF
command -v fc-cache >/dev/null 2>&1 && fc-cache -f >/dev/null 2>&1 || true
log "fonts.conf đã cập nhật (tự nhiên hơn)."

# 2) Nếu không Wayland, bỏ qua monitors.xml
if [[ "${XDG_SESSION_TYPE:-}" != "wayland" ]]; then
  log "Không phải Wayland → bỏ qua monitors.xml."
fi

# 3) Mode/refresh thật (Wayland)
WIDTH=""; HEIGHT=""; RATE=""; CONNECTOR=""; DRM_CONNECTED=""
if [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]]; then
  for s in /sys/class/drm/*/status; do
    [[ -f "$s" ]] || continue
    if [[ "$(cat "$s")" == "connected" ]]; then
      DRM_CONNECTED="$(basename "$(dirname "$s")")"; break
    fi
  done

  if [[ -n "$DRM_CONNECTED" ]]; then
    CONNECTOR="${DRM_CONNECTED#card*-}"
    MODES_FILE="/sys/class/drm/${DRM_CONNECTED}/modes"
    if [[ -f "$MODES_FILE" ]]; then
      mapfile -t REAL_MODES < <(sed -e 's/[[:space:]]*$//' "$MODES_FILE" | awk '!seen[$0]++')

      LAST_W=""; LAST_H=""; LAST_R=""
      MON_FILE="$HOME/.config/monitors.xml"
      if [[ -r "$MON_FILE" ]]; then
        LAST_W="$(sed -n 's/.*<width>\([0-9]\+\)<\/width>.*/\1/p' "$MON_FILE" | head -n1 || true)"
        LAST_H="$(sed -n 's/.*<height>\([0-9]\+\)<\/height>.*/\1/p' "$MON_FILE" | head -n1 || true)"
        LAST_R="$(sed -n 's/.*<rate>\([0-9.]\+\)<\/rate>.*/\1/p' "$MON_FILE" | head -n1 || true)"
      fi
      CAND_R=("${REAL_MODES[@]}")
      if [[ -n "$LAST_W$LAST_H" && ${#CAND_R[@]} -gt 1 ]]; then
        tmp=(); for r in "${CAND_R[@]}"; do w="${r%x*}"; h="${r#*x}"; [[ "$w" != "$LAST_W" || "$h" != "$LAST_H" ]] && tmp+=("$r"); done; CAND_R=("${tmp[@]}")
      fi
      PICK="${CAND_R[$((RANDOM % ${#CAND_R[@]}))]}"
      WIDTH="${PICK%x*}"; HEIGHT="${PICK#*x}"

      command -v modetest >/dev/null 2>&1 || { sudo apt-get update -y >/dev/null 2>&1 || true; sudo apt-get install -y libdrm-tests >/dev/null 2>&1 || true; }
      if command -v modetest >/dev/null 2>&1; then
        # LẤY DANH SÁCH REFRESH; dùng biến 'inside' thay cho 'in'
        mapfile -t RATES < <(modetest -c 2>/dev/null | awk -v c="$CONNECTOR" -v w="$WIDTH" -v h="$HEIGHT" '
          $0 ~ "^Connector .*\\(" c "\\):" {inside=1; next}
          inside && /^Connector / {inside=0}
          inside && $1 ~ /^[0-9]+x[0-9]+$/ {
            split($1,xy,"x"); if (xy[1]==w && xy[2]==h) {
              rate=$2; raw=$0; gsub(/[^0-9.]/,"",rate);
              if (index(raw,"*")) print rate"*"; else print rate;
            }
          }' | awk 'NF' | awk '!seen[$0]++')
        [[ ${#RATES[@]} -eq 0 ]] && RATES=("60.00")
        if [[ -n "$LAST_R" && ${#RATES[@]} -gt 1 ]]; then
          tmp=(); for r in "${RATES[@]}"; do base="${r%\*}"; [[ "$base" != "$LAST_R" ]] && tmp+=("$r"); done; RATES=("${tmp[@]}")
        fi
        WEIGHTED=()
        for r in "${RATES[@]}"; do
          [[ "$r" == *"*" ]] && WEIGHTED+=("${r%\*}" "${r%\*}" "${r%\*}") || WEIGHTED+=("$r")
        done
        RATE="${WEIGHTED[$((RANDOM % ${#WEIGHTED[@]}))]}"
      else
        RATE="${LAST_R:-60.00}"
      fi
    fi
  fi
fi

# 4) EDID & DPI → chọn text-scale
AUTO_TEXT=""
if [[ "$TEXT_SCALE" == "auto" ]]; then
  WIDTH_CM=""; HEIGHT_CM=""
  if [[ -n "${DRM_CONNECTED:-}" && -r "/sys/class/drm/${DRM_CONNECTED}/edid" ]]; then
    command -v edid-decode >/dev/null 2>&1 || { sudo apt-get update -y >/dev/null 2>&1 || true; sudo apt-get install -y edid-decode >/dev/null 2>&1 || true; }
    if command -v edid-decode >/dev/null 2>&1; then
      EDID_DEC="$(edid-decode "/sys/class/drm/${DRM_CONNECTED}/edid" 2>/dev/null || true)"
      SIZE_LINE="$(awk '/Maximum image size:|Screen size:/{print; exit}' <<<"$EDID_DEC")"
      WIDTH_CM="$(sed -n 's/.*: *\([0-9]\+\) *cm *x *\([0-9]\+\) *cm.*/\1/p' <<<"$SIZE_LINE" | head -n1)"
      HEIGHT_CM="$(sed -n 's/.*: *\([0-9]\+\) *cm *x *\([0-9]\+\) *cm.*/\2/p' <<<"$SIZE_LINE" | head -n1)"
    fi
  fi
  if [[ -n "${WIDTH_CM:-}" && -n "${HEIGHT_CM:-}" && -n "${WIDTH:-}" && -n "${HEIGHT:-}" ]]; then
    DPI_X="$(awk -v px="$WIDTH" -v cm="$WIDTH_CM" 'BEGIN{print px/(cm/2.54)}')"
    DPI_Y="$(awk -v px="$HEIGHT" -v cm="$HEIGHT_CM" 'BEGIN{print px/(cm/2.54)}')"
    DPI="$(awk -v x="$DPI_X" -v y="$DPI_Y" 'BEGIN{print (x+y)/2.0}')"
    BASE="$(awk -v d="$DPI" 'BEGIN{
      s=1.00;
      if(d>=110 && d<125) s=1.10;
      else if(d>=125 && d<140) s=1.20;
      else if(d>=140 && d<150) s=1.25;
      else if(d>=150 && d<170) s=1.33;
      else if(d>=170 && d<200) s=1.50;
      else if(d>=200) s=2.00;
      printf "%.2f", s;
    }')"
    SCALES_SORTED=(1.00 1.10 1.15 1.20 1.25 1.33 1.50 1.75 2.00)
    b=0; bestd=999
    for i in "${!SCALES_SORTED[@]}"; do
      d="$(float_absdiff "${SCALES_SORTED[$i]}" "$BASE")"
      if [[ "$(float_lt "$d" "$bestd")" == "1" ]]; then b=$i; bestd="$d"; fi
    done
    cand_idx=(); [[ $b -gt 0 ]] && cand_idx+=($((b-1))); cand_idx+=($b); [[ $b -lt $((${#SCALES_SORTED[@]}-1)) ]] && cand_idx+=($((b+1)))
    CUR_SCALE="$(gsettings get org.gnome.desktop.interface text-scaling-factor 2>/dev/null | tr -d "'" || true)"
    CANDS=()
    for id in "${cand_idx[@]}"; do
      val="${SCALES_SORTED[$id]}"
      [[ -n "$CUR_SCALE" && "$val" == "$CUR_SCALE" && ${#cand_idx[@]} -gt 1 ]] && continue
      CANDS+=("$val")
    done
    [[ ${#CANDS[@]} -eq 0 ]] && CANDS=("${SCALES_SORTED[$b]}")
    AUTO_TEXT="${CANDS[$((RANDOM % ${#CANDS[@]}))]}"
    log "DPI≈$(printf '%.1f' "${DPI}") → text-scale (random quanh hợp lý) ${AUTO_TEXT}"
  else
    CUR_SCALE="$(gsettings get org.gnome.desktop.interface text-scaling-factor 2>/dev/null | tr -d "'" || true)"
    t=("${POPULAR_SCALES[@]}")
    if [[ -n "$CUR_SCALE" && ${#t[@]} -gt 1 ]]; then
      tmp=(); for s in "${t[@]}"; do [[ "$s" != "$CUR_SCALE" ]] && tmp+=("$s"); done; t=("${tmp[@]}")
    fi
    AUTO_TEXT="${t[$((RANDOM % ${#t[@]}))]}"
    log "Không có kích thước vật lý từ EDID → text-scale phổ biến ${AUTO_TEXT}"
  fi
fi

TARGET_TEXT_SCALE="$TEXT_SCALE"
[[ "$TEXT_SCALE" == "auto" ]] && TARGET_TEXT_SCALE="$AUTO_TEXT"
[[ -z "$TARGET_TEXT_SCALE" ]] && TARGET_TEXT_SCALE="1.00"
command -v gsettings >/dev/null 2>&1 && gsettings set org.gnome.desktop.interface text-scaling-factor "$TARGET_TEXT_SCALE" || true
log "Text scaling factor: $TARGET_TEXT_SCALE"

WAYLAND_SCALE="$(nearest_wayland_scale "$TARGET_TEXT_SCALE")"

# 5) monitors.xml (Wayland) — EDID tags nếu có
if [[ "${XDG_SESSION_TYPE:-}" == "wayland" && -n "${CONNECTOR:-}" && -n "${WIDTH:-}" && -n "${HEIGHT:-}" && -n "${RATE:-}" ]]; then
  VENDOR=""; PRODUCT=""; SERIAL=""
  if [[ -r "/sys/class/drm/${DRM_CONNECTED}/edid" ]]; then
    command -v edid-decode >/dev/null 2>&1 || { sudo apt-get update -y >/dev/null 2>&1 || true; sudo apt-get install -y edid-decode >/dev/null 2>&1 || true; }
    if command -v edid-decode >/dev/null 2>&1; then
      EDID_DEC="$(edid-decode "/sys/class/drm/${DRM_CONNECTED}/edid" 2>/dev/null || true)"
      VENDOR="$(awk '/Manufacturer:/{print $2; exit}' <<<"$EDID_DEC" | tr -cd 'A-Za-z0-9._-')"
      PRODUCT="$(awk '/Product Code:/{print $3; exit}' <<<"$EDID_DEC" | tr -cd 'A-Za-z0-9x._-')"
      SERIAL="$(awk '/Serial Number:/{print $3; exit}' <<<"$EDID_DEC" | tr -cd 'A-Za-z0-9x._-')"
    fi
  fi

  log "Connector: $CONNECTOR"
  log "Chọn ${WIDTH}x${HEIGHT}@${RATE}, wayland-scale=${WAYLAND_SCALE}"
  [[ -n "$VENDOR$PRODUCT$SERIAL" ]] && log "EDID: vendor=$VENDOR product=$PRODUCT serial=$SERIAL"

  MON_DIR="$HOME/.config"; MON_FILE="$MON_DIR/monitors.xml"; mkdir -p "$MON_DIR"
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
$( [[ -n "$VENDOR"  ]] && printf "          <vendor>%s</vendor>\n"  "$VENDOR"  )
$( [[ -n "$PRODUCT" ]] && printf "          <product>%s</product>\n" "$PRODUCT" )
$( [[ -n "$SERIAL"  ]] && printf "          <serial>%s</serial>\n"  "$SERIAL"  )
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
  log "→ Đăng xuất nhanh: gnome-session-quit --logout --no-prompt"
fi

log "DONE."


# =============================
# 3. Audio – Driver & DSP plugin
# =============================
#!/usr/bin/env bash
# audiofp-persist.sh (v3.2)
# Ubuntu 24.04 + Wayland + PipeWire/WirePlumber
# - KHÔNG tham số => auto-apply random model
# - --force-channels <1|2|6|8>  (ép số kênh)
# - --latency-class <low|mid|high>  (ép quantum: 128/256/(512|1024))
# - Tự cài deps nếu thiếu (sudo apt update && sudo apt install -y pipewire-bin wireplumber pulseaudio-utils)

set -euo pipefail

# ====== PATHS ======
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/audiofp"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
PW_DROPIN_DIR="$CONF_DIR/pipewire/pipewire.conf.d"
WP_DROPIN_DIR="$CONF_DIR/wireplumber/wireplumber.conf.d"
SYSD_USER_DIR="$CONF_DIR/systemd/user"
BIN_DIR="$HOME/.local/bin"

SERVICE_NAME="audiofp-virtual-sink.service"
HELPER="$BIN_DIR/audiofp-ensure-vsink.sh"
PW_DROPIN_FILE="$PW_DROPIN_DIR/70-audiofp.conf"
WP_DROPIN_FILE="$WP_DROPIN_DIR/70-audiofp-defaults.conf"

mkdir -p "$STATE_DIR" "$PW_DROPIN_DIR" "$WP_DROPIN_DIR" "$SYSD_USER_DIR" "$BIN_DIR"

# ====== MODEL POOL ======
declare -A MODEL_RATES MODEL_QUANTA MODEL_DESCS MODEL_CHANNELS

# --- Laptop / Desktop Analog (HDA) ---
MODEL_RATES["laptop-intel-hda"]="44100 48000"
MODEL_QUANTA["laptop-intel-hda"]="128 256 512"
MODEL_DESCS["laptop-intel-hda"]="Intel HDA PCH Analog Realtek ALC257 Analog Realtek ALC295 Analog"
MODEL_CHANNELS["laptop-intel-hda"]="2"

MODEL_RATES["laptop-amd-hda"]="44100 48000"
MODEL_QUANTA["laptop-amd-hda"]="128 256 512"
MODEL_DESCS["laptop-amd-hda"]="AMD Family 17h HD-Audio Analog Realtek ALC256 Analog"
MODEL_CHANNELS["laptop-amd-hda"]="2"

MODEL_RATES["desktop-realtek-alc887"]="44100 48000 96000"
MODEL_QUANTA["desktop-realtek-alc887"]="256 512 1024"
MODEL_DESCS["desktop-realtek-alc887"]="Realtek ALC887 Analog"
MODEL_CHANNELS["desktop-realtek-alc887"]="2"

MODEL_RATES["desktop-realtek-alc892"]="44100 48000 96000"
MODEL_QUANTA["desktop-realtek-alc892"]="256 512 1024"
MODEL_DESCS["desktop-realtek-alc892"]="Realtek ALC892 Analog"
MODEL_CHANNELS["desktop-realtek-alc892"]="2"

MODEL_RATES["desktop-realtek-alc1200"]="44100 48000 96000 192000"
MODEL_QUANTA["desktop-realtek-alc1200"]="256 512 1024"
MODEL_DESCS["desktop-realtek-alc1200"]="Realtek ALC1200 Analog Realtek ALC1220 Analog"
MODEL_CHANNELS["desktop-realtek-alc1200"]="2"

MODEL_RATES["thinkpad-alc257"]="44100 48000"
MODEL_QUANTA["thinkpad-alc257"]="128 256 512"
MODEL_DESCS["thinkpad-alc257"]="ThinkPad ALC257 Analog"
MODEL_CHANNELS["thinkpad-alc257"]="2"

MODEL_RATES["dell-alc256"]="44100 48000"
MODEL_QUANTA["dell-alc256"]="128 256 512"
MODEL_DESCS["dell-alc256"]="DELL ALC256 Analog"
MODEL_CHANNELS["dell-alc256"]="2"

MODEL_RATES["hp-alc245"]="44100 48000"
MODEL_QUANTA["hp-alc245"]="128 256 512"
MODEL_DESCS["hp-alc245"]="HP ALC245 Analog"
MODEL_CHANNELS["hp-alc245"]="2"

# --- HDMI / Display Audio ---
MODEL_RATES["htpc-nvidia-hdmi"]="48000 96000"
MODEL_QUANTA["htpc-nvidia-hdmi"]="256 512 1024"
MODEL_DESCS["htpc-nvidia-hdmi"]="NVIDIA HDMI Audio HDA NVidia HDMI"
MODEL_CHANNELS["htpc-nvidia-hdmi"]="2 6 8"

MODEL_RATES["htpc-amd-hdmi"]="48000 96000"
MODEL_QUANTA["htpc-amd-hdmi"]="256 512 1024"
MODEL_DESCS["htpc-amd-hdmi"]="AMD HDMI Audio HDA ATI HDMI"
MODEL_CHANNELS["htpc-amd-hdmi"]="2 6 8"

MODEL_RATES["intel-uhd-hdmi"]="48000 96000"
MODEL_QUANTA["intel-uhd-hdmi"]="256 512 1024"
MODEL_DESCS["intel-uhd-hdmi"]="Intel HDMI/DP LPE Audio"
MODEL_CHANNELS["intel-uhd-hdmi"]="2 6 8"

# --- USB DACs / Headsets ---
MODEL_RATES["usb-headset-cmedia"]="48000"
MODEL_QUANTA["usb-headset-cmedia"]="128 256 512"
MODEL_DESCS["usb-headset-cmedia"]="USB Audio Device C-Media USB Audio"
MODEL_CHANNELS["usb-headset-cmedia"]="2"

MODEL_RATES["usb-dac-focusrite"]="44100 48000 96000"
MODEL_QUANTA["usb-dac-focusrite"]="128 256 512"
MODEL_DESCS["usb-dac-focusrite"]="Focusrite Scarlett 2i2 USB"
MODEL_CHANNELS["usb-dac-focusrite"]="2"

MODEL_RATES["usb-dac-fiiok3"]="44100 48000 96000"
MODEL_QUANTA["usb-dac-fiiok3"]="128 256 512"
MODEL_DESCS["usb-dac-fiiok3"]="FiiO K3 USB DAC"
MODEL_CHANNELS["usb-dac-fiiok3"]="2"

MODEL_RATES["usb-dac-ugreen"]="44100 48000"
MODEL_QUANTA["usb-dac-ugreen"]="128 256 512"
MODEL_DESCS["usb-dac-ugreen"]="UGREEN USB Audio"
MODEL_CHANNELS["usb-dac-ugreen"]="2"

MODEL_RATES["usb-headset-logitech-h390"]="48000"
MODEL_QUANTA["usb-headset-logitech-h390"]="128 256 512"
MODEL_DESCS["usb-headset-logitech-h390"]="Logitech H390 USB Headset"
MODEL_CHANNELS["usb-headset-logitech-h390"]="2"

MODEL_RATES["usb-headset-hyperx"]="48000"
MODEL_QUANTA["usb-headset-hyperx"]="128 256 512"
MODEL_DESCS["usb-headset-hyperx"]="HyperX USB Audio"
MODEL_CHANNELS["usb-headset-hyperx"]="2"

MODEL_RATES["usb-jabra-speak"]="48000"
MODEL_QUANTA["usb-jabra-speak"]="256 512 1024"
MODEL_DESCS["usb-jabra-speak"]="Jabra SPEAK USB"
MODEL_CHANNELS["usb-jabra-speak"]="2"

# --- Bluetooth (A2DP) ---
MODEL_RATES["bluetooth-a2dp"]="44100 48000"
MODEL_QUANTA["bluetooth-a2dp"]="512 1024"
MODEL_DESCS["bluetooth-a2dp"]="Bluetooth A2DP Sink"
MODEL_CHANNELS["bluetooth-a2dp"]="2"

MODEL_RATES["bt-sony-wh1000xm"]="44100 48000"
MODEL_QUANTA["bt-sony-wh1000xm"]="512 1024"
MODEL_DESCS["bt-sony-wh1000xm"]="WH-1000XM Bluetooth"
MODEL_CHANNELS["bt-sony-wh1000xm"]="2"

MODEL_RATES["bt-sony-wf1000xm"]="44100 48000"
MODEL_QUANTA["bt-sony-wf1000xm"]="512 1024"
MODEL_DESCS["bt-sony-wf1000xm"]="WF-1000XM Bluetooth"
MODEL_CHANNELS["bt-sony-wf1000xm"]="2"

# ====== UTIL ======
need() { command -v "$1" >/dev/null 2>&1; }

install_deps() {
  if ! command -v apt >/dev/null 2>&1; then
    echo ">> Không tìm thấy apt. Hãy cài thủ công: pipewire-bin wireplumber pulseaudio-utils"
    return 1
  fi
  echo ">> Cài phụ thuộc (yêu cầu mật khẩu sudo)…"
  sudo apt update
  sudo apt install -y pipewire-bin wireplumber pulseaudio-utils
}

ensure_deps() {
  local missing=()
  need pw-metadata || missing+=("pipewire-bin")
  need wpctl        || missing+=("wireplumber")
  need pactl        || missing+=("pulseaudio-utils")
  need systemctl    || true
  if ((${#missing[@]})); then
    echo ">> Thiếu: ${missing[*]}"
    install_deps
    need pw-metadata && need wpctl && need pactl || {
      echo ">> Vẫn thiếu công cụ sau khi cài. Kiểm tra lại cài đặt."
      exit 1
    }
  fi
}

rand_word() { local arr=($1); echo "${arr[$((RANDOM % ${#arr[@]}))]}"; }

list_models() {
  echo "Các model sẵn có:"
  for m in "${!MODEL_RATES[@]}"; do
    printf "  - %s  (rates: %s; quanta: %s; ch: %s)\n" \
      "$m" "${MODEL_RATES[$m]}" "${MODEL_QUANTA[$m]}" "${MODEL_CHANNELS[$m]}"
  done | sort
}

pick_model_random() {
  local keys=("${!MODEL_RATES[@]}")
  echo "${keys[$((RANDOM % ${#keys[@]}))]}"
}

get_params_from_model() {
  local model="$1"
  local rates="${MODEL_RATES[$model]:-}"
  local quanta="${MODEL_QUANTA[$model]:-}"
  local descs="${MODEL_DESCS[$model]:-}"
  local chs="${MODEL_CHANNELS[$model]:-2}"

  if [[ -z "$rates" || -z "$quanta" || -z "$descs" ]]; then
    model="laptop-intel-hda"
    rates="${MODEL_RATES[$model]}"
    quanta="${MODEL_QUANTA[$model]}"
    descs="${MODEL_DESCS[$model]}"
    chs="${MODEL_CHANNELS[$model]:-2}"
  fi

  local rate quantum desc ch
  rate="$(rand_word "$rates")"
  quantum="$(rand_word "$quanta")"
  desc="$(rand_word "$descs")"
  ch="$(rand_word "$chs")"
  echo "$model|$rate|$quantum|$desc|$ch"
}

# Map kênh -> channel_map
channel_map_for() {
  case "$1" in
    1) echo "mono" ;;
    2) echo "front-left,front-right" ;;
    6) echo "front-left,front-right,front-center,lfe,rear-left,rear-right" ;;
    8) echo "front-left,front-right,front-center,lfe,rear-left,rear-right,side-left,side-right" ;;
    *) echo "front-left,front-right" ;;
  esac
}

# Map latency-class -> quantum
quantum_from_latency_class() {
  case "$1" in
    low)  echo "128" ;;
    mid)  echo "256" ;;
    high) # cho tự nhiên: 512 hoặc 1024
      if ((RANDOM % 2)); then echo "512"; else echo "1024"; fi ;;
    *)    echo "" ;;
  esac
}

write_pw_dropin() {
  local rate="$1" quantum="$2"
  cat > "$PW_DROPIN_FILE" <<EOF
# Auto-generated by audiofp-persist
context.properties = {
    default.clock.rate          = $rate
    default.clock.allowed-rates = [ $rate ]
    default.clock.quantum       = $quantum
    default.clock.min-quantum   = 64
    default.clock.max-quantum   = 2048
}
EOF
}

write_wp_dropin() {
  cat > "$WP_DROPIN_FILE" <<'EOF'
# Auto-generated by audiofp-persist
wireplumber.settings = {
  node.restore-default-targets = true
}
EOF
}

write_helper_script() {
  local vsink_name="$1" desc="$2" ch="$3" chmap="$4"
  cat > "$HELPER" <<'EOSH'
#!/usr/bin/env bash
set -euo pipefail
VSINK="{{VSINK}}"
DESC="{{DESC}}"
CH="{{CH}}"
CHMAP="{{CHMAP}}"

# Gỡ module cũ
pactl list short modules | awk '/audiofp_vsink|module-virtual-sink/ {print $1}' | xargs -r -n1 pactl unload-module || true

# Master phần cứng
MASTER=$(pactl list short sinks | awk '{print $2}' | grep -E '^(alsa_output|bluez_output)\.' | head -n1)
[[ -z "${MASTER:-}" ]] && exit 0

# Nếu ép 6/8 kênh nhưng master là analog-stereo hoặc bluetooth thì hạ về 2 kênh cho an toàn
if [[ "$CH" -ge 6 ]]; then
  if [[ "$MASTER" == *"analog-stereo"* || "$MASTER" == *"bluez_output"* ]]; then
    CH="2"
    CHMAP="front-left,front-right"
  fi
fi

# Virtual sink nối về master
pactl load-module module-virtual-sink "sink_name=$VSINK sink_properties=node.description='$DESC' master=$MASTER channels=$CH channel_map=$CHMAP" >/dev/null

# Đặt default
pactl set-default-sink "$VSINK" || true

# Yêu cầu WirePlumber lưu default targets
wpctl settings --save node.restore-default-targets true >/dev/null 2>&1 || true
EOSH
  # thay placeholder
  sed -i "s|{{VSINK}}|$vsink_name|g; s|{{DESC}}|$desc|g; s|{{CH}}|$ch|g; s|{{CHMAP}}|$chmap|g" "$HELPER"
  chmod +x "$HELPER"
}

write_systemd_service() {
  cat > "$SYSD_USER_DIR/$SERVICE_NAME" <<EOF
[Unit]
Description=AudioFP Virtual Sink (persistent)
After=pipewire.service wireplumber.service pipewire-pulse.service
Wants=pipewire.service wireplumber.service pipewire-pulse.service

[Service]
Type=oneshot
ExecStart=$HELPER
RemainAfterExit=yes

[Install]
WantedBy=default.target
EOF
}

apply_profile() {
  ensure_deps
  local model="${1:-}" force_ch="${2:-}" latency_class="${3:-}"

  [[ -z "$model" || "${MODEL_RATES[$model]+isset}" != "isset" ]] && model="$(pick_model_random)"
  IFS='|' read -r model rate quantum desc ch <<<"$(get_params_from_model "$model")"

  # Override channels nếu có
  if [[ -n "${force_ch:-}" ]]; then
    case "$force_ch" in
      1|2|6|8) ch="$force_ch" ;;
      *) echo ">> --force-channels chỉ nhận 1|2|6|8"; exit 1 ;;
    esac
  fi

  # Override quantum theo latency-class nếu có
  if [[ -n "${latency_class:-}" ]]; then
    q_override="$(quantum_from_latency_class "$latency_class")" || true
    [[ -n "$q_override" ]] && quantum="$q_override"
  fi

  local vsink="audiofp_vsink_${model}_${rate}_${RANDOM}"
  local chmap; chmap="$(channel_map_for "$ch")"

  write_pw_dropin "$rate" "$quantum"
  write_wp_dropin
  write_helper_script "$vsink" "$desc" "$ch" "$chmap"
  write_systemd_service

  systemctl --user daemon-reload
  systemctl --user enable --now "$SERVICE_NAME"

  systemctl --user restart pipewire pipewire-pulse wireplumber || true
  "$HELPER" || true

  {
    echo "model=$model"
    echo "rate=$rate"
    echo "quantum=$quantum"
    echo "channels=$ch"
    echo "description=$desc"
    echo "vsink=$vsink"
  } > "$STATE_DIR/last_profile.conf"

  echo ">> APPLIED: model=$model | rate=${rate} Hz | quantum=${quantum} | ch=${ch} | desc='${desc}'"
  echo ">> Thoát hẳn và mở lại Chrome/Chromium để WebAudio nhận sample rate & latency mới."
}

rotate_profile() { apply_profile "$1" "$2" "$3"; }

revert_all() {
  echo ">> Reverting AudioFP to defaults…"
  systemctl --user stop "$SERVICE_NAME" 2>/dev/null || true
  systemctl --user disable "$SERVICE_NAME" 2>/dev/null || true
  rm -f "$SYSD_USER_DIR/$SERVICE_NAME" "$HELPER"
  rm -f "$PW_DROPIN_FILE" "$WP_DROPIN_FILE"
  pactl list short modules | awk '/audiofp_vsink|module-virtual-sink/ {print $1}' | xargs -r -n1 pactl unload-module || true
  pw-metadata -n settings 0 clock.force-rate 0  >/dev/null 2>&1 || true
  pw-metadata -n settings 0 clock.force-quantum 0 >/dev/null 2>&1 || true
  systemctl --user restart pipewire pipewire-pulse wireplumber || true
  echo ">> DONE."
}

status() {
  echo "=== PipeWire clock (pw-metadata) ==="
  pw-metadata -n settings 0 | sed 's/^/  /' || true
  echo
  echo "=== Default sink ==="
  pactl info | grep 'Default Sink' || true
  echo
  echo "=== Sinks ==="
  pactl list short sinks | sed 's/^/  /' || true
  echo
  echo "=== Last profile ==="
  [[ -f "$STATE_DIR/last_profile.conf" ]] && sed 's/^/  /' "$STATE_DIR/last_profile.conf" || echo "  (none)"
}

usage() {
  cat <<EOF
Usage:
  $0 models
  $0 apply [--model <name>] [--force-channels <1|2|6|8>] [--latency-class <low|mid|high>]
  $0 rotate [--model <name>] [--force-channels <1|2|6|8>] [--latency-class <low|mid|high>]
  $0 status
  $0 revert
  $0 install-deps

Mặc định (không tham số): auto-apply random model.
Ví dụ:
  $0                                  # Auto apply (random)
  $0 apply --model htpc-nvidia-hdmi --force-channels 8 --latency-class low
  $0 apply --model bluetooth-a2dp --latency-class high
  $0 rotate --force-channels 6 --latency-class mid
EOF
}

# ====== ARG PARSER ======
cmd="${1:-}"; shift || true
model=""
force_channels=""
latency_class=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model)           model="${2:-}"; shift 2 || true ;;
    --force-channels)  force_channels="${2:-}"; shift 2 || true ;;
    --latency-class)   latency_class="${2:-}"; shift 2 || true ;;
    *) break ;;
  esac
done

case "${cmd:-}" in
  models)        list_models ;;
  apply)         apply_profile "$model" "$force_channels" "$latency_class" ;;
  rotate)        rotate_profile "$model" "$force_channels" "$latency_class" ;;
  status)        status ;;
  revert)        revert_all ;;
  install-deps)  install_deps ;;
  "")            echo "No arguments supplied => auto-apply random model"; apply_profile "" "" "" ;;
  *)             usage; exit 1 ;;
esac
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
