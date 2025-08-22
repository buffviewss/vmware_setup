# Test script đơn giản để kiểm tra Python và gdown
$ErrorActionPreference = "Continue"

Write-Host "=== KIỂM TRA PYTHON VÀ GDOWN ==="

# Tìm Python
$pythonPaths = @(
    "C:\Users\$env:USERNAME\AppData\Local\Programs\Python\Python312\python.exe",
    "C:\Program Files\Python312\python.exe"
)

$pythonExe = $null
foreach ($path in $pythonPaths) {
    if (Test-Path $path) {
        $pythonExe = $path
        Write-Host "✓ Tìm thấy Python: $pythonExe"
        break
    }
}

if (-not $pythonExe) {
    Write-Host "❌ Không tìm thấy Python"
    exit 1
}

# Test Python version
try {
    $version = & $pythonExe --version 2>&1
    Write-Host "Python version: $version"
} catch {
    Write-Host "❌ Lỗi khi kiểm tra Python version: $_"
    exit 1
}

# Test pip
try {
    $pipVersion = & $pythonExe -m pip --version 2>&1
    Write-Host "Pip version: $pipVersion"
} catch {
    Write-Host "❌ Lỗi khi kiểm tra pip: $_"
    exit 1
}

# Test cài đặt gdown
Write-Host "Đang cài đặt gdown..."
try {
    $installResult = & $pythonExe -m pip install gdown 2>&1
    Write-Host "Kết quả cài gdown: $installResult"
} catch {
    Write-Host "❌ Lỗi khi cài gdown: $_"
}

# Test import gdown
Write-Host "Đang test import gdown..."
try {
    $testImport = & $pythonExe -c "import gdown; print('✓ gdown import thành công')" 2>&1
    Write-Host "Kết quả test: $testImport"
} catch {
    Write-Host "❌ Lỗi khi test gdown: $_"
}

# Test download một file nhỏ
Write-Host "Đang test download file nhỏ..."
try {
    $testFile = "$env:TEMP\test_download.txt"
    # Sử dụng file ID của một file test nhỏ (có thể thay đổi)
    $testResult = & $pythonExe -c "import gdown; gdown.download('https://drive.google.com/uc?id=1ydDsvNEk-MUNLpOnsi0Qt5RpY-2dUD1H', '$testFile', quiet=False)" 2>&1
    Write-Host "Kết quả test download: $testResult"
    
    if (Test-Path $testFile) {
        Write-Host "✓ Test download thành công!"
        Remove-Item $testFile -Force
    } else {
        Write-Host "❌ Test download thất bại"
    }
} catch {
    Write-Host "❌ Lỗi khi test download: $_"
}

Write-Host "=== KẾT THÚC TEST ==="
Read-Host "Nhấn Enter để thoát"
