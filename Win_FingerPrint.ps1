<#
Script này sẽ:
- Lấy danh sách font từ Google Fonts (qua API phụ trợ)
- Chọn ngẫu nhiên một số font
- Tải về và cài đặt vào Windows
- Đăng ký font vào registry
- Thêm delay ngẫu nhiên để mô phỏng thao tác người thật
- Ghi log quá trình vào file log

Yêu cầu: Chạy PowerShell với quyền Administrator
#>

# Đường dẫn file log (lưu ở thư mục Download của user)
$logFile = [System.IO.Path]::Combine([Environment]::GetFolderPath('UserProfile'), 'Downloads', 'WinFingerPrint.log')

Function Write-Log {
    param([string]$msg)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMsg = "$timestamp - $msg"
    Write-Host $logMsg
    Add-Content -Path $logFile -Value $logMsg
}

# Số lượng font muốn cài mỗi lần (random từ 2 đến 5)
$fontCount = Get-Random -Minimum 2 -Maximum 5

# Tạo thư mục lưu font tạm
$fontFolder = "$env:TEMP\RandomFonts"
if (!(Test-Path $fontFolder)) { 
    New-Item -ItemType Directory -Path $fontFolder | Out-Null 
    Write-Log "Tạo thư mục tạm: $fontFolder"
}

# Lấy danh sách font từ Google Fonts Helper API
$fontListUrl = "https://google-webfonts-helper.herokuapp.com/api/fonts"
try {
    $fontList = Invoke-RestMethod -Uri $fontListUrl
    Write-Log "Lấy danh sách font thành công."
} catch {
    Write-Log "Không thể lấy danh sách font. Kiểm tra kết nối mạng."
    exit 1
}

# Chọn ngẫu nhiên font
$randomFonts = $fontList | Get-Random -Count $fontCount
Write-Log "Sẽ cài đặt $fontCount font: $($randomFonts.id -join ', ')"

foreach ($font in $randomFonts) {
    $fontName = $font.id
    # Lấy bản ttf đầu tiên (thường là Regular)
    $ttfUrl = $null
    foreach ($variant in $font.variants) {
        if ($variant.ttf) {
            $ttfUrl = $variant.ttf
            break
        }
    }
    if (-not $ttfUrl) {
        Write-Log "Không tìm thấy file TTF cho font $fontName, bỏ qua."
        continue
    }

    # Tải font về thư mục tạm
    $fontFile = "$fontFolder\$fontName.ttf"
    try {
        Invoke-WebRequest -Uri $ttfUrl -OutFile $fontFile -UseBasicParsing
        Write-Log "Tải font $fontName thành công."
    } catch {
        Write-Log "Tải font $fontName thất bại, bỏ qua."
        continue
    }

    # Copy vào thư mục hệ thống
    $destPath = "C:\Windows\Fonts\$fontName.ttf"
    try {
        Copy-Item $fontFile $destPath -Force
        Write-Log "Copy font $fontName vào $destPath thành công."
    } catch {
        Write-Log "Không thể copy font $fontName vào thư mục hệ thống."
        continue
    }

    # Đăng ký font vào registry
    $fontRegName = "$fontName (TrueType)"
    try {
        New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts" `
            -Name $fontRegName -Value "$fontName.ttf" -PropertyType String -Force | Out-Null
        Write-Log "Đăng ký font $fontName vào registry thành công."
    } catch {
        Write-Log "Không thể đăng ký font $fontName vào registry."
        continue
    }

    Write-Log "Đã cài đặt font: $fontName"

    # Delay ngẫu nhiên để giống thao tác người thật
    $sleepSec = Get-Random -Minimum 2 -Maximum 6
    Write-Log "Chờ $sleepSec giây trước khi cài font tiếp theo."
    Start-Sleep -Seconds $sleepSec
}

Write-Log "Hoàn thành cài đặt $fontCount font mới từ Google Fonts!"

# Khởi động lại explorer để áp dụng (nếu cần)
try {
    Write-Log "Đang khởi động lại explorer..."
    Stop-Process -Name explorer -Force
    Start-Sleep -Seconds 2
    Start-Process explorer.exe
    Write-Log "Khởi động lại explorer thành công."
} catch {
    Write-Log "Không thể khởi động lại explorer. Bạn hãy nhấn Ctrl+Shift+Esc, vào File > Run new task, gõ explorer.exe để mở lại giao diện."
}
