
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



Write-Host "Tất cả các bước đã hoàn thành!"
Read-Host "Nhấn Enter để thoát"
