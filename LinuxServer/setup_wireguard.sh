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

# Lấy gateway mặc định gốc của WAN_INTERFACE
GATEWAY=$(ip route | awk '/^default/ && /dev '"$WAN_INTERFACE"'/ {print $3; exit}')
# Thêm route cho SOCKS proxy qua gateway gốc (tránh lặp vòng)
if [ -n "${PROXY_SOCKS_SERVER}" ] && [ "${PROXY_SOCKS_SERVER}" != "127.0.0.1" ]; then
  echo " - Đường dẫn riêng cho proxy SOCKS5 ${PROXY_SOCKS_SERVER} qua gateway gốc..."
  ip route del ${SOCKS_SERVER} 2>/dev/null || true
  ip route add ${SOCKS_SERVER} via ${GATEWAY} dev ${WAN_INTERFACE}
fi

# Đưa toàn bộ lưu lượng khác qua tun0
echo " - Đặt tun0 làm gateway mặc định tạm thời..."
# ip route add default via 198.18.0.1 dev tun0 metric 1



echo "8. Cài đặt Go 1.25.x và tun2socks (v2) bằng go install..."

set -euo pipefail

# 1) Chuẩn bị Go 1.25.x
apt update
apt install -y curl ca-certificates git build-essential

# Gỡ Go cũ, nếu có
rm -rf /usr/local/go 2>/dev/null || true

cd /tmp
# Tải Go chính thức từ go.dev hoặc storage.googleapis
TGZ="go1.25.1.linux-amd64.tar.gz"
URL1="https://go.dev/dl/${TGZ}"
URL2="https://storage.googleapis.com/golang/${TGZ}"

echo " - Tải Go từ URL1: $URL1"
if ! curl -fsSLO "$URL1"; then
  echo "   - Không tải được từ $URL1, thử URL2."
  curl -fsSLO "$URL2" || { echo "❌ Không tải được Go"; exit 1; }
fi

# Giải nén Go vào thư mục /usr/local
tar -C /usr/local -xzf "${TGZ}"

# Cài đặt PATH cho Go
export PATH="/usr/local/go/bin:${PATH}"
echo 'export PATH=/usr/local/go/bin:$PATH' >/etc/profile.d/go.sh
chmod 0644 /etc/profile.d/go.sh

# Kiểm tra Go đã cài thành công
go version | grep -q 'go1\.25' || { echo "❌ Cần Go >= 1.25"; exit 1; }

# 2) Dọn cũ và clone lại repo
sudo pkill -f tun2socks 2>/dev/null || true
sudo rm -f /usr/local/bin/tun2socks 2>/dev/null || true
rm -rf /tmp/tun2socks-build
mkdir -p /tmp/tun2socks-build
cd /tmp/tun2socks-build
git clone https://github.com/xjasonlyu/tun2socks.git
REPO="/tmp/tun2socks-build/tun2socks"

# 3) Kiểm tra thư mục cmd
echo "Danh sách thư mục trong repo:"
ls -la "$REPO/cmd"

# Kiểm tra thư mục chính có sẵn
if [ ! -d "$REPO/cmd/tun2socks" ]; then
  echo "❌ Không tìm thấy thư mục cmd/tun2socks trong repo!"
  exit 1
fi

# 4) Build ra /usr/local/bin/tun2socks
export GOTOOLCHAIN=local
export CGO_ENABLED=0
go build -C "$REPO/cmd/tun2socks" -trimpath -ldflags "-s -w" -o /usr/local/bin/tun2socks

# 5) Kiểm tra sau build
T2S="/usr/local/bin/tun2socks"
if [ ! -x "$T2S" ]; then
  echo "❌ Không thấy $T2S hoặc không thực thi được."; exit 1
fi
if ! "$T2S" -h >/tmp/t2s_help.txt 2>&1; then
  echo "❌ Chạy '$T2S -h' lỗi:"; cat /tmp/t2s_help.txt; exit 1
fi
grep -q -- "-device" /tmp/t2s_help.txt || { echo "❌ thiếu flag -device (sai bản)"; exit 1; }
grep -q -- "-proxy"  /tmp/t2s_help.txt || { echo "❌ thiếu flag -proxy (sai bản)";  exit 1; }

echo "✅ ĐÃ CÀI /usr/local/bin/tun2socks (v2, hỗ trợ -device/-proxy)"






echo "10. Kích hoạt WireGuard (wg-quick up wg0)..."
wg-quick down wg0 2>/dev/null || true
wg-quick up wg0

# Kiểm tra interface wg0 đã lên
if ! ip link show wg0 &>/dev/null; then
  echo "WireGuard chưa khởi động thành công!"
  exit 1
fi

echo "11. Khởi động tun2socks..."

# YÊU CẦU: đã tạo tun0 = 198.18.0.1/30, wg0 đã up
# Các biến đã có từ trên: WAN_INTERFACE, WG_INTERFACE, SOCKS_SERVER, PROXY_SOCKS_SERVER, WG_IPV4 (10.0.0.1/24)

# 11.1 Bảo đảm TUN & bảng định tuyến riêng
modprobe tun 2>/dev/null || true
if ! grep -qE '^[[:space:]]*100[[:space:]]+wgproxy$' /etc/iproute2/rt_tables; then
  echo "100 wgproxy" >> /etc/iproute2/rt_tables
fi

# 11.2 Policy routing: chỉ đẩy lưu lượng TỪ mạng WG vào tun0 (không đổi default route toàn máy)
WG_SUBNET="${WG_IPV4%/*}/24"   # suy ra 10.0.0.0/24 nếu WG_IPV4=10.0.0.1/24
TABLE_ID=100
ip rule del from ${WG_SUBNET} table ${TABLE_ID} 2>/dev/null || true
ip -4 route flush table ${TABLE_ID} 2>/dev/null || true
ip rule add from ${WG_SUBNET} lookup ${TABLE_ID} priority 100
ip -4 route add default dev tun0 table ${TABLE_ID}

# 11.3 Đảm bảo tuyến tới SOCKS đi thẳng qua gateway WAN (tránh vòng qua tun0)
GATEWAY=$(ip route | awk '/^default/ && /dev '"$WAN_INTERFACE"'/ {print $3; exit}')
if [ -z "$GATEWAY" ]; then
  echo "Không tìm thấy default gateway cho ${WAN_INTERFACE}"; exit 1
fi
ip route replace ${SOCKS_SERVER} via ${GATEWAY} dev ${WAN_INTERFACE}

# 11.4 Khởi động tun2socks (xjasonlyu/v2) với đường dẫn tuyệt đối
T2S="/usr/local/bin/tun2socks"
if ! "$T2S" -h 2>&1 | grep -q -- "-device"; then
  echo "tun2socks không đúng phiên bản (thiếu -device). Kiểm tra lại phần cài đặt (phần 8)."
  exit 1
fi

pkill -f "$T2S" 2>/dev/null || true
rm -f /var/log/tun2socks.log 2>/dev/null || true

nohup "$T2S" \
  -loglevel debug \
  -device "tun://tun0" \
  -proxy  "socks5://${PROXY_SOCKS_SERVER}" \
  -interface "${WG_INTERFACE}" \
  > /var/log/tun2socks.log 2>&1 &

sleep 2
if ! pgrep -f "$T2S" >/dev/null; then
  echo "tun2socks không chạy! In 100 dòng log cuối để chẩn đoán:"
  tail -n 100 /var/log/tun2socks.log || true
  exit 1
fi
echo "✅ Đã khởi động tun2socks (log: /var/log/tun2socks.log)."



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
