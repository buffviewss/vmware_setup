#!/bin/bash

# === SỬA TẤT CẢ VẤN ĐỀ PASSWORD ===

echo "🔧 Đang sửa tất cả vấn đề password..."

# 1. XÓA PASSWORD CỦA USER HIỆN TẠI
echo "🔓 Xóa password user..."
sudo passwd -d $USER

# 2. CẤU HÌNH SUDO KHÔNG CẦN PASSWORD
echo "⚡ Cấu hình sudo không cần password..."
echo "$USER ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/$USER

# 3. CẤU HÌNH AUTO-LOGIN CHO LIGHTDM (LUBUNTU)
echo "🚀 Cấu hình auto-login cho LightDM..."
sudo mkdir -p /etc/lightdm/lightdm.conf.d
sudo tee /etc/lightdm/lightdm.conf.d/50-autologin.conf << EOF
[Seat:*]
autologin-user=$USER
autologin-user-timeout=0
autologin-session=Lubuntu
EOF

# 4. CẤU HÌNH AUTO-LOGIN CHO GDM3 (UBUNTU)
echo "🚀 Cấu hình auto-login cho GDM3..."
sudo tee /etc/gdm3/custom.conf << EOF
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=$USER

[security]

[xdmcp]

[chooser]

[debug]
EOF

# 5. TẮT HOÀN TOÀN GNOME KEYRING
echo "🔑 Tắt GNOME Keyring..."
sudo apt remove --purge -y gnome-keyring seahorse 2>/dev/null || true
sudo apt remove --purge -y kwalletmanager kwallet-kf5 2>/dev/null || true

# 6. XÓA TẤT CẢ KEYRING DATA
echo "🗑️ Xóa keyring data..."
rm -rf ~/.local/share/keyrings 2>/dev/null || true
rm -rf ~/.gnupg 2>/dev/null || true
rm -rf ~/.config/kwalletrc 2>/dev/null || true

# 7. TẮT PAM KEYRING
echo "🔒 Tắt PAM keyring..."
sudo sed -i 's/.*pam_gnome_keyring.so.*/#&/' /etc/pam.d/login 2>/dev/null || true
sudo sed -i 's/.*pam_gnome_keyring.so.*/#&/' /etc/pam.d/passwd 2>/dev/null || true
sudo sed -i 's/.*pam_gnome_keyring.so.*/#&/' /etc/pam.d/gdm-password 2>/dev/null || true
sudo sed -i 's/.*pam_gnome_keyring.so.*/#&/' /etc/pam.d/gdm-autologin 2>/dev/null || true

# 8. TẮT POLICYKIT PASSWORD PROMPTS
echo "🛡️ Tắt PolicyKit prompts..."
sudo mkdir -p /etc/polkit-1/localauthority/50-local.d
sudo tee /etc/polkit-1/localauthority/50-local.d/disable-passwords.pkla << EOF
[Disable password prompts for $USER]
Identity=unix-user:$USER
Action=*
ResultActive=yes
ResultInactive=yes
ResultAny=yes
EOF

# 9. CẤU HÌNH CHROME KHÔNG YÊU CẦU PASSWORD
echo "🌐 Cấu hình Chrome..."
mkdir -p ~/.config/google-chrome/Default
cat > ~/.config/google-chrome/Default/Preferences << 'EOF'
{
   "profile": {
      "password_manager_enabled": false,
      "default_content_setting_values": {
         "password_manager": 2
      }
   }
}
EOF

# 10. CẤU HÌNH FIREFOX KHÔNG YÊU CẦU PASSWORD
echo "🦊 Cấu hình Firefox..."
# Tạo profile Firefox nếu chưa có
firefox -CreateProfile "default" 2>/dev/null || true
sleep 2
pkill firefox 2>/dev/null || true

# Tìm Firefox profile directory
FF_PROFILE=$(find ~/.mozilla/firefox -name "*.default*" -type d 2>/dev/null | head -n 1)
if [[ -n "$FF_PROFILE" ]]; then
    cat > "$FF_PROFILE/user.js" << 'EOF'
user_pref("security.ask_for_password", 0);
user_pref("security.password_lifetime", 9999);
user_pref("signon.rememberSignons", false);
user_pref("security.default_personal_cert", "");
EOF
fi

# 11. TẮT SYSTEMD USER SERVICES CÓ THỂ GÂY PROMPT
echo "⚙️ Tắt các service không cần thiết..."
systemctl --user disable gnome-keyring-daemon 2>/dev/null || true
systemctl --user stop gnome-keyring-daemon 2>/dev/null || true

# 12. XÓA CHROME KEYRING INTEGRATION
echo "🔧 Xóa Chrome keyring integration..."
sudo rm -f /usr/share/applications/google-chrome.desktop 2>/dev/null || true
cat > ~/.local/share/applications/google-chrome.desktop << 'EOF'
[Desktop Entry]
Version=1.0
Name=Google Chrome
Comment=Access the Internet
Exec=/usr/bin/google-chrome-stable --password-store=basic %U
StartupNotify=true
Terminal=false
Icon=google-chrome
Type=Application
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;
EOF

chmod +x ~/.local/share/applications/google-chrome.desktop

echo ""
echo "✅ ĐÃ SỬA TẤT CẢ VẤN ĐỀ!"
echo ""
echo "🔄 BẮT BUỘC PHẢI KHỞI ĐỘNG LẠI để áp dụng:"
echo "   sudo reboot"
echo ""
echo "📋 Sau khi reboot:"
echo "   ✅ Máy tự động vào desktop (không cần password)"
echo "   ✅ Sudo commands chạy không cần password"
echo "   ✅ Chrome/Firefox mở không hỏi master password"
echo ""
read -p "🔄 Khởi động lại ngay bây giờ? (y/n): " -r
if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo reboot
fi