#!/usr/bin/env bash
# Ubuntu 24.04 + Wayland — Random fingerprint MỖI LẦN CHẠY (100% dựa trên phần cứng)
# - Không fake EDID/mode/refresh; chỉ chọn thứ phần cứng khai báo thật
# - Random mỗi lần: độ phân giải, refresh, text scale, font ưu tiên (tránh lặp cấu hình trước)
# - Sửa lỗi thoát sớm: KHÔNG dùng `set -eE`/trap ERR; các so sánh không trả về non-zero

set -u -o pipefail
[[ "${DEBUG:-0}" == "1" ]] && set -x
shopt -s nullglob

log() { printf '[%(%F %T)T] %s\n' -1 "$*"; }

TEXT_SCALE="${TEXT_SCALE:-auto}"     # auto | số thực (vd 1.25)
INSTALL_FONTS="${INSTALL_FONTS:-1}"  # 1 cài thêm font phổ biến, 0 bỏ qua

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

# 0) Thông tin hệ
command -v lsb_release >/dev/null 2>&1 && log "Distro: $(lsb_release -ds)"
log "Session type: ${XDG_SESSION_TYPE:-unknown}"

# 1) Fonts phổ biến (không xóa gì)
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

# 2) Ưu tiên 1 sans-serif đang có thật (random mỗi lần, tránh lặp nếu có file cũ)
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
# chọn khác lần trước nếu được
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

# 3) Nếu không Wayland: chỉ random text-scale rồi thoát phần hiển thị
if [[ "${XDG_SESSION_TYPE:-}" != "wayland" ]]; then
  log "Không phải Wayland → bỏ qua monitors.xml."
fi

# 4) Lấy mode/refresh thật từ phần cứng (Wayland)
WIDTH=""; HEIGHT=""; RATE=""; CONNECTOR=""; DRM_CONNECTED=""
if [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]]; then
  for s in /sys/class/drm/*/status; do
    [[ -f "$s" ]] || continue
    if [[ "$(cat "$s")" == "connected" ]]; then
      DRM_CONNECTED="$(basename "$(dirname "$s")")"
      break
    fi
  done

  if [[ -n "$DRM_CONNECTED" ]]; then
    CONNECTOR="${DRM_CONNECTED#card*-}"
    MODES_FILE="/sys/class/drm/${DRM_CONNECTED}/modes"
    if [[ -f "$MODES_FILE" ]]; then
      mapfile -t REAL_MODES < <(sed -e 's/[[:space:]]*$//' "$MODES_FILE" | awk '!seen[$0]++')
      # random 1 mode thật; nếu có config cũ, tránh lặp width/height
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

      # refresh list dùng modetest (ưu tiên có '*'), random khác lần trước nếu có
      command -v modetest >/dev/null 2>&1 || { sudo apt-get update -y >/dev/null 2>&1 || true; sudo apt-get install -y libdrm-tests >/dev/null 2>&1 || true; }
      if command -v modetest >/dev/null 2>&1; then
        mapfile -t RATES < <(modetest -c 2>/dev/null | awk -v c="$CONNECTOR" -v w="$WIDTH" -v h="$HEIGHT" '
          $0 ~ "^Connector .*\\(" c "\\):" {in=1; next}
          in && /^Connector / {in=0}
          in && $1 ~ /^[0-9]+x[0-9]+$/ {
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

# 5) EDID & DPI → chọn text-scale (random hợp lý quanh DPI hoặc mốc phổ biến)
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
    # chọn lân cận BASE (ngẫu nhiên)
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

# 6) monitors.xml (Wayland): vendor/product/serial từ EDID (nếu có)
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
