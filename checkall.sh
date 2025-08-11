echo "===== Thông tin ngày/giờ ====="
echo "Local time : $(date '+%Y-%m-%d %H:%M:%S %z (%Z)')"
echo "UTC time   : $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "Epoch time : $(date +%s)"
timedatectl
locale | grep -E '^(LANG|LC_TIME)='
echo

echo "===== Phiên bản Chrome/Chromium ====="
if command -v google-chrome >/dev/null 2>&1; then
    google-chrome --version
elif command -v google-chrome-stable >/dev/null 2>&1; then
    google-chrome-stable --version
elif command -v chromium >/dev/null 2>&1; then
    chromium --version
elif command -v chromium-browser >/dev/null 2>&1; then
    chromium-browser --version
else
    echo "⚠️ Không tìm thấy Chrome/Chromium."
fi
echo

echo "===== IP hiện tại ====="
echo "IP nội bộ:"
hostname -I
if command -v curl >/dev/null 2>&1; then
    echo "Public IPv4: $(curl -4s https://ifconfig.co)"
    echo "Public IPv6: $(curl -6s https://ifconfig.co)"
else
    echo "⚠️ Thiếu curl để lấy IP công khai."
fi
