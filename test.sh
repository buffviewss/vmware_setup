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
