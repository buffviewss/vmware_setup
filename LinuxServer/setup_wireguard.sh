#!/usr/bin/env bash
# ======================================================================
# OpenVPN Server (LAN) -> sing-box (tun2socks) -> SOCKS5 Gateway
# Mục tiêu: Android VM (OpenVPN client) -> Ubuntu (OpenVPN server)
#           -> sb-tun (sing-box) -> SOCKS5 (user/pass) -> Internet
# Tested: Ubuntu 20.04/22.04/24.04 (VMware ESXi OK)
# ======================================================================

set -Eeuo pipefail

# =========================
# [1] THÔNG SỐ CẦN SỬA
# =========================

# --- OpenVPN Server ---
BIND_LAN_IP="192.168.50.1"         # IP LAN của Ubuntu (Android sẽ remote tới IP này)
OVPN_PORT="443"                    # TCP/443 khuyến nghị
OVPN_PROTO="tcp"                   # 'tcp' (server sẽ là 'proto tcp-server')
OVPN_NET="10.9.0.0/24"             # subnet VPN cấp cho client
OVPN_DNS1="1.1.1.1"                # DNS đẩy về client
OVPN_DNS2="8.8.8.8"                # DNS đẩy về client
OVPN_TUN_IF="tun0"                 # tên interface OpenVPN server mặc định

# --- SOCKS5 (ra Internet) ---
SOCKS_IP="185.100.170.239"
SOCKS_PORT="52743"
SOCKS_USER="VpvasmYp65hDU9t"                      # "" nếu không cần
SOCKS_PASS="S2aOw7QhmoTO3eg"                      # "" nếu không cần
SOCKS_UDP_OVER_TCP="true"         # true nếu proxy KHÔNG hỗ trợ UDP Associate

# --- sing-box binary ---
SINGBOX_VERSION="1.8.13"
SINGBOX_ARCH="amd64"               # amd64 | arm64 | 386 ...
SINGBOX_URL="https://github.com/SagerNet/sing-box/releases/download/v${SINGBOX_VERSION}/sing-box-${SINGBOX_VERSION}-linux-${SINGBOX_ARCH}.tar.gz"

# --- Tùy chọn IPv6 (để 'false' nếu chưa cần) ---
ENABLE_IPV6="false"
SB_TUN4="198.18.0.1/30"
SB_TUN6="fd00:0:0:1::1/126"

# --- Tên client OpenVPN (sinh file .ovpn) ---
CLIENT_NAME="android"

# --- File/đường dẫn ---
LOG_FILE="/tmp/setup_wireguard.log"  # Sử dụng /tmp để tránh vấn đề quyền
EASYRSA_DIR="/etc/openvpn/easy-rsa"
OVPN_SERVER_DIR="/etc/openvpn/server"
OVPN_CLIENT_OUT="/root/${CLIENT_NAME}.ovpn"
SB_BIN="/usr/local/bin/sing-box"
SB_CONF="/etc/sing-box.json"
SB_SVC="/etc/systemd/system/sing-box.service"
ROUTE_SVC="/etc/systemd/system/ovpn-socks-routing.service"

# =========================
# [2] HÀM TIỆN ÍCH
# =========================
log() { echo "[$(date +'%F %T')] $*" | tee -a "$LOG_FILE"; }
die() { echo -e "\e[31mLỖI:\e[0m $*" | tee -a "$LOG_FILE"; exit 1; }
trap 'die "Dừng tại dòng $LINENO (lệnh: $BASH_COMMAND)"' ERR
require_root() { [[ $EUID -eq 0 ]] || die "Hãy chạy bằng sudo/root."; }
cmd() { log "+ $*"; eval "$*" | tee -a "$LOG_FILE"; }

# =========================
# [3] TIỀN ĐỀ
# =========================
require_root
mkdir -p "$(dirname "$LOG_FILE")"; : > "$LOG_FILE"
log "=== BẮT ĐẦU THIẾT LẬP OpenVPN Server -> sing-box -> SOCKS5 ==="

[[ -n "$BIND_LAN_IP" ]] || die "BIND_LAN_IP chưa điền."
[[ -n "$SOCKS_IP" && -n "$SOCKS_PORT" ]] || die "Điền SOCKS_IP / SOCKS_PORT trước khi chạy."

# =========================
# [4] CÀI GÓI HỆ THỐNG
# =========================
export DEBIAN_FRONTEND=noninteractive
cmd "apt-get update -y"
cmd "apt-get install -y openvpn easy-rsa curl tar iproute2 iptables"
# proxychains4 chỉ dùng test HTTP nếu cần
cmd "apt-get install -y proxychains4 >/dev/null 2>&1 || true"

# =========================
# [5] SYSCTL: ROUTER MODE
# =========================
log "Bật ip_forward, vô hiệu rp_filter để policy routing hoạt động"
cmd "sysctl -w net.ipv4.ip_forward=1"
cmd "sed -ri 's@^#?net.ipv4.ip_forward=.*@net.ipv4.ip_forward=1@' /etc/sysctl.conf"
cmd "sysctl -w net.ipv4.conf.all.rp_filter=0"
cmd "sed -ri 's@^#?net.ipv4.conf.all.rp_filter=.*@net.ipv4.conf.all.rp_filter=0@' /etc/sysctl.conf"

if [[ "$ENABLE_IPV6" == "true" ]]; then
  cmd "sysctl -w net.ipv6.conf.all.forwarding=1"
  cmd "sed -ri 's@^#?net.ipv6.conf.all.forwarding=.*@net.ipv6.conf.all.forwarding=1@' /etc/sysctl.conf"
fi

# =========================
# [6] EASY-RSA: PKI & KEYS
# =========================
log "Khởi tạo PKI với easy-rsa (CA, server, client)"
mkdir -p "$EASYRSA_DIR"
if [[ ! -f "$EASYRSA_DIR/easyrsa" ]]; then
  cmd "cp -r /usr/share/easy-rsa/* '$EASYRSA_DIR/'"
fi
pushd "$EASYRSA_DIR" >/dev/null

export EASYRSA_BATCH=1
export EASYRSA_REQ_CN="vpn-ca"

if [[ ! -d pki ]]; then
  cmd "./easyrsa init-pki"
  cmd "./easyrsa build-ca nopass"
  cmd "./easyrsa build-server-full server nopass"
  cmd "./easyrsa build-client-full $CLIENT_NAME nopass"
  # tls-crypt key
  cmd "openvpn --genkey --secret pki/ta.key"
fi

popd >/dev/null

# =========================
# [7] OPENVPN SERVER CONFIG
# =========================
log "Tạo cấu hình OpenVPN server tại $OVPN_SERVER_DIR/server.conf"
mkdir -p "$OVPN_SERVER_DIR"
# Sao chép key/cert
cmd "install -m 600 '$EASYRSA_DIR/pki/ca.crt' '$OVPN_SERVER_DIR/ca.crt'"
cmd "install -m 600 '$EASYRSA_DIR/pki/issued/server.crt' '$OVPN_SERVER_DIR/server.crt'"
cmd "install -m 600 '$EASYRSA_DIR/pki/private/server.key' '$OVPN_SERVER_DIR/server.key'"
cmd "install -m 600 '$EASYRSA_DIR/pki/ta.key' '$OVPN_SERVER_DIR/ta.key'"

OVPN_SRV_NET="${OVPN_NET%/*}"
OVPN_SRV_MASK="$(ipcalc -m "$OVPN_NET" | awk -F= '/NETMASK/ {print $2}')"

cat > "$OVPN_SERVER_DIR/server.conf" <<EOF
port $OVPN_PORT
proto ${OVPN_PROTO}-server
dev $OVPN_TUN_IF
topology subnet
local $BIND_LAN_IP

server $OVPN_SRV_NET $OVPN_SRV_MASK
ifconfig-pool-persist ipp.txt

ca $OVPN_SERVER_DIR/ca.crt
cert $OVPN_SERVER_DIR/server.crt
key $OVPN_SERVER_DIR/server.key
tls-crypt $OVPN_SERVER_DIR/ta.key

# Bảo mật/cipher hiện đại
data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305
data-ciphers-fallback AES-256-GCM
auth SHA256
persist-key
persist-tun
keepalive 10 120
verb 3
explicit-exit-notify 0

# Đẩy toàn bộ traffic + DNS vào tunnel
push "redirect-gateway def1"
push "dhcp-option DNS $OVPN_DNS1"
push "dhcp-option DNS $OVPN_DNS2"
EOF

# Bật & khởi động OpenVPN server
cmd "systemctl enable --now openvpn-server@server.service"
cmd "sleep 2"
cmd "systemctl --no-pager status openvpn-server@server | sed -n '1,25p' || true"

# =========================
# [8] TẠO FILE .OVPN CHO ANDROID
# =========================
log "Tạo file cấu hình client: $OVPN_CLIENT_OUT"
CA_B64=$(base64 -w0 "$OVPN_SERVER_DIR/ca.crt")
CRT_B64=$(base64 -w0 "$EASYRSA_DIR/pki/issued/${CLIENT_NAME}.crt")
KEY_B64=$(base64 -w0 "$EASYRSA_DIR/pki/private/${CLIENT_NAME}.key")
TA_B64=$(base64 -w0 "$OVPN_SERVER_DIR/ta.key")

cat > "$OVPN_CLIENT_OUT" <<EOF
client
dev tun
proto $OVPN_PROTO
remote $BIND_LAN_IP $OVPN_PORT
resolv-retry infinite
nobind
persist-key
persist-tun
auth SHA256
remote-cert-tls server
verb 3
auth-nocache
cipher AES-256-GCM
setenv opt block-outside-dns

<ca>
$(base64 -d <<<"$CA_B64")
</ca>
<cert>
$(base64 -d <<<"$CRT_B64")
</cert>
<key>
$(base64 -d <<<"$KEY_B64")
</key>
<tls-crypt>
$(base64 -d <<<"$TA_B64")
</tls-crypt>
EOF
cmd "chmod 600 '$OVPN_CLIENT_OUT'"

# =========================
# [9] CÀI ĐẶT sing-box (binary)
# =========================
if ! command -v "$SB_BIN" >/dev/null 2>&1; then
  TMP="$(mktemp -d)"; pushd "$TMP" >/dev/null
  log "Tải sing-box: $SINGBOX_URL"
  cmd "curl -fsSL '$SINGBOX_URL' -o sing-box.tgz"
  cmd "tar xzf sing-box.tgz"
  SB_DIR="$(find . -maxdepth 1 -type d -name 'sing-box-*' | head -n1)"
  [[ -n "$SB_DIR" ]] || die "Giải nén sing-box thất bại."
  cmd "install -m 0755 '$SB_DIR/sing-box' '$SB_BIN'"
  popd >/dev/null; rm -rf "$TMP"
fi
cmd "$SB_BIN version"

# =========================
# [10] CẤU HÌNH sing-box
# =========================
log "Tạo cấu hình sing-box tại $SB_CONF"
IN6_BLOCK=""
if [[ "$ENABLE_IPV6" == "true" ]]; then
  IN6_BLOCK=",\"inet6_address\":\"$SB_TUN6\""
fi

cat > "$SB_CONF" <<EOF
{
  "log": { "level": "info" },
  "inbounds": [
    {
      "type": "tun",
      "interface_name": "sb-tun",
      "inet4_address": "$SB_TUN4"$IN6_BLOCK,
      "mtu": 9000,
      "auto_route": false,
      "stack": "system"
    }
  ],
  "outbounds": [
    {
      "type": "socks",
      "server": "$SOCKS_IP",
      "server_port": $SOCKS_PORT,
      "version": "5",
      "username": "$SOCKS_USER",
      "password": "$SOCKS_PASS",
      "udp_over_tcp": $SOCKS_UDP_OVER_TCP,
      "tag": "socks"
    },
    { "type": "direct", "tag": "direct" }
  ],
  "route": {
    "rules": [
      {
        "protocol": [ "tcp", "udp" ],
        "source_ip_cidr": [ "$OVPN_NET" ],
        "outbound": "socks"
      }
    ],
    "final": "direct"
  }
}
EOF
cmd "chmod 600 '$SB_CONF'"

# =========================
# [11] SYSTEMD: sing-box
# =========================
log "Tạo service sing-box: $SB_SVC"
cat > "$SB_SVC" <<'EOF'
[Unit]
Description=sing-box (tun2socks for OpenVPN->SOCKS5 Gateway)
After=network-online.target
Wants=network-online.target

[Service]
User=root
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box.json
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
cmd "systemctl daemon-reload"
cmd "systemctl enable --now sing-box"

# =========================
# [12] POLICY ROUTING (đẩy traffic từ tun0 vào sb-tun)
# =========================
log "Thiết lập policy routing: fwmark 66 -> table 100 (default dev sb-tun)"
# IPv4
cmd "ip rule add fwmark 66 table 100 2>/dev/null || true"
cmd "ip route add default dev sb-tun table 100 2>/dev/null || true"
cmd "iptables -t mangle -C PREROUTING -i $OVPN_TUN_IF -j MARK --set-mark 66 2>/dev/null || iptables -t mangle -A PREROUTING -i $OVPN_TUN_IF -j MARK --set-mark 66"

if [[ "$ENABLE_IPV6" == "true" ]]; then
  # IPv6 (nếu bật)
  cmd "ip -6 rule add fwmark 66 table 100 2>/dev/null || true"
  cmd "ip -6 route add default dev sb-tun table 100 2>/dev/null || true"
  cmd "ip6tables -t mangle -C PREROUTING -i $OVPN_TUN_IF -j MARK --set-mark 66 2>/dev/null || ip6tables -t mangle -A PREROUTING -i $OVPN_TUN_IF -j MARK --set-mark 66"
fi

# =========================
# [13] SERVICE giữ rule sau reboot
# =========================
log "Tạo service giữ policy routing: $ROUTE_SVC"
cat > "$ROUTE_SVC" <<EOF
[Unit]
Description=Persist OpenVPN->SOCKS policy routing
After=network-online.target sing-box.service openvpn-server@server.service
Wants=network-online.target sing-box.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'ip rule add fwmark 66 table 100 || true'
ExecStart=/bin/sh -c 'ip route add default dev sb-tun table 100 || true'
ExecStart=/bin/sh -c 'iptables -t mangle -C PREROUTING -i $OVPN_TUN_IF -j MARK --set-mark 66 2>/dev/null || iptables -t mangle -A PREROUTING -i $OVPN_TUN_IF -j MARK --set-mark 66'
EOF

if [[ "$ENABLE_IPV6" == "true" ]]; then
  cat >> "$ROUTE_SVC" <<'EOF'
ExecStart=/bin/sh -c 'ip -6 rule add fwmark 66 table 100 || true'
ExecStart=/bin/sh -c 'ip -6 route add default dev sb-tun table 100 || true'
EOF
  cat >> "$ROUTE_SVC" <<EOF
ExecStart=/bin/sh -c 'ip6tables -t mangle -C PREROUTING -i $OVPN_TUN_IF -j MARK --set-mark 66 2>/dev/null || ip6tables -t mangle -A PREROUTING -i $OVPN_TUN_IF -j MARK --set-mark 66'
EOF
fi

cat >> "$ROUTE_SVC" <<'EOF'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

cmd "systemctl daemon-reload"
cmd "systemctl enable --now ovpn-socks-routing"

# =========================
# [14] KIỂM TRA NHANH & THÔNG BÁO
# =========================
log "Kiểm tra trạng thái dịch vụ:"
cmd "systemctl --no-pager status openvpn-server@server | sed -n '1,25p' || true"
cmd "systemctl --no-pager status sing-box | sed -n '1,25p' || true"
log "Kiểm tra interface & routing:"
cmd "ip a show $OVPN_TUN_IF || true"
cmd "ip a show sb-tun || true"
cmd "ip rule show"
cmd "ip route show table 100"
cmd "iptables -t mangle -S PREROUTING | grep MARK || true"

echo
echo "==================== HOÀN TẤT ===================="
echo "→ File cấu hình OpenVPN cho Android: $OVPN_CLIENT_OUT"
echo "   Import vào OpenVPN Connect (Android), 'Remote' = $BIND_LAN_IP:$OVPN_PORT ($OVPN_PROTO)"
echo "→ Mọi traffic của client VPN sẽ đi qua SOCKS5: ${SOCKS_IP}:${SOCKS_PORT}"
echo "→ Log chi tiết: $LOG_FILE"
echo "→ Kiểm thử trên Android: https://ifconfig.io | https://dnsleaktest.com | https://browserleaks.com/webrtc"
echo "=================================================="
