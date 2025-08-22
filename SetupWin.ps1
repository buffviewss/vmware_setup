# Ghi lại lỗi vào tệp log
$logFile = "$env:USERPROFILE\Downloads\script_log.txt"
$ErrorActionPreference = "Stop"  # Dừng script ngay khi gặp lỗi
Start-Transcript -Path $logFile



# --- Cấu hình đầu script ---

# Danh sách các phiên bản Chrome và ID tệp Google Drive
# Bạn sẽ cần nhập ID của các tệp thủ công từ Google Drive
$ChromeVersions = @{
    1 = @{ Name = "google-chrome-135-0-7049-96"  ; ID = "1ydDsvNEk-MUNLpOnsi0Qt5RpY-2dUD1H" }
    2 = @{ Name = "google-chrome-136-0-7103-114"  ; ID = "1d-E1sy7ztydiulYyMJvl7lQx9NCrVIkc" }
    3 = @{ Name = "google-chrome-137-0-7151-120"  ; ID = "13_BfLqye5sVvWZMD6A-QzaCgHjsoWO-6" }
    4 = @{ Name = "google-chrome-138-0-7194-0"    ; ID = "1L1mJpZEq-HeoE6u8-7gJrgOWpuYzJFda" }
    5 = @{ Name = "google-chrome-141-0-7340-0"    ; ID = "1cXO_K7Vy9uIlqPpq9QtMfnOB8AHyjCY7" }
}

# ID của tệp Nekobox trên Google Drive (cập nhật bằng ID thực tế)
$NekoBoxFileID = "1Rs7as6-oHv9IIHAurlgwmc_WigSLYHJb"  # Thay thế ID của tệp Nekobox trong Google Drive

# Đường dẫn tải xuống tệp cài đặt Chrome và Nekobox
$DownloadPathChrome = "$env:USERPROFILE\Downloads\chrome_installer.exe"
$DownloadPathNekoBox = "$env:USERPROFILE\Downloads\nekobox_installer.zip"

# Đường dẫn cài đặt Nekobox
$InstallPath = "$env:ProgramFiles\Nekobox"


# Kiểm tra và cài đặt Python và gdown
function Install-PythonAndGdown {
    # Kiểm tra xem Python đã được cài đặt chưa
    $pythonPath = Get-Command python -ErrorAction SilentlyContinue

    if (-not $pythonPath) {
        Write-Host "Python chưa được cài đặt. Đang cài đặt Python bằng winget..."

        try {
            # Cài đặt Python bằng winget
            Start-Process -FilePath "winget" -ArgumentList "install Python.Python.3.9" -Wait -PassThru -Verb RunAs

            Write-Host "Cài đặt Python xong."

            # Kiểm tra lại Python sau khi cài đặt
            $pythonPath = Get-Command python -ErrorAction SilentlyContinue
            if (-not $pythonPath) {
                Write-Host "Lỗi: Python không thể cài đặt hoặc không có sẵn trong PATH."
                exit
            } else {
                Write-Host "Python đã được cài đặt thành công."
            }
        } catch {
            Write-Host "Lỗi khi cài đặt Python: $_"
            exit
        }
    } else {
        Write-Host "Python đã được cài đặt."
    }

    # Kiểm tra và cài đặt pip
    Write-Host "Đang kiểm tra pip..."
    try {
        python -m ensurepip --upgrade
        Write-Host "pip đã được cài đặt thành công."
    } catch {
        Write-Host "Lỗi khi cài đặt pip: $_"
        exit
    }

    # Cài đặt gdown
    Write-Host "Đang cài đặt gdown..."
    try {
        python -m pip install gdown --quiet
        Write-Host "Cài đặt gdown xong."
    } catch {
        Write-Host "Lỗi khi cài đặt gdown: $_"
        exit
    }
}






# Hàm tải tệp bằng gdown
function Download-With-Gdown {
    param([string]$FileID, [string]$OutputPath)

    # Chạy Python với lệnh gdown từ PowerShell
    $pythonCmd = "python -m gdown https://drive.google.com/uc?id=$FileID -O $OutputPath"
    try {
        Write-Host "Đang tải tệp từ Google Drive bằng gdown..."
        Invoke-Expression $pythonCmd
    } catch {
        Write-Host "Lỗi khi tải tệp bằng gdown: $_"
        exit
    }
}







# --- Cấu hình kết thúc ---

# Hàm kiểm tra quyền quản trị
function Check-AdminRights {
    try {
        function Check-AdminRights {
  $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
  $p  = New-Object System.Security.Principal.WindowsPrincipal($id)
  if (-not $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Bạn cần chạy PowerShell **Run as administrator**."
    exit 1
  }
}

    } catch {
        $IsAdmin = $false
    }

    if (-not $IsAdmin) {
        Write-Host "Lỗi: Bạn cần quyền quản trị để chạy script này. Hãy mở PowerShell với quyền quản trị và thử lại."
        exit
    }
}

# Thay đổi ngôn ngữ hệ thống, múi giờ và thông tin quốc gia
function Set-RegionSettings {
    param([string]$Region)

    try {
        # Thay đổi ngôn ngữ hệ thống
        $Lang = switch($Region) {
            "UK" {"en-GB"}
            "US" {"en-US"}
            "AU" {"en-AU"}
            "SINGAPORE" {"en-SG"}
            "NEWZELAND" {"en-NZ"}
            default {"en-US"}
        }

        # Thay đổi ngôn ngữ hệ thống và vùng
        Set-WinUILanguageOverride -Language $Lang
        Set-WinUserLanguageList $Lang -Force

        # Thay đổi múi giờ
        Set-TimeZone -Id "UTC"

        # Thay đổi đầu vào bàn phím (nếu cần)
        Set-WinDefaultInputMethodOverride -InputTip "0409:00000409" # US Keyboard
    } catch {
        Write-Host "Lỗi: Không thể thay đổi cài đặt khu vực. Chi tiết lỗi: $_"
        exit
    }
}

# Gỡ cài đặt Chrome nếu đã cài đặt
function Uninstall-Chrome {
  Write-Host "Đang gỡ Google Chrome (nếu có)..."
  $paths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
  )
  foreach ($p in $paths) {
    Get-ChildItem $p -ErrorAction SilentlyContinue | ForEach-Object {
      $prop = Get-ItemProperty $_.PsPath -ErrorAction SilentlyContinue
      if ($prop.DisplayName -like "Google Chrome*") {
        $uninst = $prop.UninstallString
        if ($uninst) {
          # Tách file + args an toàn
          $exe,$args = $uninst -split '\.exe"\s*',2
          if ($exe -notmatch '\.exe"$') { $exe = $uninst } else { $exe = $exe + '.exe"' ; $args = $args.Trim() }
          $exe = $exe.Trim('"')
          # Thử tham số silent phổ biến
          $extra = ' --uninstall --multi-install --chrome --force-uninstall'
          Start-Process -FilePath $exe -ArgumentList ($args + $extra) -Wait -ErrorAction Stop
          Write-Host "Đã gỡ Google Chrome."
          return
        }
      }
    }
  }
  Write-Host "Không tìm thấy Chrome để gỡ."
}


# Tải tệp Chrome từ Google Drive
function Download-Chrome {
    param([string]$FileID)

    $DownloadPathChrome = "$env:USERPROFILE\Downloads\chrome_installer.exe"
    Write-Host "Đang tải Chrome từ Google Drive: $DownloadPathChrome"

    # Sử dụng gdown để tải file
    Download-With-Gdown -FileID $FileID -OutputPath $DownloadPathChrome

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
    try {
        Start-Process -FilePath $DownloadPathChrome -ArgumentList "/silent /install" -Wait
        Write-Host "Cài đặt Chrome xong."
    } catch {
        Write-Host "Lỗi khi cài đặt Chrome: $_"
        exit
    }
}

# Khóa cập nhật tự động của Chrome
function Disable-AutoUpdateChrome {
  $k = "HKLM:\SOFTWARE\Policies\Google\Update"
  if (-not (Test-Path $k)) { New-Item $k -Force | Out-Null }
  New-ItemProperty -Path $k -Name "AutoUpdateCheckPeriodMinutes" -Value 0 -PropertyType DWord -Force | Out-Null
  New-ItemProperty -Path $k -Name "UpdateDefault" -Value 0 -PropertyType DWord -Force | Out-Null
  # App GUID của Chrome Stable
  $appKey = Join-Path $k "{8A69D345-D564-463C-AFF1-A69D9E530F96}"
  if (-not (Test-Path $appKey)) { New-Item $appKey -Force | Out-Null }
  New-ItemProperty -Path $appKey -Name "Update" -Value 0 -PropertyType DWord -Force | Out-Null
  Write-Host "Đã cấu hình policy tắt auto-update Chrome."
}


# Tải tệp Nekobox từ Google Drive
function Download-Nekobox {
    param([string]$FileID)

    $DownloadPathNekoBox = "$env:USERPROFILE\Downloads\nekobox_installer.zip"
    Write-Host "Đang tải Nekobox từ Google Drive: $DownloadPathNekoBox"

    # Sử dụng gdown để tải file
    Download-With-Gdown -FileID $FileID -OutputPath $DownloadPathNekoBox

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
    try {
        if (Test-Path $extractPath) {
            Remove-Item -Path $extractPath -Recurse -Force
        }

        # Giải nén tệp
        Expand-Archive -Path $DownloadPathNekoBox -DestinationPath $extractPath
        Write-Host "Đã giải nén Nekobox vào thư mục: $extractPath"
    } catch {
        Write-Host "Lỗi khi giải nén Nekobox: $_"
        exit
    }
}

# Cài đặt Nekobox từ thư mục giải nén
function Install-Nekobox {
    Write-Host "Đang cài đặt Nekobox từ thư mục giải nén..."

    try {
        Start-Process -FilePath "$env:USERPROFILE\Downloads\nekobox\nekobox.exe" -ArgumentList "/silent /install /dir=$InstallPath" -Wait
        Write-Host "Cài đặt Nekobox xong."
    } catch {
        Write-Host "Lỗi khi cài đặt Nekobox: $_"
        exit
    }
}

# Thiết lập Nekobox tự động mở khi khởi động Windows
function Set-AutoStart {
    Write-Host "Đang thiết lập Nekobox tự động mở khi khởi động..."

    try {
        $key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
        $value = "Nekobox"
        $command = "$InstallPath\nekobox.exe"

        Set-ItemProperty -Path $key -Name $value -Value $command
        Write-Host "Nekobox đã được thêm vào danh sách khởi động."
    } catch {
        Write-Host "Lỗi khi thiết lập Nekobox khởi động tự động: $_"
        exit
    }
}

# Pin Nekobox vào Taskbar
function Pin-To-Taskbar {
    Write-Host "Đang pin Nekobox vào Taskbar..."

    try {
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
    } catch {
        Write-Host "Lỗi khi pin Nekobox vào Taskbar: $_"
        exit
    }
}

# Hàm chọn phiên bản Chrome từ danh sách
function Select-ChromeVersion {
    Write-Host "Các phiên bản Google Chrome có sẵn:"

    # Hiển thị các phiên bản và yêu cầu người dùng chọn
    $ChromeVersions.GetEnumerator() | ForEach-Object { 
        Write-Host "$($_.Key): $($_.Value.Name)"
    }

    $validChoice = $false
    while (-not $validChoice) {
        $selectedVersion = Read-Host "Nhập số thứ tự phiên bản bạn muốn tải và cài đặt (1 - 5)"
        
        # Loại bỏ khoảng trắng và chuyển thành số nguyên nếu có thể
        $selectedVersion = $selectedVersion.Trim()

        # Kiểm tra xem giá trị nhập vào có hợp lệ không
        if ($selectedVersion -match '^\d+$' -and $ChromeVersions.ContainsKey([int]$selectedVersion)) {
            $validChoice = $true
            $version = $ChromeVersions[[int]$selectedVersion]
            Write-Host "Bạn đã chọn phiên bản: $($version.Name)"
            return $version.ID
        } else {
            Write-Host "Lựa chọn không hợp lệ. Vui lòng nhập lại một số từ 1 đến 5."
        }
    }
}


# Tải và cài đặt Chrome theo phiên bản người dùng chọn
function Download-And-Install-Chrome {
    $chromeFileID = Select-ChromeVersion

    # Tải tệp Chrome từ Google Drive
    Download-Chrome -FileID $chromeFileID
    Uninstall-Chrome
    Install-Chrome
}

# Kiểm tra quyền quản trị
Check-AdminRights

# Thực hiện thay đổi ngôn ngữ và cài đặt Chrome
Set-RegionSettings -Region "US"

# Tải và cài đặt Chrome
Download-And-Install-Chrome

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
Read-Host "Nhấn Enter để thoát"










