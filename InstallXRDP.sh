sudo apt update
sudo apt install -y xrdp xorgxrdp
# Bật kết nối qua Hyper-V socket (vsock)
sudo sed -i 's/^port=.*/port=-1/' /etc/xrdp/xrdp.ini
sudo sed -i 's/^#\?use_vsock=.*/use_vsock=true/' /etc/xrdp/xrdp.ini
sudo adduser $USER ssl-cert
sudo systemctl enable --now xrdp
