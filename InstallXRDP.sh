# Cài đủ gói cần thiết
sudo apt update
sudo apt install -y xrdp xorgxrdp gvfs-fuse

# (QUAN TRỌNG) Cho user 'xrdp' vào group ssl-cert để đọc key TLS
sudo adduser xrdp ssl-cert

# Bật kênh Hyper-V socket (vsock)
sudo sed -i 's/^port=.*/port=-1/' /etc/xrdp/xrdp.ini
sudo sed -i 's/^#\?use_vsock=.*/use_vsock=true/' /etc/xrdp/xrdp.ini

# Nạp module hv_sock và tự nạp sau reboot
echo hv_sock | sudo tee /etc/modules-load.d/hv_sock.conf
sudo modprobe hv_sock

# Khởi động dịch vụ và đặt auto-start
sudo systemctl enable --now xrdp

# Kiểm tra trạng thái (phải thấy active (running))
systemctl status xrdp --no-pager -l
