
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

MIN=1.01
MAX=1.45
RANDOM_DPI=$(awk -v min=$MIN -v max=$MAX 'BEGIN{srand(); printf "%.2f", min+rand()*(max-min)}')

gsettings set org.gnome.desktop.interface text-scaling-factor "$RANDOM_DPI" || true
echo "[Canvas] DPI scaling: $RANDOM_DPI"


FONT_DIR="$HOME/.local/share/fonts"
mkdir -p "$FONT_DIR"
FONTS_LIST=("Roboto" "Open Sans" "Lato" "Montserrat" "Source Sans Pro" "Merriweather" "Noto Sans" "Noto Serif" "Ubuntu" "Fira Sans" "Poppins" "Raleway" "Oswald" "PT Sans" "Work Sans")
RANDOM_FONT=${FONTS_LIST[$RANDOM % ${#FONTS_LIST[@]}]}
if ! fc-list | grep -qi "$RANDOM_FONT"; then
    sudo apt install -y fontconfig subversion
    FONT_URL="https://github.com/google/fonts/trunk/ofl/$(echo "$RANDOM_FONT" | tr '[:upper:]' '[:lower:]' | tr -d ' ')"
    svn export --force "$FONT_URL" "$FONT_DIR/$RANDOM_FONT" || true
    fc-cache -fv >/dev/null
fi

mkdir -p ~/.config/fontconfig
cat > ~/.config/fontconfig/fonts.conf <<EOF
<?xml version='1.0'?>
<!DOCTYPE fontconfig SYSTEM 'fonts.dtd'>
<fontconfig>
  <match target="pattern">
    <edit name="family" mode="assign">
      <string>$RANDOM_FONT</string>
    </edit>
  </match>
  <alias>
    <family>sans-serif</family>
    <prefer><family>$RANDOM_FONT</family></prefer>
  </alias>
  <alias>
    <family>serif</family>
    <prefer><family>$RANDOM_FONT</family></prefer>
  </alias>
  <alias>
    <family>monospace</family>
    <prefer><family>$RANDOM_FONT</family></prefer>
  </alias>
</fontconfig>
EOF
fc-cache -fv >/dev/null
echo "[Canvas] Font default & fallback: $RANDOM_FONT"

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
