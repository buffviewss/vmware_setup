# --- LOGGING ---
$logFile = "$env:USERPROFILE\Downloads\script_log.txt"
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true  # (PS7+) để lệnh native tôn trọng ErrorAction
Start-Transcript -Path $logFile

# --- HÀM CÀI ĐẶT ---
function Install-PythonAndGdown {
    Write-Host "=== Bắt đầu kiểm tra/cài đặt Python & gdown ==="

    # Kiểm tra winget
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "Không tìm thấy winget. Hãy cập nhật Microsoft Store App Installer hoặc cài thủ công Python."
    }

    # 1) Kiểm tra Python (ưu tiên 'python', fallback 'py')
    $pythonCmd = if (Get-Command python -ErrorAction SilentlyContinue) { "python" }
                 elseif (Get-Command py -ErrorAction SilentlyContinue) { "py -3" }
                 else { $null }

    if (-not $pythonCmd) {
        Write-Host "Python chưa có. Đang cài đặt bằng winget..."
        # Có thể đổi sang phiên bản khác nếu muốn
        Start-Process -FilePath "winget" -ArgumentList "install -e --id Python.Python.3.11" -Wait -Verb RunAs
        # Kiểm tra lại
        $pythonCmd = if (Get-Command python -ErrorAction SilentlyContinue) { "python" }
                     elseif (Get-Command py -ErrorAction SilentlyContinue) { "py -3" }
                     else { $null }
        if (-not $pythonCmd) { throw "Cài đặt Python thất bại hoặc chưa vào PATH." }
        Write-Host "Python đã được cài đặt."
    } else {
        Write-Host "Đã phát hiện Python sẵn có."
    }

    # 2) Đảm bảo pip
    Write-Host "Đang kiểm tra pip..."
    & $pythonCmd -m ensurepip --upgrade
    Write-Host "pip OK."

    # 3) Cài gdown
    Write-Host "Đang cài đặt/ cập nhật gdown..."
    & $pythonCmd -m pip install --upgrade gdown --quiet
    Write-Host "gdown OK."

    # 4) Xác minh
    $pyVer = (& $pythonCmd --version)
    $pipVer = (& $pythonCmd -m pip --version)
    $gdownVer = (& $pythonCmd -m pip show gdown | Select-String -Pattern "^Version:" | ForEach-Object {$_.ToString()})

    Write-Host "Python: $pyVer"
    Write-Host "pip: $pipVer"
    Write-Host "gdown $gdownVer"
    Write-Host "=== Hoàn tất cài đặt ==="
}

# --- MAIN ---
try {
    Install-PythonAndGdown
    Write-Host "Tất cả các bước đã hoàn thành!"
} catch {
    Write-Host "Có lỗi xảy ra: $($_.Exception.Message)"
} finally {
    Stop-Transcript | Out-Null
}

Read-Host "Nhấn Enter để thoát"
