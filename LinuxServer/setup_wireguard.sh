#!/bin/bash

# --- Biến cấu hình (chỉnh sửa tùy môi trường) ---
WG_IPV4="10.0.0.1/24"           # Địa chỉ của wg0 (server)
WG_PORT=51820                    # Cổng lắng nghe WireGuard
WG_INTERFACE="ens34"             # Interface ra Internet (WAN, ens33)
WG_CLIENT_IPV4="10.0.0.2"        # IP của client Android (peer)
SOCKS_SERVER="217.180.44.121"    # Địa chỉ proxy SOCKS5 (IPv4 hoặc hostname)
SOCKS_PORT=6012                  # Cổng proxy SOCKS5
SOCKS_USER="eyvizq4mf8n3"        # Tên người dùng proxy SOCKS5
SOCKS_PASS="6jo0C8dNSfrtkclt"    # Mật khẩu người dùng proxy SOCKS5
PROXY_SOCKS_SERVER="${SOCKS_USER}:${SOCKS_PASS}@${SOCKS_SERVER}:${SOCKS_PORT}"  # Tên biến dùng khi thêm route

# --- Log các bước ---
echo "1. Cài đặt WireGuard và các gói cần thiết..."
apt update
apt install -y wireguard iproute2 iptables    # apt-get cần cập nhật

echo "2. Tạo thư mục cấu hình WireGuard (/etc/wireguard)..."
mkdir -p /etc/wireguard
chmod 700 /etc/wireguard

cd /etc/wireguard

# --- Tạo khóa cho server và client (nếu chưa có) ---
# Tạo khóa riêng và công khai cho server
if [ ! -f server_private.key ]; then
  echo "Đang tạo khóa riêng WireGuard cho server..."
  wg genkey | tee server_private.key | wg pubkey > server_public.key
  chmod 600 server_private.key
  echo "Khóa WireGuard server đã được sinh: server_private.key, server_public.key"
fi

# Tạo khóa riêng và công khai cho client
if [ ! -f client_private.key ]; then
  echo "Đang tạo khóa riêng WireGuard cho client..."
  wg genkey | tee client_private.key | wg pubkey > client_public.key
  chmod 600 client_private.key
  echo "Khóa WireGuard client đã được sinh: client_private.key, client_public.key"
fi

# --- Tạo cấu hình wg0.conf ---
echo "3. Tạo file cấu hình wg0.conf..."
cat > wg0.conf <<EOF
[Interface]
Address = ${WG_IPV4}
ListenPort = ${WG_PORT}
PrivateKey = $(cat server_private.key)
# Enable forwarding/Giải pháp NAT sẽ cài ngoài

[Peer]
# Cấu hình cho client Android
AllowedIPs = ${WG_CLIENT_IPV4}/32
PublicKey = $(cat client_public.key)
EOF
echo "Đã tạo /etc/wireguard/wg0.conf. Khóa công khai của client đã được thêm vào."

# --- Kích hoạt IP forwarding ---
echo "4. Kích hoạt IP forwarding..."
# Bật IP forwarding
sysctl -w net.ipv4.ip_forward=1

echo "5. Tắt rp_filter trên interface chính để tun2socks hoạt động..."
sysctl -w net.ipv4.conf.all.rp_filter=0
sysctl -w net.ipv4.conf.${WG_INTERFACE}.rp_filter=0

echo "6. Thiết lập thiết bị TUN và định tuyến cho tun2socks..."
# Tạo thiết bị TUN
ip tuntap add mode tun dev tun0
ip addr add 198.18.0.1/30 dev tun0
ip link set up dev tun0

# Lấy gateway mặc định gốc
GATEWAY=$(ip route | awk '/^default/ {print $3}')
# Thêm route cho SOCKS proxy qua gateway gốc (tránh lặp vòng)
if [ -n "${PROXY_SOCKS_SERVER}" ] && [ "${PROXY_SOCKS_SERVER}" != "127.0.0.1" ]; then
  echo " - Đường dẫn riêng cho proxy SOCKS5 ${PROXY_SOCKS_SERVER} qua gateway gốc..."
  ip route add ${SOCKS_SERVER} via ${GATEWAY} dev ${WG_INTERFACE}
fi
# Đưa toàn bộ lưu lượng khác qua tun0
echo " - Đặt tun0 làm gateway mặc định tạm thời..."
ip route add default via 198.18.0.1 dev tun0 metric 1
ip route add default via ${GATEWAY} dev ens34 metric 10   # Chỉnh lại để sử dụng ens34 cho LAN

echo "7. Chạy tun2socks để chuyển hướng qua proxy SOCKS5..."
# Chạy tun2socks (xjasonlyu/tun2socks)
# Phải đảm bảo đã cài tun2socks sẵn (có thể tải từ GitHub hoặc từ bản phát hành)
nohup tun2socks -device tun://tun0 -proxy socks5://${PROXY_SOCKS_SERVER} -interface ${WG_INTERFACE} > /var/log/tun2socks.log 2>&1 &
echo "Đã khởi động tun2socks (log tại /var/log/tun2socks.log)."

echo "8. Cấu hình iptables cho WG và TUN..."
# Cho phép forward giữa wg0 và tun0
iptables -A FORWARD -i wg0 -o tun0 -j ACCEPT
iptables -A FORWARD -i tun0 -o wg0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
# NAT lưu lượng ra tun0
iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE

echo "9. Kích hoạt WireGuard (wg-quick up wg0)..."
wg-quick up wg0

echo "Hoàn tất. WireGuard và tun2socks đã được cấu hình."

# --- Thông báo cho người dùng cấu hình trên client ---
echo "10. Cấu hình trên Client Android (WireGuard App):"
echo "--------------------------------------------------------------------"
echo "[Interface]"
echo "PrivateKey = $(cat client_private.key)"
echo "Address = 10.0.0.2/32"
echo ""
echo "[Peer]"
echo "PublicKey = $(cat server_public.key)"
echo "Endpoint = <server_ip>:51820"
echo "AllowedIPs = 0.0.0.0/0"
echo "--------------------------------------------------------------------"
echo "Lưu ý: Thay <server_ip> bằng IP công cộng của server WireGuard."
