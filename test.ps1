# Test script chỉ để kiểm tra gdown
Write-Host "=== TEST GDOWN ==="

$pythonExe = "C:\Users\$env:USERNAME\AppData\Local\Programs\Python\Python312\python.exe"

if (-not (Test-Path $pythonExe)) {
    Write-Host "❌ Không tìm thấy Python"
    exit 1
}

Write-Host "✓ Python tìm thấy: $pythonExe"

# Tạo file Python tạm để test
$testPyFile = "$env:TEMP\test_gdown.py"
$pythonCode = @"
try:
    import gdown
    print("SUCCESS: gdown imported successfully")
    
    # Test basic functionality
    print("gdown version:", gdown.__version__ if hasattr(gdown, '__version__') else 'unknown')
    print("SUCCESS: gdown is working")
except ImportError as e:
    print("ERROR: Cannot import gdown -", str(e))
except Exception as e:
    print("ERROR: gdown test failed -", str(e))
"@

Set-Content -Path $testPyFile -Value $pythonCode -Encoding UTF8

# Chạy test
Write-Host "Đang chạy test gdown..."
$testProcess = Start-Process -FilePath $pythonExe -ArgumentList $testPyFile -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\gdown_result.txt" -RedirectStandardError "$env:TEMP\gdown_error.txt"

# Đọc kết quả
$result = Get-Content "$env:TEMP\gdown_result.txt" -Raw -ErrorAction SilentlyContinue
$errorResult = Get-Content "$env:TEMP\gdown_error.txt" -Raw -ErrorAction SilentlyContinue

Write-Host "Exit code: $($testProcess.ExitCode)"
Write-Host "Result: $result"
Write-Host "Error: $errorResult"

if ($result -like "*SUCCESS*") {
    Write-Host "✓ GDOWN HOẠT ĐỘNG THÀNH CÔNG!"
} else {
    Write-Host "❌ GDOWN KHÔNG HOẠT ĐỘNG"
}

# Dọn dẹp
Remove-Item $testPyFile -ErrorAction SilentlyContinue
Remove-Item "$env:TEMP\gdown_result.txt" -ErrorAction SilentlyContinue
Remove-Item "$env:TEMP\gdown_error.txt" -ErrorAction SilentlyContinue

Write-Host "=== KẾT THÚC TEST ==="
Read-Host "Nhấn Enter để thoát"
