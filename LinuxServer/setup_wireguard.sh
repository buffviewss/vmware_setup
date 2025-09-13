#!/bin/bash

# Dừng ngay khi gặp lỗi và ghi lại log chi tiết
set -e

LOG_FILE="/var/log/setup_wireguard.log"
echo "==================== Bắt đầu cài đặt ====================" | tee -a $LOG_FILE

# =============================
# Thông số cần thay đổi
# =============================

# Cấu hình SOCKS5 Proxy
SOCKS_PROXY_IP="YOUR_PROXY_IP"
SOCKS_PROXY_PORT="YOUR_PROXY_PORT"
SOCKS_PROXY_USER="YOUR_PROXY_USER"   # Nếu không có, để trống
SOCKS_PROXY_PASS="YOUR_PROXY_PASS"   # Nếu không có, để trống

# Cấu hình WireGuard Peer (Client/Server)
WG_PUBLIC_KEY="<peer_public_key_here>"
WG_PEER_IP="<peer_ip_here>"

# =============================
# Cài đặt và cấu hình bắt đầu
# =============================

# Cập nhật hệ thống và cài đặt các gói cần thiết
echo "Cập nhật hệ thống..." | tee -a $LOG_FILE
sudo apt update -y | tee -a $LOG_FILE
sudo apt upgrade -y | tee -a $LOG_FILE
sudo apt install -y wireguard proxychains git build-essential cmake make libssl-dev curl iptables iproute2 | tee -a $LOG_FILE

# Cài đặt sing-box
echo "Cài đặt sing-box..." | tee -a $LOG_FILE
cd /opt
git clone https://github.com/sagernet/sing-box.git | tee -a $LOG_FILE
cd sing-box
make | tee -a $LOG_FILE

# Cài đặt WireGuard
echo "Cài đặt WireGuard..." | tee -a $LOG_FILE
sudo apt install -y wireguard-tools | tee -a $LOG_FILE

# Cấu hình ProxyChains
echo "Cấu hình ProxyChains..." | tee -a $LOG_FILE
sudo sed -i "s/socks4 127.0.0.1 9050/socks5 $SOCKS_PROXY_IP $SOCKS_PROXY_PORT/" /etc/proxychains.conf | tee -a $LOG_FILE
# Nếu proxy yêu cầu user:pass, thêm:
if [ ! -z "$SOCKS_PROXY_USER" ] && [ ! -z "$SOCKS_PROXY_PASS" ]; then
  sudo sed -i "s/socks5 127.0.0.1 9050/socks5 $SOCKS_PROXY_USER:$SOCKS_PROXY_PASS@$SOCKS_PROXY_IP $SOCKS_PROXY_PORT/" /etc/proxychains.conf | tee -a $LOG_FILE
fi

# Tạo cấu hình WireGuard
echo "Tạo file cấu hình WireGuard wg0.conf..." | tee -a $LOG_FILE
cat <<EOT > /etc/wireguard/wg0.conf
[Interface]
PrivateKey = $(wg genkey)
Address = 10.7.0.2/32
ListenPort = 51820
DNS = 1.1.1.1

[Peer]
PublicKey = $WG_PUBLIC_KEY
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = $WG_PEER_IP:51820
PersistentKeepalive = 25
EOT

# Cấp quyền cho file cấu hình WireGuard
echo "Cấp quyền cho file cấu hình WireGuard..." | tee -a $LOG_FILE
sudo chmod 600 /etc/wireguard/wg0.conf | tee -a $LOG_FILE

# Cài đặt cấu hình sing-box để sử dụng tun2socks và chuyển UDP qua SOCKS5
echo "Cấu hình sing-box..." | tee -a $LOG_FILE
cat <<EOT > /etc/sing-box.json
{
  "log": { "level": "info" },
  "inbounds": [
    {
      "type": "tun",
      "interface_name": "sb-tun",
      "inet4_address": "198.18.0.1/30",
      "auto_route": false,
      "stack": "system"
    }
  ],
  "outbounds": [
    {
      "type": "socks",
      "server": "$SOCKS_PROXY_IP",
      "server_port": $SOCKS_PROXY_PORT,
      "version": "5",
      "username": "$SOCKS_PROXY_USER",
      "password": "$SOCKS_PROXY_PASS",
      "udp_over_tcp": false,
      "tag": "socks"
    },
    { "type": "direct", "tag": "direct" }
  ],
  "route": {
    "rules": [
      {
        "protocol": ["udp"],
        "ip_cidr": ["$WG_PEER_IP/32"],
        "port": [51820],
        "outbound": "socks"
      }
    ],
    "final": "direct"
  }
}
EOT

# Khởi động sing-box
echo "Khởi động sing-box..." | tee -a $LOG_FILE
/opt/sing-box/sing-box run -c /etc/sing-box.json & | tee -a $LOG_FILE

# Kết nối WireGuard qua ProxyChains
echo "Kết nối WireGuard qua ProxyChains..." | tee -a $LOG_FILE
sudo proxychains wg-quick up wg0 | tee -a $LOG_FILE

# Kiểm tra kết nối
echo "Kiểm tra kết nối WireGuard..." | tee -a $LOG_FILE
wg show | tee -a $LOG_FILE

echo "==================== Cài đặt hoàn tất ====================" | tee -a $LOG_FILE
