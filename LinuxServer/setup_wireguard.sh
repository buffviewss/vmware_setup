#!/bin/bash

set -euo pipefail

# --- Kiểm tra quyền root ---
if [ "$EUID" -ne 0 ]; then
  echo "Vui lòng chạy script với quyền root."
  exit 1
fi

# --- Tự động phát hiện cổng WAN và LAN ---
WAN_INTERFACE=""
LAN_INTERFACE=""

# Lấy danh sách interface vật lý (bỏ lo)
for iface in $(ls /sys/class/net | grep -v lo); do
  # Nếu interface này là default gateway => WAN
  if ip route | grep -q "^default.*dev $iface"; then
    WAN_INTERFACE="$iface"
    continue
  fi
  # Nếu chưa có WAN, thử ping Internet từ interface này
  if [ -z "$WAN_INTERFACE" ] && ping -I $iface -c 1 -W 1 8.8.8.8 &>/dev/null; then
    WAN_INTERFACE="$iface"
    continue
  fi
  # Nếu chưa có LAN, gán làm LAN (ưu tiên interface chưa có IP hoặc DOWN)
  if [ -z "$LAN_INTERFACE" ]; then
    LAN_INTERFACE="$iface"
  fi
done

if [ -z "$WAN_INTERFACE" ] || [ -z "$LAN_INTERFACE" ]; then
  echo "Không phát hiện được đủ 2 interface mạng (WAN/LAN). Hãy kiểm tra lại cấu hình mạng."
  exit 1
fi

echo "Đã phát hiện: WAN = $WAN_INTERFACE, LAN = $LAN_INTERFACE"

# --- Gán lại biến cấu hình ---
WG_INTERFACE="$WAN_INTERFACE"
LAN_INTERFACE="$LAN_INTERFACE"

# --- Gán IP cho LAN ---
LAN_IP="192.168.56.1/24"
echo "Gán IP $LAN_IP cho $LAN_INTERFACE..."
ip link set $LAN_INTERFACE up
ip addr flush dev $LAN_INTERFACE
ip addr add $LAN_IP dev $LAN_INTERFACE

# --- Nhập thủ công khóa nếu muốn ---
SERVER_PRIVATE_KEY="7Qw6Q4Qw6Q4Qw6Q4Qw6Q4Qw6Q4Qw6Q4Qw6Q4Qw6Qw6Q="   # Dán private key server vào đây nếu có, nếu để trống sẽ tự sinh
SERVER_PUBLIC_KEY="6Qw6Q4Qw6Q4Qw6Q4Qw6Q4Qw6Q4Qw6Q4Qw6Q4Qw6Q4Qw="    # Dán public key server vào đây nếu có, nếu để trống sẽ tự sinh
CLIENT_PRIVATE_KEY="9Qw6Q4Qw6Q4Qw6Q4Qw6Q4Qw6Q4Qw6Q4Qw6Q4Qw6Qw6Q="   # Dán private key client vào đây nếu có, nếu để trống sẽ tự sinh
CLIENT_PUBLIC_KEY="8Qw6Q4Qw6Q4Qw6Q4Qw6Q4Qw6Q4Qw6Q4Qw6Q4Qw6Q4Qw="    # Dán public key client vào đây nếu có, nếu để trống sẽ tự sinh

# --- Biến cấu hình (chỉnh sửa tùy môi trường) ---
WG_IPV4="10.0.0.1/24"
WG_PORT=51820
WG_CLIENT_IPV4="10.0.0.2"
SOCKS_SERVER="217.180.44.121"
SOCKS_PORT=6012
SOCKS_USER="eyvizq4mf8n3"
SOCKS_PASS="6jo0C8dNSfrtkclt"
PROXY_SOCKS_SERVER="${SOCKS_USER}:${SOCKS_PASS}@${SOCKS_SERVER}:${SOCKS_PORT}"

echo "1. Cài đặt WireGuard và các gói cần thiết..."
apt update
apt install -y wireguard iproute2 iptables

echo "2. Cấu hình IP tĩnh cho card LAN ($LAN_INTERFACE)..."
# Đã gán ở trên

echo "3. Tạo thư mục cấu hình WireGuard (/etc/wireguard)..."
mkdir -p /etc/wireguard
chmod 700 /etc/wireguard
cd /etc/wireguard

# --- Tạo hoặc nhập khóa cho server ---
if [ -n "$SERVER_PRIVATE_KEY" ] && [ -n "$SERVER_PUBLIC_KEY" ]; then
  echo "$SERVER_PRIVATE_KEY" > server_private.key
  echo "$SERVER_PUBLIC_KEY" > server_public.key
  chmod 600 server_private.key
  echo "Đã nhập khóa server thủ công."
elif [ ! -f server_private.key ]; then
  echo "Đang tạo khóa riêng WireGuard cho server..."
  wg genkey | tee server_private.key | wg pubkey > server_public.key
  chmod 600 server_private.key
  echo "Khóa WireGuard server đã được sinh: server_private.key, server_public.key"
fi

# --- Tạo hoặc nhập khóa cho client ---
if [ -n "$CLIENT_PRIVATE_KEY" ] && [ -n "$CLIENT_PUBLIC_KEY" ]; then
  echo "$CLIENT_PRIVATE_KEY" > client_private.key
  echo "$CLIENT_PUBLIC_KEY" > client_public.key
  chmod 600 client_private.key
  echo "Đã nhập khóa client thủ công."
elif [ ! -f client_private.key ]; then
  echo "Đang tạo khóa riêng WireGuard cho client..."
  wg genkey | tee client_private.key | wg pubkey > client_public.key
  chmod 600 client_private.key
  echo "Khóa WireGuard client đã được sinh: client_private.key, client_public.key"
fi

echo "4. Tạo file cấu hình wg0.conf..."
cat > wg0.conf <<EOF
[Interface]
Address = ${WG_IPV4}
ListenPort = ${WG_PORT}
PrivateKey = $(cat server_private.key)

[Peer]
AllowedIPs = ${WG_CLIENT_IPV4}/32
PublicKey = $(cat client_public.key)
EOF
echo "Đã tạo /etc/wireguard/wg0.conf. Khóa công khai của client đã được thêm vào."

echo "5. Kích hoạt IP forwarding..."
sysctl -w net.ipv4.ip_forward=1
sed -i 's/^#*net.ipv4.ip_forward=.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf

echo "6. Tắt rp_filter trên interface chính để tun2socks hoạt động..."
sysctl -w net.ipv4.conf.all.rp_filter=0
sysctl -w net.ipv4.conf.${WG_INTERFACE}.rp_filter=0

echo "7. Thiết lập thiết bị TUN và định tuyến cho tun2socks..."
ip tuntap del mode tun dev tun0 2>/dev/null
ip tuntap add mode tun dev tun0
ip addr add 198.18.0.1/30 dev tun0
ip link set up dev tun0

# Lấy gateway mặc định gốc
GATEWAY=$(ip route | awk '/^default/ {print $3}')
# Thêm route cho SOCKS proxy qua gateway gốc (tránh lặp vòng)
if [ -n "${PROXY_SOCKS_SERVER}" ] && [ "${PROXY_SOCKS_SERVER}" != "127.0.0.1" ]; then
  echo " - Đường dẫn riêng cho proxy SOCKS5 ${PROXY_SOCKS_SERVER} qua gateway gốc..."
  ip route del ${SOCKS_SERVER} 2>/dev/null || true
  ip route add ${SOCKS_SERVER} via ${GATEWAY} dev ${WG_INTERFACE}
fi

# Đưa toàn bộ lưu lượng khác qua tun0
echo " - Đặt tun0 làm gateway mặc định tạm thời..."
# ip route add default via 198.18.0.1 dev tun0 metric 1

echo "8. Kiểm tra và cài đặt tun2socks nếu cần..."
if ! command -v tun2socks &>/dev/null; then
  echo "tun2socks chưa được cài, đang tiến hành cài đặt..."
  apt update
  apt install -y golang git
  export GOPATH=$HOME/go
  export PATH=$PATH:$GOPATH/bin
  if [ ! -d "$HOME/go/src/github.com/eycorsican/go-tun2socks" ]; then
    mkdir -p $HOME/go/src/github.com/eycorsican
    cd $HOME/go/src/github.com/eycorsican
    git clone https://github.com/eycorsican/go-tun2socks.git
  fi
  cd $HOME/go/src/github.com/eycorsican/go-tun2socks/cmd/tun2socks
  go build
  sudo cp tun2socks /usr/local/bin/
  cd ~
fi

# Sau khi build tun2socks, kiểm tra lỗi build
if [ ! -f $HOME/go/src/github.com/eycorsican/go-tun2socks/cmd/tun2socks/tun2socks ]; then
  echo "Build tun2socks thất bại! Kiểm tra lại Golang."
  exit 1
fi

echo "10. Kích hoạt WireGuard (wg-quick up wg0)..."
wg-quick up wg0

# Kiểm tra interface wg0 đã lên
if ! ip link show wg0 &>/dev/null; then
  echo "WireGuard chưa khởi động thành công!"
  exit 1
fi

echo "11. Khởi động tun2socks..."
nohup tun2socks -device tun://tun0 -proxy socks5://${PROXY_SOCKS_SERVER} -interface ${WG_INTERFACE} > /var/log/tun2socks.log 2>&1 &
sleep 2
if ! pgrep -f tun2socks >/dev/null; then
  echo "tun2socks không chạy! Kiểm tra lại cài đặt hoặc log."
  exit 1
fi
echo "Đã khởi động tun2socks (log tại /var/log/tun2socks.log)."

echo "12. Xóa rule iptables cũ (nếu có)..."
iptables -D FORWARD -i wg0 -o tun0 -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -i tun0 -o wg0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
iptables -t nat -D POSTROUTING -o tun0 -j MASQUERADE 2>/dev/null || true

echo "13. Cấu hình iptables cho WG và TUN..."
iptables -A FORWARD -i wg0 -o tun0 -j ACCEPT
iptables -A FORWARD -i tun0 -o wg0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE

echo "Hoàn tất. WireGuard và tun2socks đã được cấu hình."

echo "14. Cấu hình trên Client Android (WireGuard App):"
echo "--------------------------------------------------------------------"
echo "[Interface]"
echo "PrivateKey = $(cat client_private.key)"
echo "Address = 10.0.0.2/32"
echo ""
echo "[Peer]"
echo "PublicKey = $(cat server_public.key)"
echo "Endpoint = ${LAN_IP%%/*}:51820"
echo "AllowedIPs = 0.0.0.0/0"
echo "--------------------------------------------------------------------"
echo "Lưu ý: Thay ${LAN_IP%%/*} bằng IP LAN của server nếu khác."
