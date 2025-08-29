# ===================================================================
#           ADVANCED FONT FINGERPRINT CHANGER v2.0 - 10/10
# ===================================================================
# Thay đổi Font Metrics + Unicode Glyphs + Script Coverage
# Smart Selection Algorithm for Maximum Impact
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

# COMPREHENSIVE FONT DATABASE
$FontDatabase = @{
    "Western" = @{
        "Inter" = "https://github.com/rsms/inter/releases/download/v3.19/Inter-3.19.zip"
        "JetBrains" = "https://github.com/JetBrains/JetBrainsMono/releases/download/v2.304/JetBrainsMono-2.304.zip"
        "Fira" = "https://github.com/mozilla/Fira/archive/refs/heads/master.zip"
        "Roboto" = "https://github.com/googlefonts/roboto/releases/download/v2.138/roboto-unhinted.zip"
        "SourceCode" = "https://github.com/adobe-fonts/source-code-pro/releases/download/2.038R-ro%2F1.058R-it%2F1.018R-VAR/TTF-source-code-pro-2.038R-ro-1.058R-it.zip"
    }
    "Unicode" = @{
        "NotoSans" = "https://github.com/googlefonts/noto-fonts/releases/download/NotoSans-v2.013/NotoSans-v2.013.zip"
        "NotoEmoji" = "https://github.com/googlefonts/noto-emoji/releases/download/v2.042/NotoColorEmoji.ttf"
        "NotoMath" = "https://github.com/googlefonts/noto-fonts/raw/main/hinted/ttf/NotoSansMath/NotoSansMath-Regular.ttf"
        "NotoSymbols" = "https://github.com/googlefonts/noto-fonts/raw/main/hinted/ttf/NotoSymbols/NotoSymbols-Regular.ttf"
    }
    "CJK" = @{
        "NotoSansCJK" = "https://github.com/googlefonts/noto-cjk/releases/download/Sans2.004/04_NotoSansCJK-OTC.zip"
        "SourceHanSans" = "https://github.com/adobe-fonts/source-han-sans/releases/download/2.004R/SourceHanSans.ttc"
    }
    "Scripts" = @{
        "NotoSansArabic" = "https://github.com/googlefonts/noto-fonts/raw/main/hinted/ttf/NotoSansArabic/NotoSansArabic-Regular.ttf"
        "NotoSansHebrew" = "https://github.com/googlefonts/noto-fonts/raw/main/hinted/ttf/NotoSansHebrew/NotoSansHebrew-Regular.ttf"
        "NotoSansThai" = "https://github.com/googlefonts/noto-fonts/raw/main/hinted/ttf/NotoSansThai/NotoSansThai-Regular.ttf"
        "NotoSansKorean" = "https://github.com/googlefonts/noto-fonts/raw/main/hinted/ttf/NotoSansKR/NotoSansKR-Regular.ttf"
    }
    "Specialty" = @{
        "Inconsolata" = "https://github.com/googlefonts/Inconsolata/releases/download/v3.000/fonts_ttf.zip"
        "FiraCode" = "https://github.com/tonsky/FiraCode/releases/download/6.2/Fira_Code_v6.2.zip"
        "CascadiaCode" = "https://github.com/microsoft/cascadia-code/releases/download/v2111.01/CascadiaCode-2111.01.zip"
        "VictorMono" = "https://github.com/rubjo/victor-mono/releases/download/v1.5.4/VictorMonoAll.zip"
    }
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

function Get-SmartFontSelection {
    param([int]$Count = 5)
    
    $selectedFonts = @()
    
    # Always include 1 Western font
    $westernFonts = @()
    foreach ($font in $FontDatabase["Western"].Keys) {
        $westernFonts += @{
            Name = $font
            Url = $FontDatabase["Western"][$font]
            Category = "Western"
            Impact = "High"
        }
    }
    $selectedFonts += $westernFonts | Get-Random -Count 1
    
    # Always include 1 Unicode font
    $unicodeFonts = @()
    foreach ($font in $FontDatabase["Unicode"].Keys) {
        $unicodeFonts += @{
            Name = $font
            Url = $FontDatabase["Unicode"][$font]
            Category = "Unicode"
            Impact = "Critical"
        }
    }
    $selectedFonts += $unicodeFonts | Get-Random -Count 1
    
    # Include CJK if space available
    if ($Count -ge 3) {
        $cjkFonts = @()
        foreach ($font in $FontDatabase["CJK"].Keys) {
            $cjkFonts += @{
                Name = $font
                Url = $FontDatabase["CJK"][$font]
                Category = "CJK"
                Impact = "Critical"
            }
        }
        if ($cjkFonts.Count -gt 0) {
            $selectedFonts += $cjkFonts | Get-Random -Count 1
        }
    }
    
    # Fill remaining with Scripts and Specialty
    $remainingCount = $Count - $selectedFonts.Count
    if ($remainingCount -gt 0) {
        $allOtherFonts = @()
        
        foreach ($font in $FontDatabase["Scripts"].Keys) {
            $allOtherFonts += @{
                Name = $font
                Url = $FontDatabase["Scripts"][$font]
                Category = "Scripts"
                Impact = "High"
            }
        }
        
        foreach ($font in $FontDatabase["Specialty"].Keys) {
            $allOtherFonts += @{
                Name = $font
                Url = $FontDatabase["Specialty"][$font]
                Category = "Specialty"
                Impact = "Medium"
            }
        }
        
        $availableFonts = $allOtherFonts | Where-Object { $_.Name -notin $selectedFonts.Name }
        if ($availableFonts.Count -gt 0) {
            $selectedFonts += $availableFonts | Get-Random -Count ([Math]::Min($remainingCount, $availableFonts.Count))
        }
    }
    
    return $selectedFonts
}

function Install-Font {
    param([hashtable]$FontInfo)

    try {
        $fontName = $FontInfo.Name
        $url = $FontInfo.Url
        $category = $FontInfo.Category

        Write-Status "[$category] Đang tải font: $fontName" "Yellow"

        # Handle direct TTF files
        if ($url -match "\.ttf$") {
            $ttfPath = "$TempDir\$fontName.ttf"
            $progressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $url -OutFile $ttfPath -UseBasicParsing -TimeoutSec 45

            if (Test-Path $ttfPath -and (Get-Item $ttfPath).Length -gt 1000) {
                return Install-SingleFontFile -FilePath $ttfPath -FontName $fontName
            } else {
                Write-Status "Lỗi tải TTF: $fontName" "Red"
                return 0
            }
        }

        # Handle TTC files
        if ($url -match "\.ttc$") {
            $ttcPath = "$TempDir\$fontName.ttc"
            $progressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $url -OutFile $ttcPath -UseBasicParsing -TimeoutSec 45

            if (Test-Path $ttcPath -and (Get-Item $ttcPath).Length -gt 1000) {
                return Install-SingleFontFile -FilePath $ttcPath -FontName $fontName
            } else {
                Write-Status "Lỗi tải TTC: $fontName" "Red"
                return 0
            }
        }

        # Handle ZIP files
        $zipPath = "$TempDir\$fontName.zip"
        $progressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing -TimeoutSec 45

        if (!(Test-Path $zipPath) -or (Get-Item $zipPath).Length -lt 1000) {
            Write-Status "Lỗi tải ZIP: $fontName" "Red"
            return 0
        }

        # Extract ZIP
        $extractPath = "$TempDir\$fontName"
        if (Test-Path $extractPath) {
            Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue
        }

        try {
            Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
        } catch {
            Write-Status "Lỗi giải nén: $fontName" "Red"
            return 0
        }

        # Find font files
        $fontFiles = Get-ChildItem -Path $extractPath -Recurse -Include "*.ttf", "*.otf", "*.ttc" |
                     Where-Object { $_.Name -notmatch "italic|oblique" } |
                     Sort-Object {
                         if ($_.Name -match "regular|normal") { 0 }
                         elseif ($_.Name -match "medium") { 1 }
                         elseif ($_.Name -match "bold") { 2 }
                         else { 3 }
                     } |
                     Select-Object -First 2

        if ($null -eq $fontFiles -or $fontFiles.Count -eq 0) {
            Write-Status "Không tìm thấy font files: $fontName" "Red"
            return 0
        }

        # Install fonts
        $installed = 0
        foreach ($fontFile in $fontFiles) {
            $result = Install-SingleFontFile -FilePath $fontFile.FullName -FontName $fontFile.BaseName
            $installed += $result
        }

        return $installed
    }
    catch {
        Write-Status "Lỗi cài font $($FontInfo.Name): $($_.Exception.Message)" "Red"
        return 0
    }
}

function Install-SingleFontFile {
    param([string]$FilePath, [string]$FontName)

    try {
        $fontFile = Get-Item $FilePath
        $destPath = "$FontsDir\$($fontFile.Name)"

        if (Test-Path $destPath) {
            Write-Status "Font $FontName đã tồn tại" "Gray"
            return 0
        }

        # Copy file
        Copy-Item -Path $FilePath -Destination $destPath -Force

        # Register in registry
        $fontRegistry = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
        $extension = $fontFile.Extension.ToLower()
        $fontType = if ($extension -eq ".ttf" -or $extension -eq ".ttc") { "TrueType" } else { "OpenType" }
        $fontKey = "$FontName ($fontType)"

        try {
            Set-ItemProperty -Path $fontRegistry -Name $fontKey -Value $fontFile.Name -ErrorAction Stop
        }
        catch {
            New-ItemProperty -Path $fontRegistry -Name $fontKey -Value $fontFile.Name -PropertyType String -Force | Out-Null
        }

        Write-Status "✓ Cài đặt: $FontName" "Green"
        return 1
    }
    catch {
        Write-Status "✗ Lỗi cài $FontName : $($_.Exception.Message)" "Red"
        return 0
    }
}

# ===================================================================
#                         MAIN EXECUTION
# ===================================================================

# Main execution
Clear-Host
Write-Host "=================================================================" -ForegroundColor Green
Write-Host "           ADVANCED FONT FINGERPRINT CHANGER v2.0" -ForegroundColor Yellow
Write-Host "=================================================================" -ForegroundColor Green
Write-Host "🎯 Targeting Font Metrics + Unicode Glyphs + Script Coverage" -ForegroundColor Cyan
Write-Host "🔄 Smart Selection Algorithm for Maximum Impact" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Green

# Show current fonts
$beforeFonts = Get-CurrentFonts
$beforeHash = [System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes(($beforeFonts -join "|")))
$beforeHashStr = [System.BitConverter]::ToString($beforeHash) -replace "-", ""

Write-Status "Font hiện tại: $($beforeFonts.Count)" "Cyan"
Write-Status "Hash hiện tại: $($beforeHashStr.Substring(0,16))..." "Cyan"

# Smart font selection
Write-Host "`n🧠 SMART FONT SELECTION..." -ForegroundColor Yellow
$fontCount = Get-Random -Minimum 4 -Maximum 7
$selectedFonts = Get-SmartFontSelection -Count $fontCount

Write-Host "📋 Fonts được chọn theo chiến lược:" -ForegroundColor Green
$categories = @()
foreach ($font in $selectedFonts) {
    $categories += $font.Category
    $impactColor = switch ($font.Impact) {
        "Critical" { "Red" }
        "High" { "Yellow" }
        "Medium" { "Green" }
        default { "Gray" }
    }
    Write-Host "  [$($font.Category)] $($font.Name) - Impact: $($font.Impact)" -ForegroundColor $impactColor
}

# Install fonts
Write-Host "`n🚀 BẮT ĐẦU CÀI ĐẶT..." -ForegroundColor Yellow
$totalInstalled = 0
$installedFontDetails = @()
$processedCount = 0

foreach ($fontInfo in $selectedFonts) {
    $processedCount++
    Write-Host "`n[$processedCount/$($selectedFonts.Count)] Processing..." -ForegroundColor White

    $installed = Install-Font -FontInfo $fontInfo
    $totalInstalled += $installed

    if ($installed -gt 0) {
        $installedFontDetails += $fontInfo
    }

    Start-Sleep -Seconds 2
}

# Cleanup
Write-Status "Dọn dẹp files tạm..." "Gray"
Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue

# Calculate new fingerprint
$afterFonts = Get-CurrentFonts
$afterHash = [System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes(($afterFonts -join "|")))
$afterHashStr = [System.BitConverter]::ToString($afterHash) -replace "-", ""

# Show results
Write-Host "`n=================================================================" -ForegroundColor Green
Write-Host "                        KẾT QUẢ CHI TIẾT" -ForegroundColor Yellow
Write-Host "=================================================================" -ForegroundColor Green

Write-Host "📊 FONT METRICS IMPACT:" -ForegroundColor Cyan
Write-Host "  Fonts cài đặt: $totalInstalled files" -ForegroundColor Green
Write-Host "  Tổng fonts: $($beforeFonts.Count) → $($afterFonts.Count) (+$($afterFonts.Count - $beforeFonts.Count))" -ForegroundColor Green

Write-Host "`n🔐 FINGERPRINT HASH CHANGE:" -ForegroundColor Cyan
Write-Host "  Trước: $($beforeHashStr.Substring(0,32))..." -ForegroundColor Red
Write-Host "  Sau:   $($afterHashStr.Substring(0,32))..." -ForegroundColor Green
$hashChanged = $beforeHashStr -ne $afterHashStr
Write-Host "  Status: $(if ($hashChanged) { '✅ THAY ĐỔI HOÀN TOÀN' } else { '❌ KHÔNG THAY ĐỔI' })" -ForegroundColor $(if ($hashChanged) { "Green" } else { "Red" })

if ($installedFontDetails.Count -gt 0) {
    Write-Host "`n=== UNICODE COVERAGE IMPACT ===" -ForegroundColor Magenta

    $unicodeImpact = @{
        "Emoji Support" = 0
        "Math Symbols" = 0
        "CJK Characters" = 0
        "Arabic Script" = 0
        "Special Symbols" = 0
    }

    foreach ($font in $installedFontDetails) {
        switch -Regex ($font.Name) {
            "Emoji|Color" { $unicodeImpact["Emoji Support"]++ }
            "Math|Symbol" { $unicodeImpact["Math Symbols"]++ }
            "CJK|Han|Noto.*JP|Noto.*KR|Noto.*SC" { $unicodeImpact["CJK Characters"]++ }
            "Arabic|Noto.*Arabic" { $unicodeImpact["Arabic Script"]++ }
            "Symbol|Music|Noto" { $unicodeImpact["Special Symbols"]++ }
        }
    }

    foreach ($category in $unicodeImpact.Keys) {
        $count = $unicodeImpact[$category]
        $color = if ($count -gt 0) { "Green" } else { "Gray" }
        Write-Host "  $category : $count fonts" -ForegroundColor $color
    }

    $baseScore = [Math]::Min($totalInstalled * 15, 60)
    $diversityBonus = ($categories | Select-Object -Unique).Count * 8
    $score = [Math]::Min($baseScore + $diversityBonus, 100)
    Write-Host "`n🎯 FINGERPRINT IMPACT SCORE: $score/100" -ForegroundColor $(if ($score -ge 80) { "Green" } elseif ($score -ge 60) { "Yellow" } else { "Red" })
}

if ($totalInstalled -gt 0 -and $hashChanged) {
    Write-Host "`n🌐 MỞ TRÌNH DUYỆT ĐỂ KIỂM TRA..." -ForegroundColor Cyan
    Start-Process "https://browserleaks.com/fonts"
    Start-Sleep -Seconds 2
    Start-Process "https://fingerprintjs.com/demo"

    Write-Host "`n=================================================================" -ForegroundColor Green
    Write-Host "🎉 HOÀN THÀNH! Font Fingerprint đã thay đổi hoàn toàn!" -ForegroundColor Yellow
    Write-Host "=================================================================" -ForegroundColor Green
    Write-Host "📋 Hướng dẫn:" -ForegroundColor White
    Write-Host "  1. Restart tất cả trình duyệt (Chrome, Edge, Firefox)" -ForegroundColor White
    Write-Host "  2. Kiểm tra fingerprint tại các trang đã mở" -ForegroundColor White
    Write-Host "  3. Font Metrics và Unicode Glyphs đã thay đổi!" -ForegroundColor White
    Write-Host "=================================================================" -ForegroundColor Green
} else {
    Write-Host "`n❌ KHÔNG CÓ THAY ĐỔI FINGERPRINT" -ForegroundColor Red
    Write-Host "Có thể do fonts đã tồn tại hoặc lỗi cài đặt" -ForegroundColor Yellow
}

Write-Host "`nPress any key to exit..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
