#!/bin/bash

# Cập nhật hệ thống và cài đặt các gói cần thiết
echo "Cập nhật hệ thống..."
sudo apt update -y
sudo apt upgrade -y
sudo apt install -y wireguard proxychains git build-essential cmake make libssl-dev curl iptables iproute2

# Cài đặt sing-box
echo "Cài đặt sing-box..."
cd /opt
git clone https://github.com/sagernet/sing-box.git
cd sing-box
make

# Cài đặt WireGuard
echo "Cài đặt WireGuard..."
sudo apt install -y wireguard-tools

# Cấu hình ProxyChains
echo "Cấu hình ProxyChains..."
sudo sed -i 's/socks4 127.0.0.1 9050/socks5 YOUR_PROXY_IP YOUR_PROXY_PORT/' /etc/proxychains.conf
# Nếu proxy yêu cầu user:pass, thêm:
# sudo sed -i 's/socks5 127.0.0.1 9050/socks5 user:pass@YOUR_PROXY_IP YOUR_PROXY_PORT/' /etc/proxychains.conf

# Tạo cấu hình WireGuard
echo "Tạo file cấu hình WireGuard wg0.conf..."
cat <<EOT > /etc/wireguard/wg0.conf
[Interface]
PrivateKey = $(wg genkey)
Address = 10.7.0.2/32
ListenPort = 51820
DNS = 1.1.1.1

[Peer]
PublicKey = <peer_public_key_here>
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = <peer_ip_here>:51820
PersistentKeepalive = 25
EOT

# Cấp quyền cho file cấu hình WireGuard
sudo chmod 600 /etc/wireguard/wg0.conf

# Cài đặt cấu hình sing-box để sử dụng tun2socks và chuyển UDP qua SOCKS5
echo "Cấu hình sing-box..."
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
      "server": "YOUR_PROXY_IP",
      "server_port": YOUR_PROXY_PORT,
      "version": "5",
      "username": "YOUR_PROXY_USER",
      "password": "YOUR_PROXY_PASS",
      "udp_over_tcp": false,
      "tag": "socks"
    },
    { "type": "direct", "tag": "direct" }
  ],
  "route": {
    "rules": [
      {
        "protocol": ["udp"],
        "ip_cidr": ["<wireguard_server_ip>/32"],
        "port": [51820],
        "outbound": "socks"
      }
    ],
    "final": "direct"
  }
}
EOT

# Khởi động sing-box
echo "Khởi động sing-box..."
/opt/sing-box/sing-box run -c /etc/sing-box.json &

# Kết nối WireGuard qua ProxyChains
echo "Kết nối WireGuard qua ProxyChains..."
sudo proxychains wg-quick up wg0

# Kiểm tra kết nối
wg show
