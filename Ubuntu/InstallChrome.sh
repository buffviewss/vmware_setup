#!/bin/bash

# === Tự cài Python venv và gdown ===
if [[ ! -d "$HOME/gdown-venv" ]]; then
    echo "📦 Đang tạo venv Python và cài gdown..."
    python3 -m venv ~/gdown-venv
fi

source ~/gdown-venv/bin/activate

# Cài gdown trong venv (đảm bảo luôn có)
pip install --no-cache-dir gdown

# === Cấu hình Google Drive Folder ID ===
CHROME_DRIVE_ID="1tD0XPj-t5C7p9ByV3RLg-qcHaYYSXAj1"
FIREFOX_DRIVE_ID="1CeMNJTLgfsaFkcroOh1xpxFC-uz9HrLb"

DOWNLOAD_DIR="$HOME/browser_temp"
mkdir -p "$DOWNLOAD_DIR" && cd "$DOWNLOAD_DIR"

# === Chọn trình duyệt ===
echo "Chọn trình duyệt muốn cài:"
select browser in "Chrome" "Firefox" "Thoát"; do
    case $browser in
        Chrome) DRIVE_ID="$CHROME_DRIVE_ID"; BTYPE="chrome"; break;;
        Firefox) DRIVE_ID="$FIREFOX_DRIVE_ID"; BTYPE="firefox"; break;;
        Thoát) echo "🚪 Thoát script."; exit 0;;
        *) echo "❌ Lựa chọn không hợp lệ!";;
    esac
done

# === Tải toàn bộ folder từ Google Drive ===
echo "📥 Đang tải toàn bộ folder $BTYPE từ Google Drive..."
gdown --folder "https://drive.google.com/drive/folders/$DRIVE_ID" --no-cookies

# === Liệt kê file tải về ===
echo "🔍 Danh sách file tải về:"
if [[ $BTYPE == "chrome" ]]; then
    FILE_LIST=$(find "$DOWNLOAD_DIR" -type f -name "*.deb")
else
    FILE_LIST=$(find "$DOWNLOAD_DIR" -type f)
fi

if [[ -z "$FILE_LIST" ]]; then
    echo "❌ Không tìm thấy file hợp lệ!"
    exit 1
fi

# Hiển thị danh sách để chọn
echo "$FILE_LIST" | nl -s". "
read -p "👉 Nhập số thứ tự file muốn cài: " choice

FILE_SELECT=$(echo "$FILE_LIST" | sed -n "${choice}p")

if [[ ! -f "$FILE_SELECT" ]]; then
    echo "❌ File không tồn tại!"
    exit 1
fi

echo "✅ Chọn file: $FILE_SELECT"

# === Xóa file không được chọn để tiết kiệm dung lượng ===
echo "🧹 Dọn dẹp file không dùng..."
find "$DOWNLOAD_DIR" -type f ! -name "$(basename "$FILE_SELECT")" -delete

# === Gỡ bản mặc định ===
echo "🗑️ Gỡ bản mặc định..."
if [[ $BTYPE == "chrome" ]]; then
    sudo apt remove -y google-chrome-stable || true
elif [[ $BTYPE == "firefox" ]]; then
    sudo snap remove firefox || sudo apt remove -y firefox || true
fi

# === Cài đặt và khóa cập nhật ===
if [[ $BTYPE == "chrome" ]]; then
    echo "🚀 Đang cài Chrome..."
    sudo dpkg -i "$FILE_SELECT"
    sudo apt -f install -y
    sudo apt-mark hold google-chrome-stable
    sudo sed -i 's/^deb/# deb/' /etc/apt/sources.list.d/google-chrome.list 2>/dev/null

    # 🔒 Tắt update nội bộ của Chrome
    echo "🚫 Tắt update nội bộ Chrome..."
    sudo rm -rf /opt/google/chrome/cron/
    sudo mkdir -p /etc/opt/chrome/policies/managed
    cat <<EOF > /tmp/disable_update.json
{
  "AutoUpdateCheckPeriodMinutes": 0,
  "DisableAutoUpdateChecksCheckbox": true,
  "MetricsReportingEnabled": false
}
EOF
    sudo mv /tmp/disable_update.json /etc/opt/chrome/policies/managed/disable_update.json
    sudo chmod -R 000 /opt/google/chrome/cron || true

elif [[ $BTYPE == "firefox" ]]; then
    echo "🚀 Đang cài Firefox..."
    tar -xf "$FILE_SELECT"
    sudo rm -rf /opt/firefox_custom
    sudo mv firefox /opt/firefox_custom
    sudo ln -sf /opt/firefox_custom/firefox /usr/local/bin/firefoxcustom

    # 🔒 Tắt update nội bộ Firefox bằng policy và cấu hình
    echo "🚫 Tắt update nội bộ Firefox..."
    sudo mkdir -p /opt/firefox_custom/distribution
    cat <<EOF2 | sudo tee /opt/firefox_custom/distribution/policies.json >/dev/null
{
  "policies": {
    "AppAutoUpdate": false,
    "DisableAppUpdate": true,
    "ManualAppUpdateOnly": true
  }
}
EOF2

    # Tạo file cấu hình cứng chặn update
    sudo mkdir -p /opt/firefox_custom/browser/defaults/preferences
    echo 'pref("app.update.enabled", false);' | sudo tee /opt/firefox_custom/browser/defaults/preferences/disable_update.js >/dev/null
fi

# === Tạo shortcut ===
echo "🎨 Tạo shortcut..."
if [[ $BTYPE == "chrome" ]]; then
    cat <<EOF3 > ~/.local/share/applications/browser_custom.desktop
[Desktop Entry]
Name=Google Chrome (Custom)
Exec=/usr/bin/google-chrome-stable %U
Icon=google-chrome
Type=Application
Categories=Network;WebBrowser;
StartupNotify=true
EOF3
else
    cat <<EOF3 > ~/.local/share/applications/browser_custom.desktop
[Desktop Entry]
Name=Firefox (Custom)
Exec=/usr/local/bin/firefoxcustom %U
Icon=/opt/firefox_custom/browser/chrome/icons/default/default128.png
Type=Application
Categories=Network;WebBrowser;
StartupNotify=true
EOF3
fi

# === Pin vào taskbar ===
if command -v gsettings &>/dev/null; then
    gio set ~/.local/share/applications/browser_custom.desktop metadata::trusted true 2>/dev/null
    gsettings set org.gnome.shell favorite-apps "$(gsettings get org.gnome.shell favorite-apps | sed "s/]$/, 'browser_custom.desktop']/")"
else
    echo "ℹ️ Trên Lubuntu (LXQt), hãy nhấp phải biểu tượng trong menu -> 'Pin to Panel'."
fi

echo "✅ Hoàn tất! $BTYPE đã được cài, khóa update và tắt update nội bộ."
