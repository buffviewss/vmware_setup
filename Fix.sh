# Enable and start the systemd-resolved service
sudo systemctl enable systemd-resolved
sudo systemctl start systemd-resolved

# Create a symlink for /etc/resolv.conf
sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
