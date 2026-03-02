#!/bin/bash

# ==============================================================================
# SCRIPT TỰ ĐỘNG HÓA TRIỂN KHAI NHIỀU MÁY MAC + OPENWRT (A-Z)
# Tác giả: Antigravity
# ==============================================================================

set -e

# --- CẤU HÌNH ĐƯỜNG DẪN ---
BASE_DIR="/home/luka-doncic/KWRT_MANAGEMENT"
RAW_DIR="$BASE_DIR/raw_images"
RUN_DIR="$BASE_DIR/running_vms"
RAW_IMG="$RAW_DIR/kwrt_raw.qcow2"

# --- MÀU SẮC ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# --- KIỂM TRA QUYỀN & FILE ---
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Lỗi: Script này cần chạy bằng sudo (để cấu hình mạng & iptables).${NC}"
   exit 1
fi

if [[ ! -f "$RAW_IMG" ]]; then
    echo -e "${RED}Lỗi: Không tìm thấy file gốc tại $RAW_IMG${NC}"
    echo -e "${YELLOW}Vui lòng copy file kwrt_raw.qcow2 vào thư mục $RAW_DIR trước.${NC}"
    exit 1
fi

# --- HÀM LẤY CÁC DẢI MẠNG HIỆN TẠI CỦA HOST ---
get_host_subnets() {
    # Lấy 3 số đầu của tất cả IPv4 đang có trên máy Host
    ip -4 addr show | grep -oP '(?<=inet\s)\d+\.\d+\.\d+' | sort -u
}

# --- HÀM TÌM DẢI IP LAN TRỐNG ---
find_free_subnet() {
    local host_nets=$(get_host_subnets)
    for x in $(seq 10 250); do
        local prefix="10.$x.0"
        local subnet="$prefix.0/24"
        
        # Nếu dải 10.x.0 này đã có trên Host thì bỏ qua để tránh mất kết nối
        if echo "$host_nets" | grep -q "^$prefix$"; then
            continue
        fi
        
        if ! ip route | grep -q "$subnet" && ! docker network ls | grep -q "$prefix.0"; then
            echo "$x"
            return 0
        fi
    done
    return 1
}

# --- HÀM TÌM IP WAN TRỐNG ---
find_free_wan_ip() {
    for i in $(seq 10 250); do
        local ip="172.30.0.$i"
        if ! ping -c 1 -W 1 $ip >/dev/null 2>&1; then
            echo "$ip"
            return 0
        fi
    done
}

# --- GIAO DIỆN CHỌN ---
echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}   HỆ THỐNG TRIỂN KHAI TỰ ĐỘNG MAC + OPENWRT (PRO)  ${NC}"
echo -e "${BLUE}====================================================${NC}"

echo -e "\n${YELLOW}1. Chọn phiên bản macOS:${NC}"
echo "1) Sequoia"
echo "2) Tahoe"
echo "3) Sonoma"
read -p "Lựa chọn (1-3): " OS_CHOICE

case $OS_CHOICE in
    1) OS_NAME="sequoia" ;;
    2) OS_NAME="tahoe" ;;
    3) OS_NAME="sonoma" ;;
    *) echo "Không hợp lệ"; exit 1 ;;
esac

read -p "2. Số lượng máy muốn tạo: " COUNT
if [[ ! $COUNT =~ ^[0-9]+$ ]]; then echo "Số lượng không hợp lệ"; exit 1; fi

# --- BẮT ĐẦU TRIỂN KHAI ---
for (( i=1; i<=$COUNT; i++ )); do
    TIMESTAMP=$(date +%s%N | cut -b10-14) # Random để tên không bao giờ trùng
    INST_NAME="${OS_NAME}-${TIMESTAMP}"
    
    echo -e "\n${GREEN}>>> Đang triển khai máy: $INST_NAME ($i/$COUNT)...${NC}"
    
    # 1. Tìm tài nguyên mạng
    X_VAL=$(find_free_subnet)
    LAN_SUB="10.$X_VAL.0.0/24"
    LAN_GW="10.$X_VAL.0.2"
    LAN_HOST="10.$X_VAL.0.1"
    BR_NAME="br-mac-$TIMESTAMP"
    NET_NAME="net-mac-$TIMESTAMP"
    
    WAN_IP=$(find_free_wan_ip)
    
    echo -e "   - Dải mạng LAN: $LAN_SUB"
    echo -e "   - IP WAN Router: $WAN_IP"

    # 2. Tạo mạng Docker
    docker network create --subnet "$LAN_SUB" --gateway "$LAN_GW" --opt com.docker.network.bridge.name="$BR_NAME" "$NET_NAME"
    ip addr del "$LAN_GW/24" dev "$BR_NAME" 2>/dev/null || true
    ip addr add "$LAN_HOST/24" dev "$BR_NAME" 2>/dev/null || true
    
    # 3. Quản lý File QEMU
    NEW_IMG="$RUN_DIR/kwrt-$INST_NAME.qcow2"
    cp "$RAW_IMG" "$NEW_IMG"
    
    # 4. Thêm quyền cho QEMU Bridge
    echo "allow $BR_NAME" >> /etc/qemu/bridge.conf
    
    # 5. Khởi chạy Router
    echo -e "   - Khởi chạy Router OpenWrt..."
    qemu-system-x86_64 -enable-kvm -m 512 -smp 2 \
        -drive file="$NEW_IMG",format=qcow2 \
        -netdev bridge,id=lan,br="$BR_NAME" -device virtio-net-pci,netdev=lan \
        -netdev bridge,id=wan,br=br-wan -device virtio-net-pci,netdev=wan \
        -display none -daemonize
    
    sleep 5 # Chờ QEMU tạo interface
    
    # 6. Tự động cấu hình Router qua mạng (Sử dụng IP LAN tạm thời nếu cần, 
    # nhưng ở đây ta dùng phương pháp dán config qua serial hoặc SSH)
    echo -e "   - Đang đẩy cấu hình mạng vào Router (vui lòng chờ)..."
    sleep 15 # Chờ boot xong
    
    # Dùng SSHpass để đẩy LAN/WAN config vào (Mặc định root/không pass hoặc pass 'root')
    sshpass -p 'root' ssh -o StrictHostKeyChecking=no root@10.$X_VAL.0.2 <<EOF 2>/dev/null || true
cat > /etc/config/network <<'NET'
config interface 'loopback'
        option device 'lo'
        option proto 'static'
        option ipaddr '127.0.0.1'
        option netmask '255.0.0.0'

config interface 'lan'
        option device 'br-lan'
        option proto 'static'
        option ipaddr '$LAN_GW'
        option netmask '255.255.255.0'

config interface 'wan'
        option device 'eth1'
        option proto 'static'
        option ipaddr '$WAN_IP'
        option netmask '255.255.255.0'
        option gateway '172.30.0.1'
        list dns '8.8.8.8'
NET
/etc/init.d/network restart
EOF

    # 7. Thiết lập Iptables
    iptables -t nat -I POSTROUTING 1 -s 172.30.0.0/24 -o enp4s0 -j MASQUERADE 2>/dev/null || true
    iptables -A FORWARD -s "$LAN_SUB" -o enp4s0 -j DROP 2>/dev/null || true

    # 8. Xuất lệnh chạy Mac
    echo -e "${GREEN}✔ Hoàn tất thiết lập cơ sở hạ tầng cho $INST_NAME!${NC}"
    echo -e "${BLUE}Lệnh chạy máy Mac này:${NC}"
    echo "docker run -it --name mac-$INST_NAME --network $NET_NAME --ip 10.$X_VAL.0.3 --dns $LAN_GW --device /dev/kvm -p $((50000 + TIMESTAMP % 10000)):10022 -v /tmp/.X11-unix:/tmp/.X11-unix -v mac-$INST_NAME-data:/image -e \"DISPLAY=\${DISPLAY:-:0.0}\" -e SHORTNAME=$OS_NAME sickcodes/docker-osx:latest"
done

echo -e "\n${BLUE}====================================================${NC}"
echo -e "${GREEN}TẤT CẢ CÁC MÁY ĐÃ SẴN SÀNG!${NC}"
echo -e "${BLUE}====================================================${NC}"
