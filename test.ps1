# Test script đơn giản để kiểm tra Python và gdown
Write-Host "=== KIỂM TRA PYTHON VÀ GDOWN ==="

# Tìm Python
$pythonExe = "C:\Users\$env:USERNAME\AppData\Local\Programs\Python\Python312\python.exe"

if (Test-Path $pythonExe) {
    Write-Host "✓ Tìm thấy Python: $pythonExe"
} else {
    Write-Host "❌ Không tìm thấy Python tại: $pythonExe"
    exit 1
}

# Test Python version
Write-Host "Đang kiểm tra Python version..."
$versionProcess = Start-Process -FilePath $pythonExe -ArgumentList "--version" -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\python_version.txt" -RedirectStandardError "$env:TEMP\python_version_error.txt"

if ($versionProcess.ExitCode -eq 0) {
    $version = Get-Content "$env:TEMP\python_version.txt" -Raw
    Write-Host "✓ Python version: $version"
} else {
    Write-Host "❌ Lỗi khi kiểm tra Python version"
    exit 1
}

# Test pip
Write-Host "Đang kiểm tra pip..."
$pipProcess = Start-Process -FilePath $pythonExe -ArgumentList "-m", "pip", "--version" -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\pip_version.txt" -RedirectStandardError "$env:TEMP\pip_version_error.txt"

if ($pipProcess.ExitCode -eq 0) {
    $pipVersion = Get-Content "$env:TEMP\pip_version.txt" -Raw
    Write-Host "✓ Pip version: $pipVersion"
} else {
    Write-Host "❌ Lỗi khi kiểm tra pip"
    exit 1
}

# Cài đặt gdown
Write-Host "Đang cài đặt gdown..."
$gdownProcess = Start-Process -FilePath $pythonExe -ArgumentList "-m", "pip", "install", "gdown" -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\gdown_install.txt" -RedirectStandardError "$env:TEMP\gdown_install_error.txt"

$gdownOutput = Get-Content "$env:TEMP\gdown_install.txt" -Raw -ErrorAction SilentlyContinue
$gdownError = Get-Content "$env:TEMP\gdown_install_error.txt" -Raw -ErrorAction SilentlyContinue

Write-Host "Gdown install output: $gdownOutput"
Write-Host "Gdown install error: $gdownError"
Write-Host "Gdown install exit code: $($gdownProcess.ExitCode)"

# Test import gdown
Write-Host "Đang test import gdown..."
$testProcess = Start-Process -FilePath $pythonExe -ArgumentList "-c", "import gdown; print('gdown OK')" -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\gdown_test.txt" -RedirectStandardError "$env:TEMP\gdown_test_error.txt"

if ($testProcess.ExitCode -eq 0) {
    $testOutput = Get-Content "$env:TEMP\gdown_test.txt" -Raw
    Write-Host "✓ Test import thành công: $testOutput"
} else {
    Write-Host "❌ Test import thất bại"
    $testError = Get-Content "$env:TEMP\gdown_test_error.txt" -Raw -ErrorAction SilentlyContinue
    Write-Host "Test error: $testError"
}

Write-Host "=== KẾT THÚC TEST ==="
Read-Host "Nhấn Enter để thoát"
