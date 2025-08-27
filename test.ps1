# ===================================================================
# Windows Setup Script - All-in-One Edition
# Chrome + Python + Nekobox Auto Installer
# Single file with clean architecture and comprehensive functionality
# Compatible with PowerShell 5.x and Windows 10/11
# ===================================================================

#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [ValidateSet("US", "UK", "AU", "SG", "NZ", "Interactive")]
    [string]$Region = "Interactive",
    
    [switch]$SkipPython,
    [switch]$SkipChrome, 
    [switch]$SkipNekobox,
    [switch]$Silent,
    [switch]$Test,
    [switch]$TestGDrive,
    [switch]$Benchmark
)

# ===================================================================
# CONFIGURATION & CONSTANTS
# ===================================================================

# Script configuration
$script:Config = @{
    Version = "2.0.0"
    ErrorActionPreference = "Continue"
    LogFile = "$env:USERPROFILE\Downloads\Winsetup_Log.txt"
    TempDir = $env:TEMP
    UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
}

# Google Drive file IDs - Centralized configuration
$script:GoogleDriveFiles = @{
    Chrome = @{
        "Chrome 135.0.7049.96"   = "1ydDsvNEk-MUNLpOnsi0Qt5RpY-2dUD1H"
        "Chrome 136.0.7103.114"  = "1d-E1sy7ztydiulYyMJvl7lQx9NCrVIkc"
        "Chrome 137.0.7151.120"  = "13_BfLqye5sVvWZMD6A-QzaCgHjsoWO-6"
        "Chrome 138.0.7194.0"    = "1L1mJpZEq-HeoE6u8-7gJrgOWpuYzJFda"
        "Chrome 141.0.7340.0"    = "1cXO_K7Vy9uIlqPpq9QtMfnOB8AHyjCY7"
    }
    Nekobox = "1Rs7as6-oHv9IIHAurlgwmc_WigSLYHJb"
}

# Application configurations
$script:Apps = @{
    Python = @{
        Version = "3.12.0"
        URL = "https://www.python.org/ftp/python/3.12.0/python-3.12.0-amd64.exe"
        InstallArgs = "/quiet InstallAllUsers=1 PrependPath=1 Include_test=0"
    }
    Chrome = @{
        Versions = @(
            @{ Name = "Chrome 135.0.7049.96"; ID = $script:GoogleDriveFiles.Chrome["Chrome 135.0.7049.96"] }
            @{ Name = "Chrome 136.0.7103.114"; ID = $script:GoogleDriveFiles.Chrome["Chrome 136.0.7103.114"] }
            @{ Name = "Chrome 137.0.7151.120"; ID = $script:GoogleDriveFiles.Chrome["Chrome 137.0.7151.120"] }
            @{ Name = "Chrome 138.0.7194.0"; ID = $script:GoogleDriveFiles.Chrome["Chrome 138.0.7194.0"] }
            @{ Name = "Chrome 141.0.7340.0"; ID = $script:GoogleDriveFiles.Chrome["Chrome 141.0.7340.0"] }
        )
        FallbackURL = "https://dl.google.com/chrome/install/latest/chrome_installer.exe"
        InstallArgs = "/silent /install"
    }
    Nekobox = @{
        GoogleDriveID = $script:GoogleDriveFiles.Nekobox
        GitHubURL = "https://github.com/MatsuriDayo/nekoray/releases/latest/download/nekoray-3.26-2023-12-09-windows64.zip"
        InstallPath = "$env:ProgramFiles\Nekobox"
    }
}

# Region configurations
$script:Regions = @{
    "US" = @{ Language = "en-US"; DisplayName = "United States" }
    "UK" = @{ Language = "en-GB"; DisplayName = "United Kingdom" }
    "AU" = @{ Language = "en-AU"; DisplayName = "Australia" }
    "SG" = @{ Language = "en-SG"; DisplayName = "Singapore" }
    "NZ" = @{ Language = "en-NZ"; DisplayName = "New Zealand" }
}

# ===================================================================
# CORE UTILITY FUNCTIONS
# ===================================================================

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [ValidateSet("Info", "Success", "Warning", "Error")]
        [string]$Level = "Info"
    )
    
    $colors = @{
        "Info" = "White"
        "Success" = "Green" 
        "Warning" = "Yellow"
        "Error" = "Red"
    }
    
    $prefixes = @{
        "Info" = "[i]"
        "Success" = "[+]"
        "Warning" = "[*]"
        "Error" = "[!]"
    }
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp $($prefixes[$Level]) $Message"
    
    Write-Host "$($prefixes[$Level]) $Message" -ForegroundColor $colors[$Level]
    
    # Write to log file if transcript is active
    try {
        Add-Content -Path $script:Config.LogFile -Value $logMessage -ErrorAction SilentlyContinue
    } catch {
        # Ignore logging errors
    }
}

function Test-Prerequisites {
    [CmdletBinding()]
    param()
    
    Write-Log "Checking prerequisites..." "Info"
    
    # Check admin rights
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Log "Administrator rights required. Please run as Administrator." "Error"
        throw "Administrator rights required"
    }
    Write-Log "Administrator rights confirmed" "Success"
    
    # Check PowerShell version
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        Write-Log "PowerShell 5.0 or higher required" "Error"
        throw "PowerShell version not supported"
    }
    Write-Log "PowerShell version: $($PSVersionTable.PSVersion)" "Success"
    
    # Check internet connectivity
    try {
        $null = Test-NetConnection -ComputerName "8.8.8.8" -Port 53 -InformationLevel Quiet -ErrorAction Stop
        Write-Log "Internet connectivity confirmed" "Success"
    } catch {
        Write-Log "Internet connectivity required" "Warning"
    }
}

function Initialize-Logging {
    [CmdletBinding()]
    param()
    
    try {
        Start-Transcript -Path $script:Config.LogFile -Append -ErrorAction SilentlyContinue
        Write-Log "Logging initialized: $($script:Config.LogFile)" "Info"
        Write-Log "Winsetup v$($script:Config.Version) started" "Info"
    } catch {
        Write-Log "Could not initialize logging" "Warning"
    }
}

function Stop-Logging {
    [CmdletBinding()]
    param()
    
    try {
        Write-Log "Winsetup v$($script:Config.Version) completed" "Info"
        Stop-Transcript -ErrorAction SilentlyContinue
    } catch {
        # Ignore errors
    }
}

# ===================================================================
# DOWNLOAD ENGINE CLASS
# ===================================================================

class DownloadEngine {
    [string]$UserAgent
    [string]$TempDirectory
    
    DownloadEngine([string]$userAgent, [string]$tempDir) {
        $this.UserAgent = $userAgent
        $this.TempDirectory = $tempDir
    }
    
    [bool] DownloadFile([string]$url, [string]$outputPath) {
        try {
            Write-Log "Downloading: $url" "Info"
            $webClient = New-Object System.Net.WebClient
            $webClient.Headers.Add("User-Agent", $this.UserAgent)
            $webClient.DownloadFile($url, $outputPath)
            $webClient.Dispose()
            
            return (Test-Path -Path $outputPath)
        } catch {
            Write-Log "Download failed: $($_.Exception.Message)" "Warning"
            return $false
        }
    }
    
    [bool] DownloadGoogleDriveFile([string]$fileId, [string]$outputPath) {
        Write-Log "Downloading from Google Drive ID: $fileId" "Info"
        
        # Ensure Python and gdown are available
        if (-not $this.EnsureGdown()) {
            Write-Log "gdown not available, falling back to direct download" "Warning"
            return $this.DownloadGoogleDriveDirect($fileId, $outputPath)
        }
        
        # Convert path for Python compatibility
        $pythonPath = $outputPath.Replace('\', '/')
        
        # Try gdown methods
        $methods = @(
            "import gdown; gdown.download(id='$fileId', output='$pythonPath', quiet=False, fuzzy=True)",
            "import gdown; gdown.download('https://drive.google.com/uc?id=$fileId', '$pythonPath', quiet=False)",
            "import gdown; gdown.download('$fileId', '$pythonPath', quiet=False)"
        )
        
        foreach ($method in $methods) {
            try {
                Write-Log "Trying gdown method..." "Info"
                python -c $method 2>&1 | Out-Null
                
                if ((Test-Path -Path $outputPath) -and (Get-Item -Path $outputPath).Length -gt 10240) {
                    $fileSize = (Get-Item -Path $outputPath).Length
                    Write-Log "gdown download successful: $([math]::Round($fileSize/1MB, 2)) MB" "Success"
                    return $true
                }
            } catch {
                Write-Log "gdown method failed: $($_.Exception.Message)" "Warning"
            }
        }
        
        # Fallback to direct download
        return $this.DownloadGoogleDriveDirect($fileId, $outputPath)
    }
    
    [bool] EnsureGdown() {
        try {
            python -c "import gdown" 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Log "gdown is available" "Success"
                return $true
            }
            
            Write-Log "Installing gdown..." "Info"
            python -m pip install gdown --quiet 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Log "gdown installed successfully" "Success"
                return $true
            } else {
                Write-Log "Failed to install gdown" "Error"
                return $false
            }
        } catch {
            Write-Log "Python not available" "Error"
            return $false
        }
    }
    
    [bool] DownloadGoogleDriveDirect([string]$fileId, [string]$outputPath) {
        Write-Log "Trying direct Google Drive download..." "Info"
        
        $urls = @(
            "https://drive.google.com/uc?export=download&id=$fileId",
            "https://drive.google.com/uc?id=$fileId&export=download"
        )
        
        foreach ($url in $urls) {
            if ($this.DownloadFile($url, $outputPath)) {
                # Check if we got HTML instead of the actual file
                $firstLine = Get-Content -Path $outputPath -TotalCount 1 -ErrorAction SilentlyContinue
                if ($firstLine -notlike "*html*" -and $firstLine -notlike "*DOCTYPE*") {
                    $fileSize = (Get-Item -Path $outputPath).Length
                    Write-Log "Direct download successful: $([math]::Round($fileSize/1MB, 2)) MB" "Success"
                    return $true
                }
                Write-Log "Got HTML error page, trying next URL..." "Warning"
                Remove-Item -Path $outputPath -Force -ErrorAction SilentlyContinue
            }
        }
        
        return $false
    }
    
    [bool] ValidateDownload([string]$filePath, [int]$minSizeKB = 1) {
        if (-not (Test-Path -Path $filePath)) {
            return $false
        }
        
        $fileSize = (Get-Item -Path $filePath).Length
        return ($fileSize -gt ($minSizeKB * 1024))
    }
}

# ===================================================================
# REGION SELECTION
# ===================================================================

function Select-UserRegion {
    [CmdletBinding()]
    param()
    
    if ($Region -ne "Interactive") {
        Write-Log "Region pre-selected: $Region" "Info"
        return $Region
    }
    
    if ($Silent) {
        Write-Log "Silent mode: Using default region US" "Info"
        return "US"
    }
    
    Write-Host ""
    Write-Host "=== Region Selection ===" -ForegroundColor Yellow
    Write-Host "Please select your region:" -ForegroundColor Cyan
    Write-Host ""
    
    $regionOptions = @()
    $counter = 1
    foreach ($key in $script:Regions.Keys | Sort-Object) {
        $displayName = $script:Regions[$key].DisplayName
        Write-Host "$counter. $displayName ($key)" -ForegroundColor White
        $regionOptions += $key
        $counter++
    }
    Write-Host ""
    
    do {
        $selection = Read-Host "Select region (1-$($regionOptions.Count))"
        $selectionInt = 0
        
        if ([int]::TryParse($selection, [ref]$selectionInt) -and 
            $selectionInt -ge 1 -and $selectionInt -le $regionOptions.Count) {
            $selectedRegion = $regionOptions[$selectionInt - 1]
            Write-Log "Selected region: $selectedRegion" "Success"
            return $selectedRegion
        } else {
            Write-Log "Invalid selection. Please choose 1-$($regionOptions.Count)." "Error"
        }
    } while ($true)
}

# ===================================================================
# INSTALLATION FUNCTIONS
# ===================================================================

function Install-Python {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [DownloadEngine]$Downloader
    )

    Write-Log "=== Installing Python ===" "Info"

    # Check if Python is already installed
    try {
        $pythonVersion = python --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Python already installed: $pythonVersion" "Success"

            # Ensure gdown is available
            if (-not $Downloader.EnsureGdown()) {
                Write-Log "Failed to install gdown" "Warning"
            } else {
                Write-Log "gdown is available" "Success"
            }
            return
        }
    } catch {
        # Python not found, continue with installation
    }

    Write-Log "Python not found. Installing Python $($script:Apps.Python.Version)..." "Info"

    $installerPath = Join-Path $script:Config.TempDir "python_installer.exe"

    # Download Python installer
    if (-not $Downloader.DownloadFile($script:Apps.Python.URL, $installerPath)) {
        throw "Failed to download Python installer"
    }

    if (-not $Downloader.ValidateDownload($installerPath, 1024)) {
        throw "Python installer download is invalid"
    }

    Write-Log "Installing Python..." "Info"

    # Install Python
    $process = Start-Process -FilePath $installerPath -ArgumentList $script:Apps.Python.InstallArgs -Wait -PassThru

    if ($process.ExitCode -ne 0) {
        throw "Python installation failed with exit code: $($process.ExitCode)"
    }

    # Clean up installer
    Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue

    # Refresh environment variables
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

    # Verify installation
    try {
        $pythonVersion = python --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Python installed successfully: $pythonVersion" "Success"

            # Install gdown
            if (-not $Downloader.EnsureGdown()) {
                Write-Log "Failed to install gdown" "Warning"
            } else {
                Write-Log "gdown installed successfully" "Success"
            }
        } else {
            throw "Python verification failed"
        }
    } catch {
        throw "Python installation verification failed"
    }
}

function Set-SystemRegion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Region
    )

    Write-Log "=== Configuring System Region ===" "Info"

    if (-not $script:Regions.ContainsKey($Region)) {
        Write-Log "Invalid region: $Region" "Error"
        return
    }

    $regionConfig = $script:Regions[$Region]
    $languageCode = $regionConfig.Language

    try {
        Write-Log "Setting system language to: $languageCode" "Info"

        # Set system language and region
        Set-WinUILanguageOverride -Language $languageCode -ErrorAction SilentlyContinue
        Set-WinUserLanguageList $languageCode -Force -ErrorAction SilentlyContinue

        # Set timezone to UTC
        Write-Log "Setting timezone to UTC" "Info"
        Set-TimeZone -Id "UTC" -ErrorAction SilentlyContinue

        # Set keyboard layout to US
        Write-Log "Setting keyboard layout to US" "Info"
        Set-WinDefaultInputMethodOverride -InputTip "0409:00000409" -ErrorAction SilentlyContinue

        Write-Log "System region configured successfully for $($regionConfig.DisplayName)" "Success"
    } catch {
        Write-Log "Failed to configure system region: $($_.Exception.Message)" "Warning"
    }
}

function Install-Chrome {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [DownloadEngine]$Downloader
    )

    Write-Log "=== Installing Chrome ===" "Info"

    # Check if Chrome is already installed
    $chromeInstalled = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
                      Where-Object { $_.DisplayName -like "*Google Chrome*" }

    if ($chromeInstalled) {
        Write-Log "Chrome already installed: $($chromeInstalled.DisplayVersion)" "Success"
        return
    }

    $installerPath = Join-Path $script:Config.TempDir "chrome_installer.exe"
    $downloadSuccess = $false

    # Try Chrome versions from Google Drive
    foreach ($version in $script:Apps.Chrome.Versions) {
        Write-Log "Trying Chrome version: $($version.Name)" "Info"

        if ($Downloader.DownloadGoogleDriveFile($version.ID, $installerPath)) {
            if ($Downloader.ValidateDownload($installerPath, 1024)) {
                Write-Log "Downloaded Chrome installer: $($version.Name)" "Success"
                $downloadSuccess = $true
                break
            }
        }

        # Clean up failed download
        Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue
    }

    # Fallback to official Chrome download
    if (-not $downloadSuccess) {
        Write-Log "Trying official Chrome download..." "Info"
        if ($Downloader.DownloadFile($script:Apps.Chrome.FallbackURL, $installerPath)) {
            if ($Downloader.ValidateDownload($installerPath, 1024)) {
                Write-Log "Downloaded Chrome from official source" "Success"
                $downloadSuccess = $true
            }
        }
    }

    if (-not $downloadSuccess) {
        throw "Failed to download Chrome installer from any source"
    }

    Write-Log "Installing Chrome..." "Info"

    # Install Chrome
    $process = Start-Process -FilePath $installerPath -ArgumentList $script:Apps.Chrome.InstallArgs -Wait -PassThru

    if ($process.ExitCode -ne 0) {
        Write-Log "Chrome installation may have issues (exit code: $($process.ExitCode))" "Warning"
    }

    # Clean up installer
    Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue

    # Disable Chrome auto-update
    try {
        $policyPath = "HKLM:\SOFTWARE\Policies\Google\Update"
        if (-not (Test-Path -Path $policyPath)) {
            New-Item -Path $policyPath -Force | Out-Null
        }
        New-ItemProperty -Path $policyPath -Name "UpdateDefault" -Value 0 -PropertyType DWord -Force | Out-Null
        Write-Log "Chrome auto-update disabled" "Success"
    } catch {
        Write-Log "Could not disable Chrome auto-update" "Warning"
    }

    Write-Log "Chrome installation completed" "Success"
}

function Install-Nekobox {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [DownloadEngine]$Downloader
    )

    Write-Log "=== Installing Nekobox ===" "Info"

    # Check if Nekobox is already installed
    if (Test-Path -Path $script:Apps.Nekobox.InstallPath) {
        $existingFiles = Get-ChildItem -Path $script:Apps.Nekobox.InstallPath -Filter "*.exe" -ErrorAction SilentlyContinue
        if ($existingFiles.Count -gt 0) {
            Write-Log "Nekobox already installed at: $($script:Apps.Nekobox.InstallPath)" "Success"
            return
        }
    }

    $zipPath = Join-Path $script:Config.TempDir "nekobox.zip"
    $extractPath = Join-Path $script:Config.TempDir "nekobox_extract"
    $downloadSuccess = $false

    # Try Google Drive download
    Write-Log "Downloading Nekobox from Google Drive..." "Info"
    if ($Downloader.DownloadGoogleDriveFile($script:Apps.Nekobox.GoogleDriveID, $zipPath)) {
        if ($Downloader.ValidateDownload($zipPath, 1024)) {
            Write-Log "Downloaded Nekobox from Google Drive" "Success"
            $downloadSuccess = $true
        }
    }

    # Fallback to GitHub
    if (-not $downloadSuccess) {
        Write-Log "Trying GitHub download..." "Info"
        if ($Downloader.DownloadFile($script:Apps.Nekobox.GitHubURL, $zipPath)) {
            if ($Downloader.ValidateDownload($zipPath, 1024)) {
                Write-Log "Downloaded Nekobox from GitHub" "Success"
                $downloadSuccess = $true
            }
        }
    }

    if (-not $downloadSuccess) {
        if ($Silent) {
            Write-Log "Nekobox download failed in silent mode. Skipping..." "Warning"
            return
        } else {
            throw "Failed to download Nekobox from all sources"
        }
    }

    # Extract ZIP file
    Write-Log "Extracting Nekobox..." "Info"

    try {
        # Remove existing extract directory
        if (Test-Path -Path $extractPath) {
            Remove-Item -Path $extractPath -Recurse -Force
        }

        # Extract using .NET
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $extractPath)

        # Verify extraction
        $extractedFiles = Get-ChildItem -Path $extractPath -Recurse -Filter "*.exe"
        if ($extractedFiles.Count -eq 0) {
            throw "No executable files found in extracted archive"
        }

        Write-Log "Extracted $($extractedFiles.Count) executable files" "Success"

        # Create installation directory
        if (-not (Test-Path -Path $script:Apps.Nekobox.InstallPath)) {
            New-Item -ItemType Directory -Path $script:Apps.Nekobox.InstallPath -Force | Out-Null
        }

        # Copy files to installation directory
        $sourceDir = Get-ChildItem -Path $extractPath -Directory | Select-Object -First 1
        if ($sourceDir) {
            Copy-Item -Path "$($sourceDir.FullName)\*" -Destination $script:Apps.Nekobox.InstallPath -Recurse -Force
        } else {
            Copy-Item -Path "$extractPath\*" -Destination $script:Apps.Nekobox.InstallPath -Recurse -Force
        }

        Write-Log "Nekobox installed to: $($script:Apps.Nekobox.InstallPath)" "Success"

        # Clean up
        Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $extractPath -Recurse -Force -ErrorAction SilentlyContinue

    } catch {
        Write-Log "Failed to extract/install Nekobox: $($_.Exception.Message)" "Error"

        # Clean up on failure
        Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $extractPath -Recurse -Force -ErrorAction SilentlyContinue

        if (-not $Silent) {
            throw "Nekobox installation failed"
        }
    }
}

# ===================================================================
# TESTING FUNCTIONS
# ===================================================================

function Invoke-SystemTest {
    [CmdletBinding()]
    param()

    Write-Host "=== System Installation Test ===" -ForegroundColor Yellow
    Write-Host ""

    $testResults = @()

    # Test Python
    try {
        $pythonVersion = python --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Python: $pythonVersion" "Success"
            $testResults += "Python: PASS"
        } else {
            Write-Log "Python: Not installed" "Error"
            $testResults += "Python: FAIL"
        }
    } catch {
        Write-Log "Python: Not installed" "Error"
        $testResults += "Python: FAIL"
    }

    # Test Chrome
    $chromeInstalled = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
                      Where-Object { $_.DisplayName -like "*Google Chrome*" }

    if ($chromeInstalled) {
        Write-Log "Chrome: Installed ($($chromeInstalled.DisplayVersion))" "Success"
        $testResults += "Chrome: PASS"
    } else {
        Write-Log "Chrome: Not installed" "Error"
        $testResults += "Chrome: FAIL"
    }

    # Test Nekobox
    if (Test-Path -Path $script:Apps.Nekobox.InstallPath) {
        $nekoboxFiles = Get-ChildItem -Path $script:Apps.Nekobox.InstallPath -Filter "*.exe" -ErrorAction SilentlyContinue
        if ($nekoboxFiles.Count -gt 0) {
            Write-Log "Nekobox: Installed ($($nekoboxFiles.Count) executables)" "Success"
            $testResults += "Nekobox: PASS"
        } else {
            Write-Log "Nekobox: Directory exists but no executables found" "Error"
            $testResults += "Nekobox: FAIL"
        }
    } else {
        Write-Log "Nekobox: Not installed" "Error"
        $testResults += "Nekobox: FAIL"
    }

    # Summary
    Write-Host ""
    Write-Host "=== Test Results ===" -ForegroundColor Yellow
    $passCount = ($testResults | Where-Object { $_ -like "*PASS*" }).Count
    $failCount = ($testResults | Where-Object { $_ -like "*FAIL*" }).Count

    Write-Host "Passed: $passCount" -ForegroundColor Green
    Write-Host "Failed: $failCount" -ForegroundColor Red

    if ($failCount -eq 0) {
        Write-Log "All tests passed!" "Success"
    } else {
        Write-Log "Some components need attention" "Warning"
    }
}

function Test-GoogleDriveAccess {
    [CmdletBinding()]
    param()

    Write-Host "=== Testing Google Drive Access ===" -ForegroundColor Yellow
    Write-Host ""

    $downloader = [DownloadEngine]::new($script:Config.UserAgent, $script:Config.TempDir)
    $testPath = Join-Path $script:Config.TempDir "gdrive_test.tmp"

    Write-Log "Testing Nekobox file ID: $($script:Apps.Nekobox.GoogleDriveID)" "Info"

    # Test Python availability
    try {
        $pythonVersion = python --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Python available: $pythonVersion" "Success"
        } else {
            Write-Log "Python not available" "Error"
            return
        }
    } catch {
        Write-Log "Python not available" "Error"
        return
    }

    # Test gdown availability
    if (-not $downloader.EnsureGdown()) {
        Write-Log "gdown not available and could not be installed" "Error"
        return
    }

    # Test download
    if ($downloader.DownloadGoogleDriveFile($script:Apps.Nekobox.GoogleDriveID, $testPath)) {
        $fileSize = (Get-Item -Path $testPath).Length
        Write-Log "Test PASSED: Downloaded $([math]::Round($fileSize/1MB, 2)) MB successfully" "Success"
        Write-Log "File validation: PASS" "Success"

        # Clean up
        Remove-Item -Path $testPath -Force -ErrorAction SilentlyContinue
        Write-Log "Test file cleaned up" "Info"
    } else {
        Write-Log "Test FAILED: Could not download file" "Error"
        Write-Log "Check file permissions: https://drive.google.com/file/d/$($script:Apps.Nekobox.GoogleDriveID)/view" "Info"
    }
}

function Invoke-Benchmark {
    [CmdletBinding()]
    param()

    Write-Host "=== Performance Benchmark ===" -ForegroundColor Yellow
    Write-Host ""

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $startMemory = [System.GC]::GetTotalMemory($false)

    try {
        # Run Google Drive test as benchmark
        Test-GoogleDriveAccess

        $stopwatch.Stop()
        $endMemory = [System.GC]::GetTotalMemory($false)

        Write-Host ""
        Write-Host "=== Benchmark Results ===" -ForegroundColor Green
        Write-Host "Execution Time: $($stopwatch.Elapsed.TotalSeconds) seconds" -ForegroundColor White
        Write-Host "Memory Used: $([math]::Round(($endMemory - $startMemory) / 1MB, 2)) MB" -ForegroundColor White
        Write-Host "Script Version: $($script:Config.Version)" -ForegroundColor White

        # Code metrics
        $scriptPath = $MyInvocation.ScriptName
        if ($scriptPath -and (Test-Path $scriptPath)) {
            $content = Get-Content $scriptPath
            $totalLines = $content.Count
            $codeLines = ($content | Where-Object { $_ -notmatch "^\s*#" -and $_ -notmatch "^\s*$" }).Count
            $functions = ($content | Where-Object { $_ -match "^\s*function\s+" }).Count
            $classes = ($content | Where-Object { $_ -match "^\s*class\s+" }).Count

            Write-Host ""
            Write-Host "=== Code Metrics ===" -ForegroundColor Cyan
            Write-Host "Total Lines: $totalLines" -ForegroundColor White
            Write-Host "Code Lines: $codeLines" -ForegroundColor White
            Write-Host "Functions: $functions" -ForegroundColor White
            Write-Host "Classes: $classes" -ForegroundColor White
        }

    } catch {
        $stopwatch.Stop()
        Write-Log "Benchmark failed: $($_.Exception.Message)" "Error"
    }
}

# ===================================================================
# MAIN EXECUTION FUNCTION
# ===================================================================

function Start-WindowsSetup {
    [CmdletBinding()]
    param()

    try {
        # Initialize
        Initialize-Logging

        # Show banner
        Write-Host ""
        Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║                    Windows Setup Script                     ║" -ForegroundColor Cyan
        Write-Host "║              Chrome + Python + Nekobox Installer            ║" -ForegroundColor Cyan
        Write-Host "║                   All-in-One Edition v$($script:Config.Version)                   ║" -ForegroundColor Cyan
        Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
        Write-Host ""

        # Handle test modes
        if ($Test) {
            Invoke-SystemTest
            return
        }

        if ($TestGDrive) {
            Test-GoogleDriveAccess
            return
        }

        if ($Benchmark) {
            Invoke-Benchmark
            return
        }

        # Check prerequisites
        Test-Prerequisites

        # Select region
        $selectedRegion = Select-UserRegion

        # Show configuration
        Write-Host ""
        Write-Host "=== Windows Setup Configuration ===" -ForegroundColor Yellow
        Write-Host "Region: $selectedRegion" -ForegroundColor Cyan
        Write-Host "Skip Python: $SkipPython" -ForegroundColor Cyan
        Write-Host "Skip Chrome: $SkipChrome" -ForegroundColor Cyan
        Write-Host "Skip Nekobox: $SkipNekobox" -ForegroundColor Cyan
        Write-Host "Silent Mode: $Silent" -ForegroundColor Cyan
        Write-Host ""

        # Confirm execution
        if (-not $Silent) {
            $confirm = Read-Host "Proceed with installation? (Y/N)"
            if ($confirm -notmatch '^[Yy]') {
                Write-Log "Installation cancelled by user" "Warning"
                return
            }
        }

        # Initialize download engine
        $downloader = [DownloadEngine]::new($script:Config.UserAgent, $script:Config.TempDir)

        Write-Host ""
        Write-Host "=== Starting Installation Process ===" -ForegroundColor Green

        # Execute installation steps
        if (-not $SkipPython) {
            Install-Python -Downloader $downloader
        }

        Set-SystemRegion -Region $selectedRegion

        if (-not $SkipChrome) {
            Install-Chrome -Downloader $downloader
        }

        if (-not $SkipNekobox) {
            Install-Nekobox -Downloader $downloader
        }

        Write-Host ""
        Write-Host "=== Installation Completed Successfully ===" -ForegroundColor Green
        Write-Log "All installations completed successfully" "Success"

        # Show summary
        Write-Host ""
        Write-Host "=== Installation Summary ===" -ForegroundColor Yellow
        Write-Host "System region: $selectedRegion" -ForegroundColor White

        if (-not $SkipPython) {
            try {
                $pythonVersion = python --version 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "Python: $pythonVersion" -ForegroundColor Green
                } else {
                    Write-Host "Python: Installation may have failed" -ForegroundColor Red
                }
            } catch {
                Write-Host "Python: Installation may have failed" -ForegroundColor Red
            }
        }

        if (-not $SkipChrome) {
            $chromeInstalled = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
                              Where-Object { $_.DisplayName -like "*Google Chrome*" }
            if ($chromeInstalled) {
                Write-Host "Chrome: Installed ($($chromeInstalled.DisplayVersion))" -ForegroundColor Green
            } else {
                Write-Host "Chrome: Installation may have failed" -ForegroundColor Red
            }
        }

        if (-not $SkipNekobox) {
            if (Test-Path -Path $script:Apps.Nekobox.InstallPath) {
                $nekoboxFiles = Get-ChildItem -Path $script:Apps.Nekobox.InstallPath -Filter "*.exe" -ErrorAction SilentlyContinue
                if ($nekoboxFiles.Count -gt 0) {
                    Write-Host "Nekobox: Installed ($($nekoboxFiles.Count) executables)" -ForegroundColor Green
                } else {
                    Write-Host "Nekobox: Installation may have failed" -ForegroundColor Red
                }
            } else {
                Write-Host "Nekobox: Installation may have failed" -ForegroundColor Red
            }
        }

        Write-Host ""
        Write-Host "Log file: $($script:Config.LogFile)" -ForegroundColor Cyan

    } catch {
        Write-Host ""
        Write-Host "=== Installation Failed ===" -ForegroundColor Red
        Write-Log "Installation failed: $($_.Exception.Message)" "Error"
        throw
    } finally {
        Stop-Logging

        if (-not $Silent) {
            Write-Host ""
            Write-Host "Press any key to exit..." -ForegroundColor Yellow
            $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        }
    }
}

# ===================================================================
# SCRIPT ENTRY POINT
# ===================================================================

# Start the setup if not dot-sourced
if ($MyInvocation.InvocationName -ne '.') {
    Start-WindowsSetup
}
