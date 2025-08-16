lsmod | egrep 'hv_(vmbus|netvsc|storvsc|sock)' || echo "hv modules not loaded"
uname -r




sudo systemctl stop xrdp || true
sudo apt purge -y xrdp xorgxrdp
sudo rm -rf /etc/xrdp /var/run/xrdp
sudo apt update
sudo apt install -y xrdp xorgxrdp gvfs-fuse




# Cho user 'xrdp' đọc private key TLS
sudo adduser xrdp ssl-cert

# Bật VSock để Hyper-V Enhanced Session dùng kênh nội bộ (không qua TCP)
sudo sed -i 's/^port=.*/port=-1/' /etc/xrdp/xrdp.ini
sudo sed -i 's/^#\?use_vsock=.*/use_vsock=true/' /etc/xrdp/xrdp.ini

# Nạp và tự nạp module hv_sock
echo hv_sock | sudo tee /etc/modules-load.d/hv_sock.conf
sudo modprobe hv_sock




sudo systemctl enable --now xrdp
systemctl status xrdp --no-pager -l




journalctl -xeu xrdp --no-pager



Enhanced Session Mode



sudo sed -i 's/^use_vsock=.*/use_vsock=false/' /etc/xrdp/xrdp.ini
sudo sed -i 's/^port=.*/port=3389/' /etc/xrdp/xrdp.ini
sudo systemctl restart xrdp && systemctl status xrdp --no-pager -l




socks5://217.177.34.19:6012:eyvizq4mf8n3:6jo0C8dNSfrtkclt




systemctl status xrdp --no-pager -l
journalctl -xeu xrdp --no-pager | tail -n 100
