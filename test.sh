# 1) Tạo file
cat > audio-persona-linux.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# audio-persona-linux.sh — Ubuntu 24.04 (Wayland) ONLY
# Mục tiêu: fingerprint AudioContext "trông như thật" bằng cách:
#  - Khóa sample-rate 48 kHz (chuẩn Linux)
#  - Đặt buffer quantum hợp lý
#  - Đặt tên thiết bị dựa trên PHẦN CỨNG THẬT (HDA/ES1371 và codec ALC nếu có)
#  - Không random mỗi lần; mặc định ổn định theo máy
#
# Tuỳ chọn:
#   --rate 48000|44100     (mặc định 48000; khuyên 48000 trên Linux)
#   --quantum N            (512|1024|2048; mặc định auto=1024)
#   --no-rename            (không đụng tới nhãn thiết bị)
#   --rotate-weekly        (thay đổi NHẸ quantum theo tuần; vẫn giữ 48 kHz)
#   --revert               (gỡ cấu hình)
#   --vmx-hint             (gợi ý dùng hdaudio trong .vmx — KHÔNG yêu cầu)
#
# Ghi chú:
# - Không cài hay bật JACK realtime.
# - Chỉ cài các gói PipeWire/WirePlumber/ALSA cần thiết.

# ---------- Config paths ----------
PW_DIR="/etc/pipewire/pipewire.conf.d"
PW_FILE="$PW_DIR/99-audio-persona-linux.conf"
WP_DIR="/etc/wireplumber/main.lua.d"
WP_FILE="$WP_DIR/51-audio-persona-linux.lua"

# ---------- Utils ----------
info(){ echo "[+] $*"; }
warn(){ echo "[!] $*" >&2; }
die(){  echo "[x] $*" >&2; exit 1; }

need_root(){
  if [[ ${EUID:-0} -ne 0 ]]; then
    die "Cần quyền root. Hãy chạy: sudo $0 $*"
  fi
}

detect_user(){
  # Lấy user thật để restart user services
  if [[ -n "${SUDO_USER:-}" ]]; then
    RUN_USER="$SUDO_USER"
  else
    RUN_USER="$(logname 2>/dev/null || who | awk '{print $1; exit}')"
  fi
  [[ -z "$RUN_USER" ]] && die "Không xác định được user để restart services."
}

# ---------- Arg parse ----------
RATE="48000"
Q_AUTO="1"; QUANTUM="1024"
DO_RENAME="1"
ROTATE_WEEKLY="0"
DO_REVERT="0"
DO_VMX_HINT="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rate) RATE="$2"; shift 2;;
    --quantum) Q_AUTO="0"; QUANTUM="$2"; shift 2;;
    --no-rename) DO_RENAME="0"; shift;;
    --rotate-weekly) ROTATE_WEEKLY="1"; shift;;
    --revert) DO_REVERT="1"; shift;;
    --vmx-hint) DO_VMX_HINT="1"; shift;;
    -h|--help)
      cat <<HLP
Usage: sudo $0 [--rate 48000] [--quantum 1024] [--no-rename] [--rotate-weekly] [--revert] [--vmx-hint]
HLP
      exit 0;;
    *) die "Option không hợp lệ: $1";;
  esac
done

# ---------- Package ensure ----------
ensure_packages(){
  info "Đảm bảo PipeWire/WirePlumber/ALSA đã cài..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y --no-install-recommends \
    pipewire pipewire-audio pipewire-pulse wireplumber libspa-0.2-modules alsa-utils
}

# ---------- Hardware detection ----------
detect_model_and_codec(){
  # Lấy chuỗi model PCI audio
  local LSPCI="$(lspci -nn | grep -i audio || true)"
  MODEL="$(echo "$LSPCI" | head -n1)"
  [[ -z "$MODEL" ]] && MODEL="(unknown audio device)"

  # Tìm codec Realtek ALC nếu có
  CODEC=""
  if ls /proc/asound/ 1>/dev/null 2>&1; then
    while read -r f; do
      [[ -f "$f" ]] || continue
      local line
      line="$(grep -m1 -E '^Codec:' "$f" || true)"
      if echo "$line" | grep -qi 'Realtek ALC'; then
        CODEC="$(echo "$line" | sed 's/^Codec:\s*//')"
        break
      fi
    done < <(ls /proc/asound/card*/codec* 2>/dev/null || true)
  fi

  # Lấy tên aplay -l để tham khảo
  APLAY_NAME="$(aplay -l 2>/dev/null | grep -m1 '^card ' || true)"
}

derive_labels(){
  # Mặc định: không ghi đè gì, chỉ nếu DO_RENAME=1 thì đặt cho KHỚP thực tế
  if [[ "$DO_RENAME" -eq 0 ]]; then
    NICK="(unchanged)"; DESC="(unchanged)"; return
  fi

  local model_low="$(echo "$MODEL" | tr '[:upper:]' '[:lower:]')"
  if echo "$model_low" | grep -q 'es1371'; then
    # VMware ES1371 (AudioPCI)
    NICK="Ensoniq AudioPCI ES1371"
    DESC="Sound Blaster PCI 128 (ES1371)"
  elif echo "$model_low" | grep -Eq 'hd audio|ich9|intel.*audio|hdaudio'; then
    if [[ -n "$CODEC" ]]; then
      # Ví dụ: "Realtek ALC887 HD Audio"
      local alc="$(echo "$CODEC" | sed -n 's/.*\(Realtek ALC[0-9A-Za-z]\+\).*/\1/p')"
      if [[ -n "$alc" ]]; then
        NICK="$alc"
        DESC="$alc HD Audio"
      else
        NICK="HDA Intel PCH"
        DESC="Built-in Audio HD (PCH)"
      fi
    else
      NICK="HDA Intel PCH"
      DESC="Built-in Audio HD (PCH)"
    fi
  else
    # Fallback an toàn
    NICK="HDA Intel PCH"
    DESC="Built-in Audio HD (PCH)"
  fi
}

# ---------- PipeWire config ----------
pick_quantum(){
  # Mặc định 1024; nếu --rotate-weekly thì thay đổi NHẸ theo tuần
  if [[ "$Q_AUTO" -eq 0 ]]; then
    return
  fi
  if [[ "$ROTATE_WEEKLY" -eq 1 ]]; then
    # Sử dụng năm+tuần → xoay giữa 512/1024/2048 (nhẹ, không đụng sample-rate)
    local wk="$(date +%G%V)"
    case $((wk % 3)) in
      0) QUANTUM="512";;
      1) QUANTUM="1024";;
      2) QUANTUM="2048";;
    esac
  else
    QUANTUM="1024"
  fi
}

bounds_for_quantum(){
  case "$QUANTUM" in
    512)  MINQ="256";  MAXQ="1024";;
    1024) MINQ="512";  MAXQ="2048";;
    2048) MINQ="512";  MAXQ="4096";;
    *)    die "Quantum không hợp lệ: $QUANTUM (chỉ 512/1024/2048)";;
  esac
}

write_pw_conf(){
  mkdir -p "$PW_DIR"
  cat > "$PW_FILE" <<EOF
# Generated by audio-persona-linux.sh (Ubuntu 24.04)
context.properties = {
  default.clock.rate          = ${RATE}
  default.clock.allowed-rates = [ 48000 44100 ]
  default.clock.quantum       = ${QUANTUM}
  default.clock.min-quantum   = ${MINQ}
  default.clock.max-quantum   = ${MAXQ}
}
EOF
}

write_wp_rule(){
  [[ "$DO_RENAME" -eq 0 ]] && return
  mkdir -p "$WP_DIR"
  cat > "$WP_FILE" <<EOF
-- Generated by audio-persona-linux.sh
-- Đặt nhãn khớp HÀNG THẬT đã dò được
local rule = {
  matches = { { { "device.api", "equals", "alsa" } } },
  apply_properties = {
    ["device.nick"]        = "${NICK}",
    ["device.description"] = "${DESC}"
  }
}
alsa_monitor.rules = alsa_monitor.rules or {}
table.insert(alsa_monitor.rules, rule)
EOF
}

restart_user_services(){
  info "Khởi động lại PipeWire/WirePlumber cho user: $RUN_USER"
  loginctl enable-linger "$RUN_USER" >/dev/null 2>&1 || true
  sudo -u "$RUN_USER" systemctl --user daemon-reload || true
  sudo -u "$RUN_USER" systemctl --user restart pipewire pipewire-pulse wireplumber || true
}

revert_all(){
  info "Gỡ cấu hình đã áp dụng..."
  rm -f "$PW_FILE" "$WP_FILE"
  restart_user_services
  info "Đã hoàn nguyên."
}

vmx_hint(){
  cat <<'EOH'
# Gợi ý cấu hình .vmx (HOST, khi VM tắt) để nhất quán Linux:
sound.present = "TRUE"
sound.autodetect = "TRUE"
sound.virtualDev = "hdaudio"   # Intel HD Audio (tự nhiên nhất trên Linux)
EOH
}

print_summary(){
  echo "------------------------------------------------------------"
  echo "  Audio Persona (Linux) — applied"
  echo "------------------------------------------------------------"
  echo " Model (lspci):   $MODEL"
  [[ -n "$CODEC" ]] && echo " Codec:          $CODEC"
  [[ -n "$APLAY_NAME" ]] && echo " aplay -l:       $APLAY_NAME"
  echo " Sample-rate:     ${RATE} Hz"
  echo " Quantum:         ${QUANTUM} (min ${MINQ} / max ${MAXQ})"
  if [[ "$DO_RENAME" -eq 1 ]]; then
    echo " Nick/Desc:       ${NICK} / ${DESC}"
  else
    echo " Nick/Desc:       (không thay đổi)"
  fi
  echo " Files:"
  echo "  - $PW_FILE"
  [[ "$DO_RENAME" -eq 1 ]] && echo "  - $WP_FILE"
  echo "------------------------------------------------------------"
  echo " Kiểm tra: wpctl status | sed -n '/Audio/,/Video/p'"
  echo " Trong Console: new (AudioContext||webkitAudioContext)().sampleRate"
}

main(){
  need_root
  detect_user

  if [[ "$DO_VMX_HINT" -eq 1 ]]; then
    vmx_hint; exit 0
  fi

  if [[ "$DO_REVERT" -eq 1 ]]; then
    revert_all; exit 0
  fi

  ensure_packages
  detect_model_and_codec
  derive_labels
  pick_quantum
  bounds_for_quantum
  write_pw_conf
  write_wp_rule
  restart_user_services
  print_summary
}

main "$@"
EOF

# 2) Cấp quyền và chạy (ổn định, tự nhiên chuẩn Linux 48 kHz)
chmod +x audio-persona-linux.sh
sudo SUDO_USER=$USER ./audio-persona-linux.sh
