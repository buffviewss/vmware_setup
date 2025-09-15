#!/usr/bin/env bash
# ==========================================================
# WireGuard over SOCKS5 via sing-box (tun2socks) – Auto Setup
# Tested on Ubuntu Server 20.04/22.04/24.04 (VMware ESXi OK)
# ==========================================================
set -Eeuo pipefail

# ---------- [1] THÔNG SỐ CẦN SỬA ----------
# SOCKS5 proxy (hỗ trợ user/pass; để rỗng nếu không dùng auth)
SOCKS_IP="1.2.3.4"
SOCKS_PORT="1080"
SOCKS_USER="username"        # "" nếu không cần
SOCKS_PASS="password"        # "" nếu không cần
SOCKS_UDP_OVER_TCP="true"    # "true" nếu proxy KHÔNG hỗ trợ UDP ASSOCIATE

# WireGuard (client) -> kết nối tới server WireGuard bên ngoài
WG_ENDPOINT_IP="203.0.113.10"    # IP public của server WG
WG_ENDPOINT_PORT="51820"         # cổng WG trên server
WG_SERVER_PUBLIC_KEY="REPLACE_ME_SERVER_PUBKEY"

# Địa chỉ WG của client (subnet tùy bạn)
WG_CLIENT_ADDRESS="10.7.0.2/32"
WG_DNS="1.1.1.1"
WG_ALLOWED_IPS="0.0.0.0/0, ::/0"
WG_KEEPALIVE="25"

# sing-box binary (chọn phiên bản/kiến trúc phù hợp)
SINGBOX_VERSION="1.8.13"
SINGBOX_ARCH="amd64" # amd64|arm64|386...
SINGBOX_URL="https://github.com/SagerNet/sing-box/releases/download/v${SINGBOX_VERSION}/sing-box-${SINGBOX_VERSION}-linux-${SINGBOX_ARCH}.tar.gz"

# File/đường dẫn
LOG_FILE="/var/log/setup_wireguard.log"
WG_CONF="/etc/wireguard/wg0.conf"
SB_CONF="/etc/sing-box.json"
SB_BIN="/usr/local/bin/sing-box"
SB_SVC="/etc/systemd/system/sing-box.service"

# ---------- [2] HÀM TIỆN ÍCH ----------
red()  { printf "\e[31m%s\e[0m\n" "$*"; }
grn()  { printf "\e[32m%s\e[0m\n" "$*"; }
ylw()  { printf "\e[33m%s\e[0m\n" "$*"; }
log()  { echo "[$(date +'%F %T')] $*" | tee -a "$LOG_FILE"; }
die()  { red "LỖI: $*"; echo "Xem log: $LOG_FILE"; exit 1; }
trap 'die "Dòng lỗi: $BASH_SOURCE:$LINENO (lệnh: $BASH_COMMAND)"' ERR

require_root() {
  if [[ $EUID -ne 0 ]]; then
    die "Hãy chạy script bằng sudo/root."
  fi
}
cmd() { log "+ $*"; eval "$@" | tee -a "$LOG_FILE"; }

# ---------- [3] TIỀN ĐỀ ----------
require_root
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"
grn "================ BẮT ĐẦU CÀI ĐẶT ================"
log "VMware ESXi guest: OK. Ubuntu detected: $(lsb_release -ds || true)"

# Kiểm tra biến bắt buộc
[[ -n "$WG_SERVER_PUBLIC_KEY" && "$WG_SERVER_PUBLIC_KEY" != "REPLACE_ME_SERVER_PUBKEY" ]] || \
  die "Chưa điền WG_SERVER_PUBLIC_KEY."
[[ -n "$WG_ENDPOINT_IP" ]] || die "Chưa điền WG_ENDPOINT_IP."

# ---------- [4] CÀI GÓI HỆ THỐNG ----------
export DEBIAN_FRONTEND=noninteractive
cmd "apt-get update -y"
cmd "apt-get install -y curl tar iproute2 iptables wireguard-tools"
# proxychains tùy chọn (hữu ích để test HTTP qua SOCKS)
cmd "apt-get install -y proxychains4 || apt-get install -y proxychains || true"

# ---------- [5] TẢI & CÀI ĐẶT sing-box (binary) ----------
TMP_DIR="$(mktemp -d)"
pushd "$TMP_DIR" >/dev/null
log "Tải sing-box: $SINGBOX_URL"
cmd "curl -fsSL '$SINGBOX_URL' -o sing-box.tgz"
cmd "tar xzf sing-box.tgz"
SB_DIR="$(find . -maxdepth 1 -type d -name 'sing-box-*' | head -n1)"
[[ -n "$SB_DIR" ]] || die "Giải nén sing-box thất bại."
cmd "install -m 0755 '$SB_DIR/sing-box' '$SB_BIN'"
popd >/dev/null
rm -rf "$TMP_DIR"
cmd "$SB_BIN version"

# ---------- [6] TẠO CẤU HÌNH WireGuard (client) ----------
log "Tạo/ghi $WG_CONF"
mkdir -p /etc/wireguard
# Tạo private key client nếu chưa có
if ! [[ -f /etc/wireguard/client.key ]]; then
  umask 077
  cmd "wg genkey > /etc/wireguard/client.key"
fi
WG_CLIENT_PRIVKEY="$(cat /etc/wireguard/client.key)"
cat > "$WG_CONF" <<EOF
[Interface]
PrivateKey = $WG_CLIENT_PRIVKEY
Address = $WG_CLIENT_ADDRESS
DNS = $WG_DNS

[Peer]
PublicKey = $WG_SERVER_PUBLIC_KEY
AllowedIPs = $WG_ALLOWED_IPS
Endpoint = $WG_ENDPOINT_IP:$WG_ENDPOINT_PORT
PersistentKeepalive = $WG_KEEPALIVE
EOF
cmd "chmod 600 '$WG_CONF'"
log "Xem nhanh wg0.conf:"
cat "$WG_CONF" | sed 's/PrivateKey = .*/PrivateKey = (hidden)/' | tee -a "$LOG_FILE"

# ---------- [7] CẤU HÌNH sing-box (tun2socks) ----------
log "Tạo/ghi $SB_CONF"
cat > "$SB_CONF" <<EOF
{
  "log": { "level": "info" },
  "inbounds": [
    {
      "type": "tun",
      "interface_name": "sb-tun",
      "inet4_address": "198.18.0.1/30",
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
        "protocol": [ "udp" ],
        "ip_cidr": [ "$WG_ENDPOINT_IP/32" ],
        "port": [ "$WG_ENDPOINT_PORT" ],
        "outbound": "socks"
      }
    ],
    "final": "direct"
  }
}
EOF
cmd "chmod 600 '$SB_CONF'"

# ---------- [8] SYSTEMD SERVICE cho sing-box ----------
log "Tạo service $SB_SVC"
cat > "$SB_SVC" <<'EOF'
[Unit]
Description=sing-box (tun2socks for WireGuard over SOCKS5)
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

# ---------- [9] POLICY ROUTING: ép chỉ gói UDP -> WG_SERVER đi vào sb-tun ----------
log "Thiết lập policy routing cho sb-tun"
# Bảng 100: default qua sb-tun
cmd "ip rule add fwmark 1 table 100 || true"
cmd "ip route add default dev sb-tun table 100 || true"
# Mark gói đi tới WG_ENDPOINT_IP:WG_ENDPOINT_PORT/udp
cmd "iptables -t mangle -C OUTPUT -p udp -d $WG_ENDPOINT_IP --dport $WG_ENDPOINT_PORT -j MARK --set-mark 1 2>/dev/null || iptables -t mangle -A OUTPUT -p udp -d $WG_ENDPOINT_IP --dport $WG_ENDPOINT_PORT -j MARK --set-mark 1"

# ---------- [10] KHỞI CHẠY WireGuard ----------
log "Khởi chạy WireGuard (client)"
cmd "wg-quick down wg0 2>/dev/null || true"
cmd "wg-quick up wg0"

# ---------- [11] KIỂM TRA ----------
grn "=========== TRẠNG THÁI ==========="
cmd "systemctl --no-pager status sing-box | sed -n '1,25p'"
cmd "ip a show sb-tun || true"
cmd "wg show"
ylw "Nếu 'latest handshake' hiển thị và TX/RX tăng -> thành công."
grn "=============== HOÀN TẤT ==============="
echo "Log đầy đủ: $LOG_FILE"
