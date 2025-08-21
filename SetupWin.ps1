# --- Kiểm tra và cài đặt PowerShell 7 (nếu cần) ---

# Kiểm tra phiên bản PowerShell hiện tại
$CurrentVersion = $PSVersionTable.PSVersion.Major

# Nếu phiên bản PowerShell hiện tại nhỏ hơn 7, tiến hành cài đặt PowerShell 7
if ($CurrentVersion -lt 7) {
    Write-Host "Phiên bản PowerShell hiện tại là $CurrentVersion. Đang nâng cấp lên PowerShell 7..."
    
    # Kiểm tra xem winget có sẵn không
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "Đang cài đặt PowerShell 7 qua winget..."
        # Cài đặt PowerShell 7
        winget install --id Microsoft.Powershell --source winget
        Write-Host "PowerShell đã được nâng cấp thành công."
    } else {
        Write-Host "winget không có sẵn trên hệ thống của bạn. Hãy cài đặt PowerShell 7 thủ công từ GitHub."
        exit
    }
} else {
    Write-Host "Phiên bản PowerShell hiện tại là $CurrentVersion. Không cần nâng cấp."
}
# --- Cấu hình đầu script ---

# Danh sách các phiên bản Chrome và ID tệp Google Drive
# Bạn sẽ cần nhập ID của các tệp thủ công từ Google Drive
$ChromeVersions = @{
    1 = @{ Name = "google-chrome-135-0-7049-96"  ; ID = "1oSfjrZvx7LUoF6YHGiImcN1sI5ka1RGJ" }
    2 = @{ Name = "google-chrome-136-0-7103-114"  ; ID = "1z850sfY0i720Oa3jf6A3E1KKcAAiMNFR" }
    3 = @{ Name = "google-chrome-137-0-7151-120"  ; ID = "1FgkcBwoGr5C-55ZX433IEz9mH7UbGTlr" }
    4 = @{ Name = "google-chrome-138-0-7194-0"  ; ID = "1QEMHQSJk3A_KcK2t_yuYXcVjHVAPHQay" }
    5 = @{ Name = "google-chrome-141-0-7340-0"  ; ID = "1El9yy2-AMu3ZUZoGK8KoYujXPt8WQ9Ko" }
}

# ID của tệp Nekobox trên Google Drive (cập nhật bằng ID thực tế)
$NekoBoxFileID = "1Rs7as6-oHv9IIHAurlgwmc_WigSLYHJb"  # Thay thế ID của tệp Nekobox trong Google Drive

# Đường dẫn tải xuống tệp cài đặt Chrome và Nekobox
$DownloadPathChrome = "$env:USERPROFILE\Downloads\chrome_installer.exe"
$DownloadPathNekoBox = "$env:USERPROFILE\Downloads\nekobox_installer.zip"

# Đường dẫn cài đặt Nekobox
$InstallPath = "$env:ProgramFiles\Nekobox"

# --- Cấu hình kết thúc ---

# Hàm kiểm tra quyền quản trị
function Check-AdminRights {
    try {
        $null = [System.Security.Principal.WindowsPrincipal][System.Security.Principal.WindowsIdentity]::GetCurrent()
        $IsAdmin = $true
    } catch {
        $IsAdmin = $false
    }

    if (-not $IsAdmin) {
        Write-Host "Lỗi: Bạn cần quyền quản trị để chạy script này. Hãy mở PowerShell với quyền quản trị và thử lại."
        exit
    }
}

# Hàm để thay đổi ngôn ngữ hệ thống, múi giờ và thông tin quốc gia
function Set-RegionSettings {
    param([string]$Region)

    # Thay đổi ngôn ngữ hệ thống
    $Lang = switch($Region) {
        "UK" {"en-GB"}
        "US" {"en-US"}
        "AU" {"en-AU"}
        "SINGAPORE" {"en-SG"}
        "NEWZELAND" {"en-NZ"}
        default {"en-US"}
    }

    Set-WinUILanguageOverride -Language $Lang
    Set-WinUserLanguageList $Lang -Force
    Set-TimeZone -Id "UTC"

    # Thay đổi vùng
    Set-WinDefaultInputMethodOverride -InputTip "0409:00000409" # 0409:US Keyboard
    Set-RegionalFormat -Locale $Lang
}

# Gỡ cài đặt Chrome nếu đã cài đặt
function Uninstall-Chrome {
    Write-Host "Đang kiểm tra và gỡ bỏ Google Chrome nếu có..."
    $chromeUninstallKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    $chromeAppKey = Get-ChildItem -Path $chromeUninstallKey | Where-Object { $_.GetValue("DisplayName") -like "Google Chrome*" }

    if ($chromeAppKey) {
        Write-Host "Đang gỡ bỏ Google Chrome..."
        $uninstallString = $chromeAppKey.GetValue("UninstallString")
        
        # Thực thi lệnh gỡ bỏ
        Start-Process -FilePath $uninstallString -ArgumentList "/silent /uninstall" -Wait
        Write-Host "Google Chrome đã được gỡ bỏ thành công."
    } else {
        Write-Host "Không tìm thấy Google Chrome cài đặt trên máy."
    }
}

# Tải tệp Chrome từ Google Drive
function Download-Chrome {
    param([string]$FileID)

    $DownloadUrl = "https://drive.google.com/uc?id=$FileID&export=download"
    Write-Host "Đang tải Chrome từ Google Drive: $DownloadUrl"

    try {
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $DownloadPathChrome -ErrorAction Stop
    } catch {
        Write-Host "Lỗi: Không thể tải tệp Chrome từ Google Drive. Kiểm tra lại link Google Drive."
        exit
    }

    if (Test-Path $DownloadPathChrome) {
        Write-Host "Đã tải xong tệp cài đặt Chrome."
    } else {
        Write-Host "Lỗi: Không thể tải tệp cài đặt Chrome."
        exit
    }
}

# Cài đặt Chrome
function Install-Chrome {
    Write-Host "Đang cài đặt Chrome..."
    Start-Process -FilePath $DownloadPathChrome -ArgumentList "/silent /install" -Wait
    Write-Host "Cài đặt Chrome xong."
}

# Khóa cập nhật tự động của Chrome
function Disable-AutoUpdateChrome {
    Write-Host "Đang vô hiệu hóa cập nhật tự động của Chrome..."

    $chromeUpdateKey = "HKLM:\SOFTWARE\Policies\Google\Update"
    
    # Kiểm tra nếu không có khóa thì tạo mới
    if (-not (Test-Path $chromeUpdateKey)) {
        New-Item -Path $chromeUpdateKey -Force
    }

    # Thiết lập khóa vô hiệu hóa cập nhật tự động
    Set-ItemProperty -Path $chromeUpdateKey -Name "AutoUpdateCheckPeriodMinutes" -Value 0
    Set-ItemProperty -Path $chromeUpdateKey -Name "DisableAutoUpdate" -Value 1

    Write-Host "Cập nhật tự động của Chrome đã được vô hiệu hóa."
}

# Tải tệp Nekobox từ Google Drive
function Download-Nekobox {
    param([string]$FileID)

    $DownloadUrl = "https://drive.google.com/uc?id=$FileID&export=download"
    Write-Host "Đang tải Nekobox từ Google Drive: $DownloadUrl"

    try {
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $DownloadPathNekoBox -ErrorAction Stop
    } catch {
        Write-Host "Lỗi: Không thể tải tệp Nekobox từ Google Drive. Kiểm tra lại link Google Drive."
        exit
    }

    if (Test-Path $DownloadPathNekoBox) {
        Write-Host "Đã tải xong tệp cài đặt Nekobox."
    } else {
        Write-Host "Lỗi: Không thể tải tệp cài đặt Nekobox."
        exit
    }
}

# Giải nén tệp Nekobox
function Extract-Nekobox {
    Write-Host "Đang giải nén Nekobox..."

    $extractPath = "$env:USERPROFILE\Downloads\nekobox"
    
    # Kiểm tra nếu thư mục giải nén đã tồn tại, nếu có thì xóa nó
    if (Test-Path $extractPath) {
        Remove-Item -Path $extractPath -Recurse -Force
    }

    # Giải nén tệp
    Expand-Archive -Path $DownloadPathNekoBox -DestinationPath $extractPath

    Write-Host "Đã giải nén Nekobox vào thư mục: $extractPath"
}

# Cài đặt Nekobox từ thư mục giải nén
function Install-Nekobox {
    Write-Host "Đang cài đặt Nekobox từ thư mục giải nén..."

    Start-Process -FilePath "$env:USERPROFILE\Downloads\nekobox\nekobox.exe" -ArgumentList "/silent /install /dir=$InstallPath" -Wait

    Write-Host "Cài đặt Nekobox xong."
}

# Thiết lập Nekobox tự động mở khi khởi động Windows
function Set-AutoStart {
    Write-Host "Đang thiết lập Nekobox tự động mở khi khởi động..."

    $key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    $value = "Nekobox"
    $command = "$InstallPath\nekobox.exe"

    Set-ItemProperty -Path $key -Name $value -Value $command
    Write-Host "Nekobox đã được thêm vào danh sách khởi động."
}

# Pin Nekobox vào Taskbar
function Pin-To-Taskbar {
    Write-Host "Đang pin Nekobox vào Taskbar..."

    $taskbarPinCmd = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
    $shortcutPath = "$taskbarPinCmd\Nekobox.lnk"
    
    # Kiểm tra xem shortcut có tồn tại chưa, nếu chưa thì tạo
    if (-not (Test-Path $shortcutPath)) {
        $WshShell = New-Object -ComObject WScript.Shell
        $shortcut = $WshShell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = "$InstallPath\nekobox.exe"
        $shortcut.Save()
    }

    # Pin ứng dụng vào taskbar
    Invoke-Expression -Command "powershell -command $shortcutPath"
    Write-Host "Nekobox đã được pin vào Taskbar."
}

# Kiểm tra quyền quản trị
Check-AdminRights

# Thực hiện thay đổi ngôn ngữ và cài đặt Chrome
Set-RegionSettings -Region "US"

# Tải và cài đặt Chrome
Download-Chrome -FileID "FILE_ID_FOR_CHROME"
Uninstall-Chrome
Install-Chrome

# Khóa cập nhật tự động của Chrome
Disable-AutoUpdateChrome

# Tải, giải nén và cài đặt Nekobox
Download-Nekobox -FileID $NekoBoxFileID
Extract-Nekobox
Install-Nekobox

# Thiết lập Nekobox tự động mở khi khởi động Windows
Set-AutoStart

# Pin Nekobox vào Taskbar
Pin-To-Taskbar

Write-Host "Tất cả các bước đã hoàn thành!"

