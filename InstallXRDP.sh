# 0) Stop và gỡ sạch cấu hình cũ (nếu có)
sudo systemctl stop xrdp || true
sudo apt purge -y xrdp xorgxrdp
sudo rm -rf /etc/xrdp /var/run/xrdp

# 1) Cài lại gói cần thiết
sudo apt update
sudo apt install -y xrdp xorgxrdp gvfs-fuse

# 2) Cho user "xrdp" đọc private key TLS (nguyên nhân fail phổ biến nhất)
sudo adduser xrdp ssl-cert

# 3) Bật Hyper-V socket (vsock) cho Enhanced Session
sudo sed -i 's/^port=.*/port=-1/' /etc/xrdp/xrdp.ini
sudo sed -i 's/^#\?use_vsock=.*/use_vsock=true/' /etc/xrdp/xrdp.ini

# 4) Đảm bảo module hv_sock được nạp mỗi lần boot
echo hv_sock | sudo tee /etc/modules-load.d/hv_sock.conf
sudo modprobe hv_sock

# 5) Sửa quyền file key nếu cần (đôi lúc bị sai quyền)
sudo chgrp ssl-cert /etc/ssl/private/ssl-cert-snakeoil.key 2>/dev/null || true
sudo chmod 640 /etc/ssl/private/ssl-cert-snakeoil.key 2>/dev/null || true

# 6) Xoá PID/Socket cũ rồi bật dịch vụ
sudo rm -rf /var/run/xrdp
sudo systemctl enable --now xrdp

# 7) Kiểm tra trạng thái (phải nhìn thấy active (running))
systemctl status xrdp --no-pager -l



socks5://217.177.34.19:6012:eyvizq4mf8n3:6jo0C8dNSfrtkclt
