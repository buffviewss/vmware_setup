#!/usr/bin/env bash
# ======================================================================
# OpenVPN Server (LAN) -> sing-box (tun2socks) -> SOCKS5 Gateway
# Mục tiêu: Android VM (OpenVPN client) -> Ubuntu (OpenVPN server)
#           -> sb-tun (sing-box) -> SOCKS5 (user/pass) -> Internet
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
SOCKS_UDP_OVER_TCP="false"         # true nếu proxy KHÔNG hỗ trợ UDP Associate

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

# =========================
# [2] HÀM TIỆN ÍCH
# =========================
log() { echo "[$(date +'%F %T')] $*"; }
die() { echo -e "\e[31mLỖI:\e[0m $*"; exit 1; }
trap 'die "Dừng tại dòng $LINENO (lệnh: $BASH_COMMAND)"' ERR
require_root() { [[ $EUID -eq 0 ]] || die "Hãy chạy bằng sudo/root."; }
cmd() { echo "+ $*"; eval "$*"; }

# =========================
# [3] TIỀN ĐỀ
# =========================
require_root

# =========================
# [4] CÀI GÓI HỆ THỐNG
# =========================
echo "Cài đặt OpenVPN, easy-rsa và các gói cần thiết..."
apt-get update -y
apt-get install -y openvpn easy-rsa curl tar iproute2 iptables

# =========================
# [5] SYSCTL: ROUTER MODE
# =========================
echo "Bật ip_forward, vô hiệu rp_filter để policy routing hoạt động"
sysctl -w net.ipv4.ip_forward=1
sed -ri 's@^#?net.ipv4.ip_forward=.*@net.ipv4.ip_forward=1@' /etc/sysctl.conf
sysctl -w net.ipv4.conf.all.rp_filter=0
sed -ri 's@^#?net.ipv4.conf.all.rp_filter=.*@net.ipv4.conf.all.rp_filter=0@' /etc/sysctl.conf

if [[ "$ENABLE_IPV6" == "true" ]]; then
  sysctl -w net.ipv6.conf.all.forwarding=1
  sed -ri 's@^#?net.ipv6.conf.all.forwarding=.*@net.ipv6.conf.all.forwarding=1@' /etc/sysctl.conf
fi

# =========================
# [6] TẠO FILE VARS (CẬP NHẬT COMMONNAME)
# =========================
echo "Tạo file vars cho EasyRSA..."
cat > /etc/openvpn/easy-rsa/vars <<EOF
# EasyRSA variables
export EASYRSA_BATCH="1"      # Tắt các câu hỏi xác nhận
export EASYRSA_REQ_CN="server" # commonName cho server certificate
export EASYRSA_REQ_COUNTRY="GB"
export EASYRSA_REQ_PROVINCE="London"
export EASYRSA_REQ_CITY="London"
export EASYRSA_REQ_ORG="MyOrg"
export EASYRSA_REQ_EMAIL="iaernaoe@uk.com"
export EASYRSA_REQ_OU="MyOrgUnit"
export EASYRSA_KEY_SIZE=2048   # Kích thước khóa RSA (2048-bit)
export EASYRSA_ALGO="rsa"     # Thuật toán khóa RSA
export EASYRSA_CA_EXPIRE=3650 # Thời gian hết hạn chứng chỉ CA (10 năm)
export EASYRSA_CERT_EXPIRE=3650 # Thời gian hết hạn chứng chỉ (10 năm)

# Set the OpenVPN-related default parameters
export EASYRSA_DEFAULT_NICKNAME="server" # Tên chứng chỉ cho server
export EASYRSA_DEFAULT_KEY_SIZE=2048
EOF

# =========================
# [7] EASY-RSA: PKI & KEYS
# =========================
echo "Khởi tạo PKI với easy-rsa (CA, server, client)"
mkdir -p /etc/openvpn/easy-rsa
cp -r /usr/share/easy-rsa/* /etc/openvpn/easy-rsa/

pushd /etc/openvpn/easy-rsa >/dev/null
export EASYRSA_BATCH=1
export EASYRSA_REQ_CN="server"  # Đảm bảo commonName là "server"

if [[ ! -d pki ]]; then
  ./easyrsa init-pki
  ./easyrsa build-ca nopass
  ./easyrsa build-server-full server nopass  # Sử dụng 'server' làm commonName
  ./easyrsa build-client-full $CLIENT_NAME nopass
  ./easyrsa gen-crl
  openvpn --genkey --secret pki/ta.key
fi
popd >/dev/null

# =========================
# [8] OPENVPN SERVER CONFIG
# =========================
echo "Tạo cấu hình OpenVPN server tại /etc/openvpn/server.conf"
mkdir -p /etc/openvpn/server
cp /etc/openvpn/easy-rsa/pki/ca.crt /etc/openvpn/server/ca.crt
cp /etc/openvpn/easy-rsa/pki/issued/server.crt /etc/openvpn/server/server.crt
cp /etc/openvpn/easy-rsa/pki/private/server.key /etc/openvpn/server/server.key
cp /etc/openvpn/easy-rsa/pki/ta.key /etc/openvpn/server/ta.key

OVPN_SRV_NET="${OVPN_NET%/*}"
OVPN_SRV_MASK="$(ipcalc -m "$OVPN_NET" | awk -F= '/NETMASK/ {print $2}')"

cat > /etc/openvpn/server/server.conf <<EOF
port $OVPN_PORT
proto ${OVPN_PROTO}-server
dev $OVPN_TUN_IF
topology subnet
local $BIND_LAN_IP

server $OVPN_SRV_NET $OVPN_SRV_MASK
ifconfig-pool-persist ipp.txt

ca /etc/openvpn/server/ca.crt
cert /etc/openvpn/server/server.crt
key /etc/openvpn/server/server.key
tls-crypt /etc/openvpn/server/ta.key

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
systemctl enable --now openvpn-server@server.service

# =========================
# [9] TẠO FILE .OVPN CHO ANDROID
# =========================
echo "Tạo file cấu hình client: /root/${CLIENT_NAME}.ovpn"
CA_B64=$(base64 -w0 /etc/openvpn/server/ca.crt)
CRT_B64=$(base64 -w0 /etc/openvpn/easy-rsa/pki/issued/${CLIENT_NAME}.crt)
KEY_B64=$(base64 -w0 /etc/openvpn/easy-rsa/pki/private/${CLIENT_NAME}.key)
TA_B64=$(base64 -w0 /etc/openvpn/server/ta.key)

cat > /root/${CLIENT_NAME}.ovpn <<EOF
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
chmod 600 /root/${CLIENT_NAME}.ovpn

# =========================
# [10] CÀI ĐẶT sing-box (binary)
# =========================
echo "Cài đặt sing-box (tun2socks)..."
if ! command -v /usr/local/bin/sing-box >/dev/null 2>&1; then
  TMP="$(mktemp -d)"; pushd "$TMP" >/dev/null
  curl -fsSL "$SINGBOX_URL" -o sing-box.tgz
  tar xzf sing-box.tgz
  SB_DIR="$(find . -maxdepth 1 -type d -name 'sing-box-*' | head -n1)"
  [[ -n "$SB_DIR" ]] || die "Giải nén sing-box thất bại."
  install -m 0755 "$SB_DIR/sing-box" /usr/local/bin/sing-box
  popd >/dev/null; rm -rf "$TMP"
fi

# =========================
# [11] CẤU HÌNH sing-box
# =========================
echo "Cấu hình sing-box..."
IN6_BLOCK=""
if [[ "$ENABLE_IPV6" == "true" ]]; then
  IN6_BLOCK=",\"inet6_address\":\"$SB_TUN6\""
fi

cat > /etc/sing-box.json <<EOF
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

chmod 600 /etc/sing-box.json

# =========================
# [12] SYSTEMD: sing-box
# =========================
echo "Tạo service sing-box..."
cat > /etc/systemd/system/sing-box.service <<'EOF'
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
systemctl daemon-reload
systemctl enable --now sing-box

# =========================
# [13] POLICY ROUTING (đẩy traffic từ tun0 vào sb-tun)
# =========================
echo "Thiết lập policy routing..."
iptables -t mangle -C PREROUTING -i $OVPN_TUN_IF -j MARK --set-mark 66 2>/dev/null || iptables -t mangle -A PREROUTING -i $OVPN_TUN_IF -j MARK --set-mark 66
ip rule add fwmark 66 table 100
ip route add default dev sb-tun table 100

# =========================
# [14] SYSTEMD: Route giữ sau reboot
# =========================
cat > /etc/systemd/system/ovpn-socks-routing.service <<'EOF'
[Unit]
Description=Persist OpenVPN->SOCKS policy routing
After=network-online.target sing-box.service openvpn-server@server.service
Wants=network-online.target sing-box.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'ip rule add fwmark 66 table 100 || true'
ExecStart=/bin/sh -c 'ip route add default dev sb-tun table 100 || true'
ExecStart=/bin/sh -c 'iptables -t mangle -C PREROUTING -i $OVPN_TUN_IF -j MARK --set-mark 66 2>/dev/null || iptables -t mangle -A PREROUTING -i $OVPN_TUN_IF -j MARK --set-mark 66'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now ovpn-socks-routing

# =========================
# [15] KIỂM TRA NHANH
# =========================
echo "Kiểm tra trạng thái dịch vụ..."
systemctl status openvpn-server@server
systemctl status sing-box
ip a show $OVPN_TUN_IF
ip a show sb-tun
ip rule show
ip route show table 100
iptables -t mangle -S PREROUTING | grep MARK

echo "==================== HOÀN TẤT ===================="
echo "→ File cấu hình OpenVPN cho Android: /root/${CLIENT_NAME}.ovpn"
echo "→ Mọi traffic của client VPN sẽ đi qua SOCKS5: ${SOCKS_IP}:${SOCKS_PORT}"
echo "→ Kiểm thử trên Android: https://ifconfig.io | https://dnsleaktest.com | https://browserleaks.com/webrtc"
echo "=================================================="
