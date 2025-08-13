#!/usr/bin/env bash
# Ubuntu 24.04 + Wayland one-shot "real human" display & fonts setup
# - Random hợp lý (hardware-aware) cho máy mới, sau đó cố định
# - Không xóa cấu hình cũ; chỉ ghi khi khác; phù hợp Wayland (GNOME)

set -Eeuo pipefail

########################################
# 0) Utils & one-shot guard
########################################
log() { printf '[%(%F %T)T] %s\n' -1 "$*"; }

LOCK_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/realize"
LOCK_FILE="$LOCK_DIR/wayland_fingerprint.lock"
STATE_JSON="${XDG_CONFIG_HOME:-$HOME/.config}/realize/fingerprint_applied.json"
mkdir -p "$LOCK_DIR" "$(dirname "$STATE_JSON")"

if [[ -f "$LOCK_FILE" && "${FORCE:-0}" != "1" ]]; then
  log "Đã áp dụng trước đó ($(cat "$LOCK_FILE" 2>/dev/null || true)). Bỏ qua (FORCE=1 để làm lại)."
  exit 0
fi

trap 'log "Có lỗi xảy ra. Giữ nguyên tối đa những gì đã thiết lập."' ERR

# Lấy thông tin bản phân phối (log tham khảo)
if command -v lsb_release >/dev/null 2>&1; then
  log "Distro: $(lsb_release -ds 2>/dev/null || true)"
fi
log "Session type: ${XDG_SESSION_TYPE:-unknown}"

########################################
# 1) DPI scaling (ưu tiên dựa trên DPI thực; cho phép override TEXT_SCALE)
########################################
TEXT_SCALE="${TEXT_SCALE:-auto}"

# Các mốc người dùng hay dùng (giữ lại từ bản cũ)
POPULAR_SCALES=(1.00 1.00 1.10 1.15 1.20 1.25 1.25 1.33 1.50)

nearest_wayland_scale() {
  # Map về 1.00/1.25/1.50/1.75/2.00
  local v="$1" a=(1.00 1.25 1.50 1.75 2.00) best="${a[0]}" d dd
  d=$(awk -v x="$v" -v y="${a[0]}" 'BEGIN{d=x-y; if(d<0)d=-d; print d}')
  for s in "${a[@]:1}"; do
    dd=$(awk -v x="$v" -v y="$s" 'BEGIN{d=x-y; if(d<0)d=-d; print d}')
    awk -v dd="$dd" -v d="$d" 'BEGIN{exit !(dd<d)}' && { d="$dd"; best="$s"; }
  done
  printf "%.2f" "$best"
}

########################################
# 2) Fonts: phổ biến, không xóa, alias tự nhiên; cho tắt bằng INSTALL_FONTS=0
########################################
INSTALL_FONTS="${INSTALL_FONTS:-1}"

safe_install_fonts() {
  if [[ "$INSTALL_FONTS" = "1" ]]; then
    sudo apt-get update -y >/dev/null 2>&1 || true
    # Giữ gọn & phổ biến cho Ubuntu 24.04
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
    log "Bỏ qua bước cài thêm font (INSTALL_FONTS=0)."
  fi
}
safe_install_fonts

# Chọn 1 sans-serif sẵn có để ưu tiên (giữ chức năng cũ)
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
    # Chọn "random" 1 lần theo seed (ở dưới), tạm để Ubuntu nếu chưa có seed
    PREF_HEAD="${INSTALLED_SANS[0]}"
  fi
fi

mkdir -p ~/.config/fontconfig
FC_FILE="$HOME/.config/fontconfig/fonts.conf"
generate_fonts_conf() {
cat <<EOF
<?xml version='1.0'?>
<!DOCTYPE fontconfig SYSTEM 'fonts.dtd'>
<fontconfig>
  <!-- Ưu tiên tự nhiên, không ép toàn hệ thống -->
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
}
TMP_FC="$(mktemp)"
generate_fonts_conf > "$TMP_FC"
if ! cmp -s "$TMP_FC" "$FC_FILE" 2>/dev/null; then
  mv -f "$TMP_FC" "$FC_FILE"
  log "fonts.conf đã cập nhật (tự nhiên hơn)."
else
  rm -f "$TMP_FC"
  log "fonts.conf không đổi."
fi
if command -v fc-cache >/dev/null 2>&1; then
  fc-cache -f >/dev/null 2>&1 || true
fi

########################################
# 3) Wayland-only: chọn độ phân giải thật & refresh từ phần cứng; monitors.xml
########################################
# Cho phép bỏ qua phần hiển thị nếu không phải Wayland (giữ hành vi cũ)
if [[ "${XDG_SESSION_TYPE:-}" != "wayland" ]]; then
  log "Không phải Wayland → bỏ qua đổi resolution (vẫn set fonts/text-scale nếu áp dụng)."
else
  # 3.1) Xác định connector đang connected
  DRM_CONNECTED=$(for s in /sys/class/drm/*/status; do
    [[ -f "$s" ]] || continue
    [[ "$(cat "$s")" == "connected" ]] && dirname "$s" | xargs -I{} basename {}
  done | head -n1)

  if [[ -z "${DRM_CONNECTED:-}" ]]; then
    log "Không phát hiện connector đang kết nối trong /sys/class/drm."
  else
    CONNECTOR="${DRM_CONNECTED#card*-}"     # -> Virtual-1 / eDP-1 / HDMI-A-1 ...
    MODES_FILE="/sys/class/drm/${DRM_CONNECTED}/modes"
    if [[ -f "$MODES_FILE" ]]; then
      # 3.2) Mode thật từ kernel
      mapfile -t REAL_MODES < <(sed -e 's/[[:space:]]*$//' "$MODES_FILE" | awk '!seen[$0]++')

      # 3.3) Danh sách phổ biến (giữ từ bản cũ) → giao với mode thật
      RES_CHOICES=("1920x1200" "1920x1080" "1918x928" "1856x1392" "1792x1344" "1680x1050" "1600x1200" "1600x900" "1440x900" "1400x1050" "1366x768")
      CANDIDATES=()
      for r in "${RES_CHOICES[@]}"; do
        if printf "%s\n" "${REAL_MODES[@]}" | grep -qx -- "$r"; then
          CANDIDATES+=("$r")
        fi
      done
      # Nếu rỗng, dùng toàn bộ mode thật (trông đời hơn là ép danh sách)
      if ((${#CANDIDATES[@]}==0)); then
        CANDIDATES=("${REAL_MODES[@]}")
      fi

      # 3.4) Ưu tiên "preferred" từ modetest nếu có
      if ! command -v modetest >/dev/null 2>&1; then
        sudo apt-get update -y >/dev/null 2>&1 || true
        sudo apt-get install -y libdrm-tests >/dev/null 2>&1 || true
      fi

      WIDTH=""; HEIGHT=""; RATE=""
      if command -v modetest >/dev/null 2>&1; then
        # Lấy preferred cho connector
        # - Dòng có '*' là preferred; chọn từ CANDIDATES nếu có; nếu không có '*' thì chọn cái đầu tiên khớp
        while IFS= read -r cand; do
          w="${cand%x*}"; h="${cand#*x}"
          rate_line="$(modetest -c 2>/dev/null | awk -v c="$CONNECTOR" -v w="$w" -v h="$h" '
            $0 ~ "^Connector .*\\(" c "\\):" {in=1; next}
            in && /^Connector / {in=0}
            in && $1 ~ /^[0-9]+x[0-9]+$/ {
              split($1,xy,"x"); if (xy[1]==w && xy[2]==h) {
                if (index($0,"*")) { print $0; exit }  # preferred
                if (!line) line=$0
              }
            }
            END { if (line) print line }
          ')"
          if [[ -n "$rate_line" ]]; then
            WIDTH="$w"; HEIGHT="$h"
            # Tách tần số: ưu tiên số có dấu '*', nếu không có thì lấy số đầu
            RATE="$(awk '
              {
                for(i=2;i<=NF;i++){
                  gsub(/[^0-9.\\*]/,"",$i);
                  if($i ~ /\\*$/){ gsub(/\\*/,"",$i); print $i; exit }
                  if(!first && $i ~ /^[0-9.]+$/){ first=$i }
                }
              }
              END{ if(first) print first }
            ' <<<"$rate_line")"
            [[ -n "$RATE" ]] && break
          fi
        done < <(printf "%s\n" "${CANDIDATES[@]}")
      fi

      # Fallback: nếu vẫn trống, chọn ứng viên đầu + rate 60.00
      if [[ -z "${WIDTH:-}" || -z "${RATE:-}" ]]; then
        PICK="${CANDIDATES[0]}"
        WIDTH="${PICK%x*}"; HEIGHT="${PICK#*x}"
        RATE="60.00"
      fi

      # 3.5) EDID: vendor/product/serial + kích thước vật lý để tính DPI
      VENDOR=""; PRODUCT=""; SERIAL=""; WIDTH_CM=""; HEIGHT_CM=""
      if [[ -r "/sys/class/drm/${DRM_CONNECTED}/edid" ]]; then
        if ! command -v edid-decode >/dev/null 2>&1; then
          sudo apt-get update -y >/dev/null 2>&1 || true
          sudo apt-get install -y edid-decode >/dev/null 2>&1 || true
        fi
        if command -v edid-decode >/dev/null 2>&1; then
          EDID_DEC="$(edid-decode "/sys/class/drm/${DRM_CONNECTED}/edid" 2>/dev/null || true)"
          # Parse thương hiệu/mã/serial
          VENDOR="$(awk '/Manufacturer:/{print $2; exit}' <<<"$EDID_DEC" | tr -cd 'A-Za-z0-9._-')"
          PRODUCT="$(awk '/Product Code:/{print $3; exit}' <<<"$EDID_DEC" | tr -cd 'A-Za-z0-9x._-')"
          SERIAL="$(awk '/Serial Number:/{print $3; exit}' <<<"$EDID_DEC" | tr -cd 'A-Za-z0-9x._-')"
          # Parse kích thước (cm)
          if awk '/Maximum image size:/{f=1} /Screen size:/{f=1} END{exit !f}' <<<"$EDID_DEC" >/dev/null 2>&1; then
            SIZE_LINE="$(awk '/Maximum image size:|Screen size:/{print; exit}' <<<"$EDID_DEC")"
            WIDTH_CM="$(sed -n 's/.*: *\([0-9]\+\) *cm *x *\([0-9]\+\) *cm.*/\1/p' <<<"$SIZE_LINE" | head -n1)"
            HEIGHT_CM="$(sed -n 's/.*: *\([0-9]\+\) *cm *x *\([0-9]\+\) *cm.*/\2/p' <<<"$SIZE_LINE" | head -n1)"
          fi
        fi
      fi

      # 3.6) Tính DPI & chọn text scale hợp lý nếu auto
      AUTO_TEXT=""
      if [[ "$TEXT_SCALE" == "auto" ]]; then
        if [[ -n "${WIDTH_CM:-}" && -n "${HEIGHT_CM:-}" && "$WIDTH_CM" -gt 0 && "$HEIGHT_CM" -gt 0 ]]; then
          DPI_X="$(awk -v px="$WIDTH" -v cm="$WIDTH_CM" 'BEGIN{print px/(cm/2.54)}')"
          DPI_Y="$(awk -v px="$HEIGHT" -v cm="$HEIGHT_CM" 'BEGIN{print px/(cm/2.54)}')"
          # Lấy trung bình để mượt
          DPI="$(awk -v x="$DPI_X" -v y="$DPI_Y" 'BEGIN{print (x+y)/2.0}')"
          # Map DPI -> text scale quen thuộc
          # <110:1.00, 110-125:1.10, 125-140:1.20, 140-150:1.25, 150-170:1.33, 170-200:1.50, >200:2.00
          AUTO_TEXT="$(awk -v d="$DPI" 'BEGIN{
            s=1.00;
            if(d>=110 && d<125) s=1.10;
            else if(d>=125 && d<140) s=1.20;
            else if(d>=140 && d<150) s=1.25;
            else if(d>=150 && d<170) s=1.33;
            else if(d>=170 && d<200) s=1.50;
            else if(d>=200) s=2.00;
            printf "%.2f", s;
          }')"
          log "DPI≈$(printf '%.1f' "${DPI}") → đề xuất text-scale ${AUTO_TEXT}"
        else
          # Không có kích thước vật lý → chọn mốc phổ biến
          idx=$(( RANDOM % ${#POPULAR_SCALES[@]} ))
          AUTO_TEXT="${POPULAR_SCALES[$idx]}"
          log "Không có kích thước vật lý từ EDID → chọn text-scale phổ biến ${AUTO_TEXT}"
        fi
      fi

      # 3.7) Áp dụng text scale (idempotent)
      TARGET_TEXT_SCALE="${TEXT_SCALE}"
      [[ "$TEXT_SCALE" == "auto" ]] && TARGET_TEXT_SCALE="$AUTO_TEXT"
      if command -v gsettings >/dev/null 2>&1; then
        CUR_SCALE="$(gsettings get org.gnome.desktop.interface text-scaling-factor 2>/dev/null | tr -d "'")" || CUR_SCALE=""
        if [[ -n "${TARGET_TEXT_SCALE:-}" && "$CUR_SCALE" != "$TARGET_TEXT_SCALE" ]]; then
          gsettings set org.gnome.desktop.interface text-scaling-factor "$TARGET_TEXT_SCALE" || true
          log "Text scaling factor set → $TARGET_TEXT_SCALE"
        else
          log "Text scaling factor giữ nguyên: ${CUR_SCALE:-unset}"
        fi
      else
        log "gsettings không sẵn có, bỏ qua set text scale."
      fi

      # 3.8) Wayland UI scale map gần nhất từ text-scale
      BASE_FOR_SCALE="${TARGET_TEXT_SCALE:-1.00}"
      WAYLAND_SCALE="$(nearest_wayland_scale "$BASE_FOR_SCALE")"

      log "Connector: $CONNECTOR"
      log "Modes thật: ${REAL_MODES[*]}"
      log "Chọn ${WIDTH}x${HEIGHT}@${RATE}, wayland-scale=${WAYLAND_SCALE}"
      [[ -n "$VENDOR$PRODUCT$SERIAL" ]] && log "EDID: vendor=$VENDOR product=$PRODUCT serial=$SERIAL"

      # 3.9) Ghi monitors.xml (idempotent, có vendor/product/serial nếu có)
      MON_DIR="$HOME/.config"
      MON_FILE="$MON_DIR/monitors.xml"
      mkdir -p "$MON_DIR"

      TMP_MON="$(mktemp)"
      {
        printf '<monitors version="2">\n  <configuration>\n    <logicalmonitor>\n'
        printf '      <x>0</x>\n      <y>0</y>\n'
        printf '      <scale>%.2f</scale>\n' "$WAYLAND_SCALE"
        printf '      <transform>normal</transform>\n'
        printf '      <monitor>\n        <monitorspec>\n'
        printf '          <connector>%s</connector>\n' "$CONNECTOR"
        if [[ -n "$VENDOR" ]]; then printf '          <vendor>%s</vendor>\n' "$VENDOR"; fi
        if [[ -n "$PRODUCT" ]]; then printf '          <product>%s</product>\n' "$PRODUCT"; fi
        if [[ -n "$SERIAL" ]]; then printf '          <serial>%s</serial>\n' "$SERIAL"; fi
        printf '        </monitorspec>\n        <mode>\n'
        printf '          <width>%s</width>\n          <height>%s</height>\n' "$WIDTH" "$HEIGHT"
        printf '          <rate>%s</rate>\n' "$RATE"
        printf '        </mode>\n      </monitor>\n'
        printf '      <primary>yes</primary>\n'
        printf '    </logicalmonitor>\n  </configuration>\n</monitors>\n'
      } > "$TMP_MON"

      if ! cmp -s "$TMP_MON" "$MON_FILE" 2>/dev/null; then
        [[ -f "$MON_FILE" ]] && cp -f "$MON_FILE" "$MON_FILE.bak" && log "Đã sao lưu: $MON_FILE.bak"
        mv -f "$TMP_MON" "$MON_FILE"
        log "Đã ghi $MON_FILE — Wayland sẽ nạp khi đăng nhập mới."
      else
        rm -f "$TMP_MON"
        log "monitors.xml không đổi — bỏ qua ghi."
      fi

      # 3.10) Cập nhật PREF_HEAD theo “random ổn định” sau khi đã biết EDID
      # Dùng seed từ machine-id + product_uuid + EDID (nếu có) + salt (lưu vào lock)
      edid_hex=""
      [[ -r "/sys/class/drm/${DRM_CONNECTED}/edid" ]] && edid_hex="$(hexdump -v -e '1/1 "%02x"' "/sys/class/drm/${DRM_CONNECTED}/edid" 2>/dev/null || true)"
      MACHINE_ID="$(cat /etc/machine-id 2>/dev/null || echo unknown)"
      PRODUCT_UUID="$(cat /sys/class/dmi/id/product_uuid 2>/dev/null || echo unknown)"
      if [[ -f "$LOCK_FILE" ]]; then
        SALT="$(awk -F= '/^SALT=/{print $2}' "$LOCK_FILE" 2>/dev/null || true)"
      else
        SALT="$(xxd -l 8 -p /dev/urandom 2>/dev/null || echo randsalt)"
      fi
      SEED="$(printf '%s' "${MACHINE_ID}${PRODUCT_UUID}${edid_hex}${SALT}" | sha1sum | cut -c1-12)"

      if ((${#INSTALLED_SANS[@]:-0})); then
        idx=$(( 0x$(printf '%s' "${SEED}sans" | sha1sum | cut -c1-6) % ${#INSTALLED_SANS[@]} ))
        PREF_HEAD="${INSTALLED_SANS[$idx]}"
        # Nếu fonts.conf chưa ưu tiên đúng PREF_HEAD thì ghi lại (nhẹ)
        TMP_FC2="$(mktemp)"; generate_fonts_conf > "$TMP_FC2"
        if ! cmp -s "$TMP_FC2" "$FC_FILE" 2>/dev/null; then
          mv -f "$TMP_FC2" "$FC_FILE"
          command -v fc-cache >/dev/null 2>&1 && fc-cache -f >/dev/null 2>&1 || true
          log "Ưu tiên sans-serif ngẫu nhiên-ổn định: $PREF_HEAD (ghi lại fonts.conf)"
        else
          rm -f "$TMP_FC2"
        fi
      fi

      # 3.11) Ghi trạng thái áp dụng (JSON) & lock
      jq_payload="$(cat <<JSON
{
  "timestamp": "$(date --iso-8601=seconds)",
  "connector": "$CONNECTOR",
  "vendor": "$VENDOR",
  "product": "$PRODUCT",
  "serial": "$SERIAL",
  "mode": {"width": $WIDTH, "height": $HEIGHT, "rate": "$RATE"},
  "text_scale": "${TARGET_TEXT_SCALE:-unset}",
  "wayland_scale": "$WAYLAND_SCALE",
  "preferred_sans": "$PREF_HEAD"
}
JSON
)"
      printf '%s\n' "$jq_payload" > "$STATE_JSON" 2>/dev/null || true
      {
        echo "APPLIED=$(date --iso-8601=seconds)"
        echo "SALT=$SALT"
        echo "SEED=$SEED"
        echo "CONNECTOR=$CONNECTOR"
        echo "MODE=${WIDTH}x${HEIGHT}@${RATE}"
        echo "TEXT_SCALE=${TARGET_TEXT_SCALE:-unset}"
        echo "WAYLAND_SCALE=$WAYLAND_SCALE"
        echo "PREF_SANS=$PREF_HEAD"
      } > "$LOCK_FILE"

      log "Hoàn tất hiển thị. → Gợi ý đăng xuất để GNOME nạp: gnome-session-quit --logout --no-prompt"
    else
      log "Không thấy $MODES_FILE để kiểm tra mode khả dụng."
    fi
  fi
fi

log "DONE."
