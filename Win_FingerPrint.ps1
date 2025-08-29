# ===================================================================
#                    FONT FINGERPRINT CHANGER
# ===================================================================
# Tự động tải và cài đặt font ngẫu nhiên để thay đổi browser fingerprint
# Chạy với quyền Administrator
# ===================================================================

# Check Admin
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "ERROR: Cần chạy với quyền Administrator!" -ForegroundColor Red
    Write-Host "Right-click PowerShell và chọn 'Run as Administrator'" -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

# Variables
$TempDir = "$env:TEMP\FontInstaller"
$FontsDir = "$env:SystemRoot\Fonts"

# Create temp directory
if (!(Test-Path $TempDir)) {
    New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
}

# Font URLs - Working GitHub releases
$FontUrls = @{
    "Inter" = "https://github.com/rsms/inter/releases/download/v3.19/Inter-3.19.zip"
    "JetBrains" = "https://github.com/JetBrains/JetBrainsMono/releases/download/v2.304/JetBrainsMono-2.304.zip"
    "Roboto" = "https://github.com/googlefonts/roboto/releases/download/v2.138/roboto-unhinted.zip"
    "Fira" = "https://github.com/mozilla/Fira/archive/refs/heads/master.zip"
    "SourceCode" = "https://github.com/adobe-fonts/source-code-pro/releases/download/2.038R-ro%2F1.058R-it%2F1.018R-VAR/TTF-source-code-pro-2.038R-ro-1.058R-it.zip"
}

function Write-Status {
    param([string]$Message, [string]$Color = "Cyan")
    $timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "[$timestamp] $Message" -ForegroundColor $Color
}

function Get-CurrentFonts {
    try {
        $fonts = @()
        $fontRegistry = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
        $fontEntries = Get-ItemProperty -Path $fontRegistry -ErrorAction SilentlyContinue

        if ($fontEntries) {
            $fontEntries.PSObject.Properties | ForEach-Object {
                if ($_.Name -notmatch "^PS" -and $_.Name -ne "PSPath" -and $_.Name -ne "PSParentPath" -and $_.Name -ne "PSChildName" -and $_.Name -ne "PSDrive" -and $_.Name -ne "PSProvider") {
                    $fontName = $_.Name -replace " \(TrueType\)$", "" -replace " \(OpenType\)$", ""
                    $fonts += $fontName
                }
            }
        }

        return $fonts | Sort-Object | Select-Object -Unique
    }
    catch {
        return @()
    }
}

function Install-Font {
    param([string]$FontName, [string]$Url)

    try {
        Write-Status "Đang tải font: $FontName" "Yellow"
        $zipPath = "$TempDir\$FontName.zip"

        # Download
        $progressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $Url -OutFile $zipPath -UseBasicParsing -TimeoutSec 30

        if (!(Test-Path $zipPath) -or (Get-Item $zipPath).Length -lt 1000) {
            Write-Status "Lỗi tải font $FontName" "Red"
            return 0
        }

        # Extract
        $extractPath = "$TempDir\$FontName"
        if (Test-Path $extractPath) {
            Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue
        }

        Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

        # Find font files
        $fontFiles = Get-ChildItem -Path $extractPath -Recurse -Include "*.ttf", "*.otf" |
                     Where-Object { $_.Name -notmatch "italic|light|thin|bold" } |
                     Select-Object -First 2

        if ($null -eq $fontFiles -or $fontFiles.Count -eq 0) {
            Write-Status "Không tìm thấy font files cho $FontName" "Red"
            return 0
        }

        # Install fonts
        $installed = 0
        foreach ($fontFile in $fontFiles) {
            $destPath = "$FontsDir\$($fontFile.Name)"

            if (Test-Path $destPath) {
                Write-Status "Font $($fontFile.BaseName) đã tồn tại" "Gray"
                continue
            }

            # Copy file
            Copy-Item -Path $fontFile.FullName -Destination $destPath -Force

            # Register in registry
            $fontRegistry = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
            $fontKey = "$($fontFile.BaseName) (TrueType)"

            try {
                Set-ItemProperty -Path $fontRegistry -Name $fontKey -Value $fontFile.Name
            }
            catch {
                New-ItemProperty -Path $fontRegistry -Name $fontKey -Value $fontFile.Name -PropertyType String -Force | Out-Null
            }

            Write-Status "✓ Cài đặt: $($fontFile.BaseName)" "Green"
            $installed++
        }

        return $installed
    }
    catch {
        Write-Status "Lỗi cài font $FontName : $($_.Exception.Message)" "Red"
        return 0
    }
}

# ===================================================================
#                         MAIN EXECUTION
# ===================================================================

# Main execution
Clear-Host
Write-Host "=================================================================" -ForegroundColor Green
Write-Host "                 FONT FINGERPRINT CHANGER" -ForegroundColor Yellow
Write-Host "=================================================================" -ForegroundColor Green

# Show current fonts
$beforeFonts = Get-CurrentFonts
Write-Status "Font hiện tại: $($beforeFonts.Count)" "Cyan"

# Install random fonts
$selectedFonts = $FontUrls.Keys | Get-Random -Count 2
$totalInstalled = 0

Write-Host "`nBắt đầu cài đặt font..." -ForegroundColor Yellow
foreach ($fontName in $selectedFonts) {
    $installed = Install-Font -FontName $fontName -Url $FontUrls[$fontName]
    $totalInstalled += $installed
    Start-Sleep -Seconds 1
}

# Cleanup
Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue

# Show results
$afterFonts = Get-CurrentFonts
Write-Host "`n=== KẾT QUẢ ===" -ForegroundColor Green
Write-Host "✓ Đã cài đặt: $totalInstalled font files" -ForegroundColor Green
Write-Host "✓ Tổng font: $($beforeFonts.Count) → $($afterFonts.Count)" -ForegroundColor Green

if ($totalInstalled -gt 0) {
    Write-Host "✓ Font fingerprint đã thay đổi!" -ForegroundColor Yellow

    # Open browser
    Write-Host "`nMở trình duyệt để kiểm tra..." -ForegroundColor Cyan
    Start-Process "https://browserleaks.com/fonts"

    Write-Host "`n=================================================================" -ForegroundColor Green
    Write-Host "HOÀN THÀNH! Restart browser và kiểm tra fingerprint" -ForegroundColor Yellow
    Write-Host "=================================================================" -ForegroundColor Green
} else {
    Write-Host "Không có font nào được cài đặt mới" -ForegroundColor Red
}

Write-Host "`nPress any key to exit..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
