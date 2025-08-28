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
$logFile = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads\WinFingerPrint.log'

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMsg = "$timestamp - $Message"
    Write-Host $logMsg
    Add-Content -Path $logFile -Value $logMsg
}

function Get-RandomFontList {
    param(
        [Parameter(Mandatory=$true)][array]$FontList,
        [Parameter(Mandatory=$true)][int]$Count
    )
    return $FontList | Get-Random -Count $Count
}

function Get-TtfUrl {
    param([array]$Variants)
    foreach ($variant in $Variants) {
        if ($variant.ttf) {
            return $variant.ttf
        }
    }
    return $null
}

function Install-Font {
    param(
        [string]$FontName,
        [string]$TtfUrl,
        [string]$FontFolder
    )
    $fontFile = Join-Path $FontFolder "$FontName.ttf"
    $destPath = "C:\Windows\Fonts\$FontName.ttf"
    $fontRegName = "$FontName (TrueType)"

    try {
        Invoke-WebRequest -Uri $TtfUrl -OutFile $fontFile -UseBasicParsing
        Write-Log "Tải font $FontName thành công."
    } catch {
        Write-Log "Tải font $FontName thất bại, bỏ qua."
        return
    }

    try {
        Copy-Item $fontFile $destPath -Force
        Write-Log "Copy font $FontName vào $destPath thành công."
    } catch {
        Write-Log "Không thể copy font $FontName vào thư mục hệ thống."
        return
    }

    try {
        New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts" `
            -Name $fontRegName -Value "$FontName.ttf" -PropertyType String -Force | Out-Null
        Write-Log "Đăng ký font $FontName vào registry thành công."
    } catch {
        Write-Log "Không thể đăng ký font $FontName vào registry."
        return
    }

    Write-Log "Đã cài đặt font: $FontName"
}

function Ensure-Folder {
    param([string]$Path)
    if (!(Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
        Write-Log "Tạo thư mục tạm: $Path"
    }
}

function Main {
    $fontCount = Get-Random -Minimum 2 -Maximum 5
    $fontFolder = Join-Path $env:TEMP 'RandomFonts'
    Ensure-Folder $fontFolder

    $fontListUrl = "https://google-webfonts-helper.herokuapp.com/api/fonts"
    try {
        $fontList = Invoke-RestMethod -Uri $fontListUrl
        Write-Log "Lấy danh sách font thành công."
    } catch {
        Write-Log "Không thể lấy danh sách font. Kiểm tra kết nối mạng."
        exit 1
    }

    $randomFonts = Get-RandomFontList -FontList $fontList -Count $fontCount
    Write-Log "Sẽ cài đặt $fontCount font: $($randomFonts.id -join ', ')"

    foreach ($font in $randomFonts) {
        $fontName = $font.id
        $ttfUrl = Get-TtfUrl -Variants $font.variants
        if (-not $ttfUrl) {
            Write-Log "Không tìm thấy file TTF cho font $fontName, bỏ qua."
            continue
        }
        Install-Font -FontName $fontName -TtfUrl $ttfUrl -FontFolder $fontFolder

        $sleepSec = Get-Random -Minimum 2 -Maximum 6
        Write-Log "Chờ $sleepSec giây trước khi cài font tiếp theo."
        Start-Sleep -Seconds $sleepSec
    }

    Write-Log "Hoàn thành cài đặt $fontCount font mới từ Google Fonts!"

    try {
        Write-Log "Đang khởi động lại explorer..."
        Stop-Process -Name explorer -Force
        Start-Sleep -Seconds 2
        Start-Process explorer.exe
        Write-Log "Khởi động lại explorer thành công."
    } catch {
        Write-Log "Không thể khởi động lại explorer. Bạn hãy nhấn Ctrl+Shift+Esc, vào File > Run new task, gõ explorer.exe để mở lại giao diện."
    }
}

Main
