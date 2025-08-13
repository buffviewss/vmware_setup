#!/usr/bin/env bash
set -euo pipefail
log(){ echo "[Canvas] $*"; }

# Không chạy bằng root
if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
  echo "[Canvas] Đừng chạy bằng sudo/root. Hãy chạy với user thường."; exit 1
fi

# 0) đảm bảo thư viện D-Bus cho Python
if ! python3 -c 'import gi' 2>/dev/null; then
  sudo apt-get update -y || true
  sudo apt-get install -y python3-gi gir1.2-glib-2.0 >/dev/null 2>&1 || true
fi

########################################
# 1) DPI (text) & UI scale
########################################
TEXT_SCALE="${TEXT_SCALE:-auto}"
if [[ "$TEXT_SCALE" == "auto" ]]; then
  SCALES=(1.0 1.1 1.25 1.33 1.5 1.75 2.0)
  RANDOM_DPI="${SCALES[$RANDOM % ${#SCALES[@]}]}"
else
  RANDOM_DPI="$TEXT_SCALE"
fi
gsettings set org.gnome.desktop.interface text-scaling-factor "$RANDOM_DPI" || true
log "Text scaling factor: $RANDOM_DPI"

UI_SCALES=(1.00 1.25 1.50 1.75 2.00)
WAYLAND_SCALE_MODE="${WAYLAND_SCALE_MODE:-uniform}"
if [[ -n "${FORCE_WAYLAND_SCALE:-}" ]]; then
  WAYLAND_SCALE=$(printf "%.2f" "$FORCE_WAYLAND_SCALE")
else
  if [[ "$WAYLAND_SCALE_MODE" == "near" ]]; then
    nearest=0; best=9e9
    for i in "${!UI_SCALES[@]}"; do
      d=$(awk -v a="${UI_SCALES[$i]}" -v b="$RANDOM_DPI" 'BEGIN{d=a-b; if(d<0)d=-d; print d}')
      awk -v d="$d" -v b="$best" 'BEGIN{exit !(d<b)}' && { nearest=$i; best=$d; }
    done
    cands=($nearest); ((nearest>0)) && cands+=($((nearest-1))); ((nearest<${#UI_SCALES[@]}-1)) && cands+=($((nearest+1)))
    r=$((RANDOM%10)); if ((r<6)); then pick="${cands[0]}"; elif ((r<8)); then pick="${cands[1]:-${cands[0]}}"; else pick="${cands[2]:-${cands[0]}}"; fi
    WAYLAND_SCALE=$(printf "%.2f" "${UI_SCALES[$pick]}")
  else
    WAYLAND_SCALE=$(printf "%.2f" "${UI_SCALES[$RANDOM % ${#UI_SCALES[@]}]}")
  fi
fi
log "Wayland UI scale (immediate): $WAYLAND_SCALE"

# Bật fractional scaling nếu cần
if [[ "$WAYLAND_SCALE" != "1.00" && "$WAYLAND_SCALE" != "2.00" ]]; then
  gsettings set org.gnome.mutter experimental-features "['scale-monitor-framebuffer']" || true
  log "Enabled GNOME fractional scaling feature."
fi

########################################
# 2) Chọn Resolution từ modes thật (hoặc FORCE_RES=WxH)
########################################
# Tìm connector đang connected
DRM_CONNECTED=$(for s in /sys/class/drm/*/status; do
  [[ -f "$s" ]] || continue
  [[ "$(cat "$s")" == "connected" ]] && dirname "$s" | xargs -I{} basename {}
done | head -n1)
[[ -z "${DRM_CONNECTED:-}" ]] && { log "Không thấy connector connected"; exit 0; }

CONNECTOR="${DRM_CONNECTED#card*-}"      # ví dụ Virtual-1
MODES_FILE="/sys/class/drm/${DRM_CONNECTED}/modes"
[[ ! -f "$MODES_FILE" ]] && { log "Không có $MODES_FILE"; exit 0; }

mapfile -t REAL_MODES < <(awk -Fx '{ if ($1>=800 && $2>=600) print $0 }' "$MODES_FILE" | awk '!seen[$0]++')
log "Modes thật: ${REAL_MODES[*]}"

if [[ -n "${FORCE_RES:-}" ]] && printf "%s\n" "${REAL_MODES[@]}" | grep -qx -- "$FORCE_RES"; then
  PICK="$FORCE_RES"
else
  PICK="${REAL_MODES[$RANDOM % ${#REAL_MODES[@]}]}"
fi
TARGET_W="${PICK%x*}"
TARGET_H="${PICK#*x}"
log "Target resolution: ${TARGET_W}x${TARGET_H} (connector=$CONNECTOR)"

########################################
# 3) ÁP DỤNG NGAY bằng D-Bus (org.gnome.Mutter.DisplayConfig)
########################################
APPLY_METHOD="${APPLY_METHOD:-2}"  # 1=temporary, 2=persistent
python3 - <<'PY' || { echo "[Canvas] D-Bus apply failed"; exit 1; }
from gi.repository import Gio, GLib
import os, sys

t_w = int(os.environ['TARGET_W'])
t_h = int(os.environ['TARGET_H'])
scale = float(os.environ['WAYLAND_SCALE'])
conn_name = os.environ.get('CONNECTOR','')
method = int(os.environ.get('APPLY_METHOD','2'))

bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
proxy = Gio.DBusProxy.new_sync(
    bus, 0, None,
    'org.gnome.Mutter.DisplayConfig',
    '/org/gnome/Mutter/DisplayConfig',
    'org.gnome.Mutter.DisplayConfig', None
)

serial, monitors, logical_monitors, props = proxy.call_sync('GetCurrentState', None, 0, -1, None).unpack()

# Chọn monitor theo connector (nếu trùng), nếu không lấy cái đầu tiên
mon_id = None
modes_map = {}
for mid, md in monitors:
    if mon_id is None:
        mon_id = mid
        modes_map = { m_id: m_attr for (m_id, m_attr) in md.get('modes', []) }
    if md.get('connector') == conn_name:
        mon_id = mid
        modes_map = { m_id: m_attr for (m_id, m_attr) in md.get('modes', []) }
        break

# Tìm mode id theo WIDTHxHEIGHT
mode_id = None
for mid, m in modes_map.items():
    if int(m.get('width',-1)) == t_w and int(m.get('height',-1)) == t_h:
        mode_id = mid
        break
if mode_id is None:
    # fallback: lấy mode đầu tiên
    for mid, m in modes_map.items():
        mode_id = mid; t_w=int(m.get('width',t_w)); t_h=int(m.get('height',t_h)); break

# Xây logical_monitors mới (giữ layout, chỉ đổi 'mode' và 'scale')
lm_out = []
for lmid, lmd in logical_monitors:
    new_dict = {}

    # copy các khóa hay gặp
    if 'x' in lmd: new_dict['x'] = GLib.Variant('i', int(lmd['x']))
    if 'y' in lmd: new_dict['y'] = GLib.Variant('i', int(lmd['y']))
    if 'transform' in lmd: new_dict['transform'] = GLib.Variant('i', int(lmd['transform']))
    if 'primary' in lmd: new_dict['primary'] = GLib.Variant('b', bool(lmd['primary']))

    new_dict['scale'] = GLib.Variant('d', scale)

    # monitors: [(u, a{sv})]
    new_mon_list = []
    for pmid, pmd in lmd.get('monitors', []):
        mdict = {}
        if pmid == mon_id:
            mdict['mode'] = GLib.Variant('u', int(mode_id))
        elif 'mode' in pmd:
            mdict['mode'] = GLib.Variant('u', int(pmd['mode']))
        new_mon_list.append((GLib.Variant('u', int(pmid)), GLib.Variant('a{sv}', mdict)))

    new_lm = (GLib.Variant('u', int(lmid)),
              GLib.Variant('a{sv}', {**new_dict, 'monitors': GLib.Variant('a(ua{sv})', new_mon_list)}))
    lm_out.append(new_lm)

lm_array = GLib.Variant('a(ua{sv})', lm_out)
props_v = GLib.Variant('a{sv}', {})

proxy.call_sync('ApplyMonitorsConfig',
                GLib.Variant('(uu@a(ua{sv})@a{sv})', (int(serial), method, lm_array, props_v)),
                0, -1, None)

print(f"[Canvas] D-Bus applied: {t_w}x{t_h} scale={scale} monitor_id={mon_id}")
PY

log "DONE — Resolution/Scale đã đổi NGAY trong phiên."
