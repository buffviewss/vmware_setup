bash -c "$(cat <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Đảm bảo các gói cần thiết đã được cài
ensure_packages(){
  info "Đảm bảo PipeWire/WirePlumber/ALSA đã cài..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y --no-install-recommends \
    pipewire pipewire-audio pipewire-pulse wireplumber libspa-0.2-modules alsa-utils
}

# Hàm giúp hiển thị thông tin
info(){ echo "[+] $*"; }

# Hàm giúp báo lỗi
die(){ echo "[x] $*" >&2; exit 1; }

# Kiểm tra quyền root
need_root(){
  if [[ ${EUID:-0} -ne 0 ]]; then
    die "Cần quyền root. Hãy chạy: sudo $0 $*"
  fi
}

# Xác định người dùng thực
detect_user(){
  if [[ -n "${SUDO_USER:-}" ]]; then
    RUN_USER="$SUDO_USER"
  else
    RUN_USER="$(logname 2>/dev/null || who | awk '{print $1; exit}')"
  fi
  [[ -z "$RUN_USER" ]] && die "Không xác định được user để restart services."
}

# Kiểm tra và chọn driver audio
detect_model_and_codec(){
  local LSPCI="$(lspci -nn | grep -i audio || true)"
  MODEL="$(echo "$LSPCI" | head -n1)"
  [[ -z "$MODEL" ]] && MODEL="(unknown audio device)"

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
}

# Cấu hình PipeWire
write_pw_conf(){
  mkdir -p /etc/pipewire/pipewire.conf.d
  cat > /etc/pipewire/pipewire.conf.d/99-audio-persona-linux.conf <<EOF
context.properties = {
  default.clock.rate          = 48000
  default.clock.allowed-rates = [ 48000 44100 ]
  default.clock.quantum       = 1024
  default.clock.min-quantum   = 512
  default.clock.max-quantum   = 2048
}
EOF
}

# Restart user services để áp dụng cấu hình
restart_user_services(){
  info "Khởi động lại PipeWire/WirePlumber cho user: $RUN_USER"
  sudo -u "$RUN_USER" systemctl --user daemon-reload || true
  sudo -u "$RUN_USER" systemctl --user restart pipewire pipewire-pulse wireplumber || true
}

# Main function
main(){
  need_root
  detect_user
  ensure_packages
  detect_model_and_codec
  write_pw_conf
  restart_user_services
  echo "[HOÀN TẤT] Tác vụ Audio Persona đã thực hiện xong."
}

main "$@"
EOF
)"
