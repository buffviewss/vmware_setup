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



echo "8. Cài đặt Go 1.25.x và tun2socks (bản xjasonlyu), chống lỗi 404..."

set -euo pipefail

# Dọn dẹp bản cũ
pkill -f tun2socks 2>/dev/null || true
rm -f /usr/local/bin/tun2socks 2>/dev/null || true
rm -rf /tmp/tun2socks-build 2>/dev/null || true
rm -rf /usr/local/go 2>/dev/null || true

# Cài đặt Go từ Snap nếu có
if command -v snap >/dev/null 2>&1; then
  echo " - Cài Go qua snap channel 1.25/stable..."
  snap install go --classic --channel=1.25/stable || true
fi

# Nếu chưa có go hoặc Snap không cài được, tải tarball Go 1.25
if ! command -v go >/dev/null 2>&1 || ! go version 2>/dev/null | grep -q 'go1\.25'; then
  echo " - Cài Go qua tarball..."
  cd /tmp
  # Thử lần lượt các phiên bản 1.25.x để tránh lỗi 404
  for V in 1.25.5 1.25.4 1.25.3 1.25.2 1.25.1 1.25.0; do
    TGZ="go${V}.linux-amd64.tar.gz"
    URL1="https://go.dev/dl/${TGZ}"
    URL2="https://storage.googleapis.com/golang/${TGZ}"
    echo "   * Thử tải ${TGZ} ..."
    if curl -fsSLO "$URL1" || curl -fsSLO "$URL2"; then
      echo "   -> Tải thành công ${TGZ}"
      tar -C /usr/local -xzf "${TGZ}"
      break
    fi
  done
  export PATH="/usr/local/go/bin:${PATH}"
  echo 'export PATH=/usr/local/go/bin:$PATH' >/etc/profile.d/go.sh
  chmod 0644 /etc/profile.d/go.sh
fi

# Kiểm tra Go
go version
if ! go version | grep -q 'go1\.25'; then
  echo "❌ Cần Go >= 1.25 để build tun2socks. Dừng!"
  exit 1
fi

# --- Clone + build tun2socks ---
mkdir -p /tmp/tun2socks-build
cd /tmp/tun2socks-build
git clone https://github.com/xjasonlyu/tun2socks.git
REPO_DIR="/tmp/tun2socks-build/tun2socks"
cd "$REPO_DIR"

# Không cho Go tự kéo toolchain khác (đã là 1.25 rồi)
export GOTOOLCHAIN=local
export CGO_ENABLED=0

go build -trimpath -ldflags "-s -w" -o /usr/local/bin/tun2socks ./cmd/tun2socks
chmod 0755 /usr/local/bin/tun2socks

# --- Kiểm tra hậu build ---
T2S="/usr/local/bin/tun2socks"
if [ ! -x "$T2S" ]; then
  echo "❌ Không thấy $T2S hoặc không thực thi được."; exit 1
fi
if ! "$T2S" -h >/tmp/t2s_help.txt 2>&1; then
  echo "❌ Chạy '$T2S -h' lỗi:"; cat /tmp/t2s_help.txt || true; exit 1
fi
grep -q -- "-device" /tmp/t2s_help.txt || { echo "❌ Sai bản tun2socks: thiếu -device"; exit 1; }
grep -q -- "-proxy"  /tmp/t2s_help.txt || { echo "❌ Sai bản tun2socks: thiếu -proxy";  exit 1; }
echo "✅ tun2socks đã build OK tại: $T2S"





echo "10. Kích hoạt WireGuard (wg-quick up wg0)..."
wg-quick down wg0 2>/dev/null || true
wg-quick up wg0

# Kiểm tra interface wg0 đã lên
if ! ip link show wg0 &>/dev/null; then
  echo "WireGuard chưa khởi động thành công!"
  exit 1
fi

echo "11. Khởi động tun2socks..."

# Bảo đảm module TUN và bảng định tuyến riêng (ID 100)
modprobe tun || true
if ! grep -qE '^[[:space:]]*100[[:space:]]+wgproxy$' /etc/iproute2/rt_tables; then
  echo "100 wgproxy" >> /etc/iproute2/rt_tables
fi

# Policy routing: chỉ đẩy lưu lượng TỪ mạng WG vào tun0 (không đổi default route toàn máy)
WG_SUBNET="10.0.0.0/24"        # khớp với WG_IPV4=10.0.0.1/24
TABLE_ID=100
ip rule del from ${WG_SUBNET} table ${TABLE_ID} 2>/dev/null || true
ip -4 route flush table ${TABLE_ID} 2>/dev/null || true
ip rule add from ${WG_SUBNET} lookup ${TABLE_ID} priority 100
ip -4 route add default dev tun0 table ${TABLE_ID}

# Đảm bảo tuyến tới SOCKS đi thẳng qua gateway thật của WAN (tránh vòng qua tun0)
GATEWAY=$(ip route | awk '/^default/ && /dev '"$WAN_INTERFACE"'/ {print $3; exit}')
if [ -z "$GATEWAY" ]; then
  echo "Không tìm thấy default gateway cho ${WAN_INTERFACE}"; exit 1
fi
ip route replace ${SOCKS_SERVER} via ${GATEWAY} dev ${WAN_INTERFACE}

# Khởi chạy tun2socks (bản xjasonlyu) với đường dẫn tuyệt đối để tránh đụng PATH cũ
pkill -f '/usr/local/bin/tun2socks' 2>/dev/null || true
rm -f /var/log/tun2socks.log 2>/dev/null || true

# Host giữ tun0: 198.18.0.1/30; tun2socks dùng cùng device qua -device, không cần set tunAddr ở đây
nohup /usr/local/bin/tun2socks \
  -loglevel debug \
  -device "tun://tun0" \
  -proxy  "socks5://${PROXY_SOCKS_SERVER}" \
  -interface "${WG_INTERFACE}" \
  > /var/log/tun2socks.log 2>&1 &

sleep 2
if ! pgrep -f '/usr/local/bin/tun2socks' >/dev/null; then
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
