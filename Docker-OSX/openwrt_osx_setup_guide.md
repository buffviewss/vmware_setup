# Hướng dẫn thiết lập hệ thống OpenWrt (Kwrt) + Docker-OSX từ đầu

Tài liệu này giúp bạn thiết lập hệ thống từ máy mới tinh, đảm bảo mạng LAN/WAN thông suốt và không bị lỗi DNS/Loopback.

---

### 🔥 BƯỚC 1: Tạo hạ tầng mạng (Docker Network)
Chúng ta tạo các "vòng kết nối" ảo để các máy có thể cắm dây mạng vào.

```bash
# 1. Tạo mạng LAN cho Sequoia (máy Mac 10.2.0.3 -> Router 10.2.0.2)
docker network create --subnet 10.2.0.0/24 --gateway 10.2.0.2 --opt com.docker.network.bridge.name=br-lan-sequoia lan-sequoia
sudo ip addr del 10.2.0.2/24 dev br-lan-sequoia 2>/dev/null; sudo ip addr add 10.2.0.1/24 dev br-lan-sequoia

# 2. Tạo mạng LAN cho Tahoe (máy Mac 10.3.0.3 -> Router 10.3.0.2)
docker network create --subnet 10.3.0.0/24 --gateway 10.3.0.2 --opt com.docker.network.bridge.name=br-lan-tahoe lan-tahoe
sudo ip addr del 10.3.0.2/24 dev br-lan-tahoe 2>/dev/null; sudo ip addr add 10.3.0.1/24 dev br-lan-tahoe

# 3. Tạo mạng LAN cho Sonoma (máy Mac 10.1.0.3 -> Router 10.1.0.2)
docker network create --subnet 10.1.0.0/24 --gateway 10.1.0.2 --opt com.docker.network.bridge.name=br-sonoma lan-net-01
sudo ip addr del 10.1.0.2/24 dev br-sonoma 2>/dev/null; sudo ip addr add 10.1.0.1/24 dev br-sonoma

# 4. Tạo mạng WAN chung (Cấp internet cho toàn bộ router)
docker network create --subnet 172.30.0.0/24 --opt com.docker.network.bridge.name=br-wan wan-total
```

---

### 🛠 BƯỚC 2: Cấu hình Host để cho phép QEMU dùng Bridge
Mặc định Linux chặn QEMU truy cập vào bridge của Docker.

1.  **Thêm quyền cho Bridge:**
    ```bash
    sudo mkdir -p /etc/qemu
    echo "allow br-lan-sequoia" | sudo tee -a /etc/qemu/bridge.conf
    echo "allow br-lan-tahoe" | sudo tee -a /etc/qemu/bridge.conf
    echo "allow br-sonoma" | sudo tee -a /etc/qemu/bridge.conf
    echo "allow br-wan" | sudo tee -a /etc/qemu/bridge.conf
    ```

2.  **Cấp quyền thực thi cho Helper:**
    ```bash
    sudo chmod u+s /usr/lib/qemu/qemu-bridge-helper 2>/dev/null || sudo chmod u+s /usr/libexec/qemu-bridge-helper
    ```

---

### 🚀 BƯỚC 3: Khởi chạy Router OpenWrt (Kwrt)
Mở terminal mới và chạy lệnh tương ứng (đảm bảo file [.qcow2](file:///home/luka-doncic/Downloads/kwrt.qcow2) nằm đúng đường dẫn).

**Cho Sequoia:** `sudo qemu-system-x86_64 -enable-kvm -m 512 -smp 2 -drive file=/home/luka-doncic/Downloads/kwrt-sequoia.qcow2,format=qcow2 -netdev bridge,id=lan,br=br-lan-sequoia -device virtio-net-pci,netdev=lan -netdev bridge,id=wan,br=br-wan -device virtio-net-pci,netdev=wan -display none -daemonize`

**Cho Tahoe:** `sudo qemu-system-x86_64 -enable-kvm -m 512 -smp 2 -drive file=/home/luka-doncic/Downloads/Tahoe/kwrt-tahoe.qcow2,format=qcow2 -netdev bridge,id=lan,br=br-lan-tahoe -device virtio-net-pci,netdev=lan -netdev bridge,id=wan,br=br-wan -device virtio-net-pci,netdev=wan -display none -daemonize`

**Cho Sonoma:** `sudo qemu-system-x86_64 -enable-kvm -m 512 -smp 2 -drive file=/home/luka-doncic/Downloads/kwrt.qcow2,format=qcow2 -netdev bridge,id=lan,br=br-sonoma -device virtio-net-pci,netdev=lan -netdev bridge,id=wan,br=br-wan -device virtio-net-pci,netdev=wan -display none -daemonize`

---

### ⚙️ BƯỚC 4: Cấu hình nội bộ cho Router (QUAN TRỌNG)
Vào terminal của từng router (dùng `sshpass -p 'root' ssh root@10.x.0.2`) và dán cấu hình mạng. Nhớ thay đổi `ipaddr` WAN để không trùng nhau (ví dụ: `.50`, `.60`, `.70`).

**Mẫu cấu hình (Ví dụ cho Tahoe 10.3.0.2):**
```bash
cat > /etc/config/network <<'EOF'
config interface 'loopback'
        option device 'lo'
        option proto 'static'
        option ipaddr '127.0.0.1'
        option netmask '255.0.0.0'

config globals 'globals'
        option packet_steering '1'

config device
        option name 'br-lan'
        option type 'bridge'
        list ports 'eth0'

config interface 'lan'
        option device 'br-lan'
        option proto 'static'
        option ipaddr '10.3.0.2'
        option netmask '255.255.255.0'

config interface 'wan'
        option device 'eth1'
        option proto 'static'
        option ipaddr '172.30.0.60'
        option netmask '255.255.255.0'
        option gateway '172.30.0.1'
        list dns '8.8.8.8'
EOF
/etc/init.d/network restart
```

---

### 🌐 BƯỚC 5: Cấp Internet (NAT) từ máy Host
Trở lại terminal của máy Linux (Host) để chạy các lệnh NAT:

```bash
# Cấp internet cho dải WAN chung
sudo iptables -t nat -I POSTROUTING 1 -s 172.30.0.0/24 -o enp4s0 -j MASQUERADE
sudo iptables -I FORWARD 1 -s 172.30.0.0/24 -j ACCEPT

# Bảo mật: Chặn Mac đi thẳng ra ngoài không qua router
sudo iptables -A FORWARD -s 10.1.0.0/16 -o enp4s0 -j DROP
```

---

### 🍏 BƯỚC 6: Chạy macOS (Docker-OSX)
Dưới đây là 3 lệnh build máy Mac đi qua 3 router tương ứng:

#### 1. Mac-Sequoia (Qua Router 10.2.0.2)
```bash
docker run -it \
  --name mac-sequoia \
  --hostname mac-sequoia \
  --network lan-sequoia \
  --ip 10.2.0.3 \
  --dns 10.2.0.2 \
  --device /dev/kvm \
  -p 50925:10022 \
  -v /tmp/.X11-unix:/tmp/.X11-unix \
  -v mac-sequoia-data:/image \
  -e "DISPLAY=${DISPLAY:-:0.0}" \
  -e GENERATE_UNIQUE=true \
  -e CPU='Haswell-noTSX' \
  -e CPU_COUNT=8 \
  -e RAM=8 \
  -e WIDTH=2560 \
  -e HEIGHT=1600 \
  -e CPUID_FLAGS='kvm=on,vendor=GenuineIntel,+invtsc,vmware-cpuid-freq=on' \
  -e MASTER_PLIST_URL='https://raw.githubusercontent.com/sickcodes/osx-serial-generator/master/config-custom-sonoma.plist' \
  -e SHORTNAME=sequoia \
  sickcodes/docker-osx:latest
```

#### 2. Mac-Tahoe (Qua Router 10.3.0.2)
```bash
docker run -it \
  --name mac-tahoe \
  --hostname mac-tahoe \
  --network lan-tahoe \
  --ip 10.3.0.3 \
  --dns 10.3.0.2 \
  --device /dev/kvm \
  -p 50926:10022 \
  -v /tmp/.X11-unix:/tmp/.X11-unix \
  -v mac-tahoe-data:/image \
  -e "DISPLAY=${DISPLAY:-:0.0}" \
  -e GENERATE_UNIQUE=true \
  -e CPU='Haswell-noTSX' \
  -e CPU_COUNT=8 \
  -e RAM=8 \
  -e WIDTH=2560 \
  -e HEIGHT=1600 \
  -e CPUID_FLAGS='kvm=on,vendor=GenuineIntel,+invtsc,vmware-cpuid-freq=on' \
  -e MASTER_PLIST_URL='https://raw.githubusercontent.com/sickcodes/osx-serial-generator/master/config-custom-sonoma.plist' \
  -e SHORTNAME=tahoe \
  sickcodes/docker-osx:latest
```

#### 3. Mac-Sonoma (Qua Router 10.1.0.2)
```bash
docker run -it \
    --name mac-sonoma \
    --hostname mac-sonoma \
    --network lan-net-01 \
    --ip 10.1.0.3 \
    --dns 10.1.0.2 \
    --device /dev/kvm \
    -p 50922:10022 \
    -v mac-sonoma-data:/image \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    -e "DISPLAY=${DISPLAY:-:0.0}" \
    -e GENERATE_UNIQUE=true \
    -e CPU='Haswell-noTSX' \
    -e CPU_COUNT=8 \
    -e RAM=8 \
    -e WIDTH=2560 \
    -e HEIGHT=1600 \
    -e CPUID_FLAGS='kvm=on,vendor=GenuineIntel,+invtsc,vmware-cpuid-freq=on' \
    -e MASTER_PLIST_URL='https://raw.githubusercontent.com/sickcodes/osx-serial-generator/master/config-custom-sonoma.plist' \
    -e SHORTNAME=sonoma \
    -e EXTRA_QEMU_ARGS="-name mac-sonoma" \
    sickcodes/docker-osx:latest
```
