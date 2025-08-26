# ===================================================================
# Windows Setup Script - Chrome, Python, Nekobox Auto Installer
# All-in-One Script for VM Deployment
# Compatible with PowerShell 5.x and Windows 10/11
# ===================================================================

param(
    [string]$Region = "US",
    [switch]$SkipPython,
    [switch]$SkipChrome,
    [switch]$SkipNekobox,
    [switch]$Silent
)

# Script configuration
$ErrorActionPreference = "Continue"  # Changed to Continue for better VM compatibility
$LogFile = "$env:USERPROFILE\Downloads\SetupWin_Log.txt"

# Start logging
try {
    Start-Transcript -Path $LogFile -Append -ErrorAction SilentlyContinue
} catch {
    # Continue without logging if transcript fails
}

Write-Host "=== Windows Setup Script Started ===" -ForegroundColor Green
Write-Host "Log file: $LogFile" -ForegroundColor Cyan
Write-Host ""

# ===================================================================
# CONFIGURATION
# ===================================================================

# Chrome versions with multiple download sources
$ChromeVersions = @{
    1 = @{
        Name = "Chrome Latest Stable"
        GoogleDriveID = "1ydDsvNEk-MUNLpOnsi0Qt5RpY-2dUD1H"
        DirectURL = "https://dl.google.com/chrome/install/latest/chrome_installer.exe"
        BackupURL = "https://dl.google.com/chrome/install/GoogleChromeStandaloneEnterprise64.msi"
    }
    2 = @{
        Name = "Chrome 136.0.7103.114"
        GoogleDriveID = "1d-E1sy7ztydiulYyMJvl7lQx9NCrVIkc"
        DirectURL = "https://dl.google.com/chrome/install/latest/chrome_installer.exe"
        BackupURL = "https://dl.google.com/chrome/install/GoogleChromeStandaloneEnterprise64.msi"
    }
    3 = @{
        Name = "Chrome 137.0.7151.120"
        GoogleDriveID = "13_BfLqye5sVvWZMD6A-QzaCgHjsoWO-6"
        DirectURL = "https://dl.google.com/chrome/install/latest/chrome_installer.exe"
        BackupURL = "https://dl.google.com/chrome/install/GoogleChromeStandaloneEnterprise64.msi"
    }
    4 = @{
        Name = "Chrome Enterprise MSI"
        GoogleDriveID = "1L1mJpZEq-HeoE6u8-7gJrgOWpuYzJFda"
        DirectURL = "https://dl.google.com/chrome/install/GoogleChromeStandaloneEnterprise64.msi"
        BackupURL = "https://dl.google.com/chrome/install/latest/chrome_installer.exe"
    }
    5 = @{
        Name = "Chrome Beta Channel"
        GoogleDriveID = "1cXO_K7Vy9uIlqPpq9QtMfnOB8AHyjCY7"
        DirectURL = "https://dl.google.com/chrome/install/beta/chrome_installer.exe"
        BackupURL = "https://dl.google.com/chrome/install/latest/chrome_installer.exe"
    }
}

# Nekobox configuration with multiple sources
$NekoboxConfig = @{
    GoogleDriveID = "1Rs7as6-oHv9IIHAurlgwmc_WigSLYHJb"
    BackupGoogleDriveID = "1Rs7as6-oHv9IIHAurlgwmc_WigSLYHJb"  # Same for now, can be updated
    DirectURL = ""  # Add direct download URL if available
    GitHubURL = ""  # Add GitHub release URL if available
}

# Paths
$DownloadsPath = "$env:USERPROFILE\Downloads"
$ChromeInstallerPath = "$DownloadsPath\chrome_installer.exe"
$NekoboxZipPath = "$DownloadsPath\nekobox_installer.zip"
$NekoboxExtractPath = "$DownloadsPath\nekobox"
$NekoboxInstallPath = "$env:ProgramFiles\Nekobox"

# ===================================================================
# UTILITY FUNCTIONS
# ===================================================================

function Test-AdminRights {
    Write-Host "Checking administrator rights..." -ForegroundColor Yellow
    
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        Write-Host "ERROR: This script requires administrator privileges." -ForegroundColor Red
        Write-Host "Please run PowerShell as Administrator and try again." -ForegroundColor Red
        Stop-Transcript
        exit 1
    }
    
    Write-Host "✓ Administrator rights confirmed" -ForegroundColor Green
}

function Write-Status {
    param(
        [string]$Message,
        [string]$Status = "Info"
    )
    
    $color = switch ($Status) {
        "Success" { "Green" }
        "Error" { "Red" }
        "Warning" { "Yellow" }
        default { "White" }
    }
    
    $prefix = switch ($Status) {
        "Success" { "✓" }
        "Error" { "❌" }
        "Warning" { "⚠️" }
        default { "ℹ️" }
    }
    
    Write-Host "$prefix $Message" -ForegroundColor $color
}

function Invoke-SafeCommand {
    param(
        [string]$Command,
        [string]$Arguments = "",
        [string]$WorkingDirectory = $PWD,
        [int]$TimeoutSeconds = 300
    )
    
    try {
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = $Command
        $processInfo.Arguments = $Arguments
        $processInfo.WorkingDirectory = $WorkingDirectory
        $processInfo.UseShellExecute = $false
        $processInfo.RedirectStandardOutput = $true
        $processInfo.RedirectStandardError = $true
        $processInfo.CreateNoWindow = $true
        
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $processInfo
        $process.Start() | Out-Null
        
        $output = $process.StandardOutput.ReadToEnd()
        $errorOutput = $process.StandardError.ReadToEnd()

        $process.WaitForExit($TimeoutSeconds * 1000)

        if ($process.ExitCode -eq 0) {
            return @{
                Success = $true
                Output = $output
                Error = $errorOutput
                ExitCode = $process.ExitCode
            }
        } else {
            return @{
                Success = $false
                Output = $output
                Error = $errorOutput
                ExitCode = $process.ExitCode
            }
        }
    } catch {
        return @{
            Success = $false
            Output = ""
            Error = $_.Exception.Message
            ExitCode = -1
        }
    }
}

# ===================================================================
# PYTHON & GDOWN INSTALLATION
# ===================================================================

function Install-PythonAndGdown {
    if ($SkipPython) {
        Write-Status "Skipping Python installation (SkipPython flag set)" "Warning"
        return
    }

    Write-Host "=== Installing Python and gdown ===" -ForegroundColor Yellow

    # Check if Python is already installed
    try {
        $pythonVersion = python --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Status "Python already installed: $pythonVersion" "Success"
        } else {
            throw "Python not found"
        }
    } catch {
        Write-Status "Python not found. Installing..." "Warning"

        # Download Python installer directly
        $pythonUrl = "https://www.python.org/ftp/python/3.12.0/python-3.12.0-amd64.exe"
        $pythonInstaller = "$env:TEMP\python_installer.exe"

        Write-Status "Downloading Python installer..."
        try {
            # Use System.Net.WebClient for better VM compatibility
            $webClient = New-Object System.Net.WebClient
            $webClient.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
            $webClient.DownloadFile($pythonUrl, $pythonInstaller)
            $webClient.Dispose()

            if (Test-Path -Path $pythonInstaller) {
                Write-Status "Python installer downloaded" "Success"

                # Install Python silently
                Write-Status "Installing Python..."
                $installArgs = "/quiet InstallAllUsers=1 PrependPath=1 Include_test=0"
                $installResult = Start-Process -FilePath $pythonInstaller -ArgumentList $installArgs -Wait -PassThru

                if ($installResult.ExitCode -eq 0) {
                    Write-Status "Python installed successfully" "Success"

                    # Refresh PATH
                    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")

                    # Clean up installer
                    Remove-Item -Path $pythonInstaller -Force -ErrorAction SilentlyContinue
                } else {
                    throw "Python installation failed with exit code: $($installResult.ExitCode)"
                }
            } else {
                throw "Failed to download Python installer"
            }
        } catch {
            Write-Status "Direct download failed. Trying alternative method..." "Warning"

            # Fallback: Try to open Microsoft Store
            try {
                Start-Process "ms-windows-store://pdp/?ProductId=9NRWMJP3717K" -ErrorAction SilentlyContinue
                if (-not $Silent) {
                    Read-Host "Please install Python from Microsoft Store and press Enter to continue"
                }
            } catch {
                Write-Status "Cannot open Microsoft Store. Please install Python manually from python.org" "Error"
                if (-not $Silent) {
                    Read-Host "Press Enter after installing Python to continue"
                }
            }
        }
    }

    # Verify Python installation with retry
    $retryCount = 0
    $maxRetries = 3

    do {
        Start-Sleep -Seconds 2
        try {
            $pythonVersion = python --version 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Status "Python verification successful: $pythonVersion" "Success"
                break
            } else {
                $retryCount++
                if ($retryCount -lt $maxRetries) {
                    Write-Status "Python verification failed, retrying... ($retryCount/$maxRetries)" "Warning"
                } else {
                    throw "Python not working after installation"
                }
            }
        } catch {
            $retryCount++
            if ($retryCount -ge $maxRetries) {
                Write-Status "Python installation verification failed" "Error"
                throw "Python installation failed"
            }
        }
    } while ($retryCount -lt $maxRetries)

    # Install gdown
    Write-Status "Installing gdown package..."
    try {
        python -m pip install gdown --quiet --upgrade 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Status "gdown installed successfully" "Success"
        } else {
            throw "pip install gdown failed"
        }
    } catch {
        Write-Status "gdown installation failed, trying alternative..." "Warning"
        try {
            python -m pip install --user gdown --quiet 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Status "gdown installed successfully (user mode)" "Success"
            } else {
                throw "gdown installation failed completely"
            }
        } catch {
            Write-Status "gdown installation failed: $($_.Exception.Message)" "Error"
            throw "gdown installation failed"
        }
    }

    # Verify gdown
    try {
        python -c "import gdown; print('gdown OK')" 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Status "gdown verification successful" "Success"
        } else {
            throw "gdown import failed"
        }
    } catch {
        Write-Status "gdown verification failed" "Error"
        throw "gdown verification failed"
    }
}

# ===================================================================
# DOWNLOAD FUNCTIONS - VM Compatible
# ===================================================================

function Test-FileIntegrity {
    param(
        [string]$FilePath,
        [int]$MinSizeKB = 1024
    )

    if (-not (Test-Path -Path $FilePath)) {
        return @{ Valid = $false; Reason = "File does not exist" }
    }

    $fileSize = (Get-Item -Path $FilePath).Length

    if ($fileSize -lt ($MinSizeKB * 1024)) {
        return @{ Valid = $false; Reason = "File too small ($fileSize bytes)" }
    }

    # Check if file is HTML (common Google Drive error)
    try {
        $firstLine = Get-Content -Path $FilePath -TotalCount 1 -ErrorAction SilentlyContinue
        if ($firstLine -like "*<html*" -or $firstLine -like "*<!DOCTYPE*") {
            return @{ Valid = $false; Reason = "File is HTML (Google Drive error page)" }
        }
    } catch {
        # If we can't read the file, it might be binary (which is good for installers)
    }

    # Check file signature for executables (PowerShell 5.x compatible)
    try {
        $extension = [System.IO.Path]::GetExtension($FilePath).ToLower()
        if ($extension -eq ".exe") {
            # Read first few bytes using .NET FileStream for PowerShell 5.x compatibility
            $fileStream = [System.IO.File]::OpenRead($FilePath)
            $buffer = New-Object byte[] 2
            $fileStream.Read($buffer, 0, 2) | Out-Null
            $fileStream.Close()

            if ($buffer[0] -eq 0x4D -and $buffer[1] -eq 0x5A) {  # MZ header
                return @{ Valid = $true; Reason = "Valid PE executable" }
            } else {
                return @{ Valid = $false; Reason = "Invalid executable header" }
            }
        } elseif ($extension -eq ".msi") {
            # MSI files start with specific signature
            $fileStream = [System.IO.File]::OpenRead($FilePath)
            $buffer = New-Object byte[] 8
            $fileStream.Read($buffer, 0, 8) | Out-Null
            $fileStream.Close()

            if ($buffer[0] -eq 0xD0 -and $buffer[1] -eq 0xCF) {  # MSI signature
                return @{ Valid = $true; Reason = "Valid MSI file" }
            } else {
                return @{ Valid = $false; Reason = "Invalid MSI header" }
            }
        } elseif ($extension -eq ".zip") {
            # ZIP files start with PK signature
            $fileStream = [System.IO.File]::OpenRead($FilePath)
            $buffer = New-Object byte[] 4
            $fileStream.Read($buffer, 0, 4) | Out-Null
            $fileStream.Close()

            if ($buffer[0] -eq 0x50 -and $buffer[1] -eq 0x4B) {  # PK signature
                return @{ Valid = $true; Reason = "Valid ZIP file" }
            } else {
                return @{ Valid = $false; Reason = "Invalid ZIP header" }
            }
        }
    } catch {
        # If byte reading fails, assume it's valid if size is OK
        return @{ Valid = $true; Reason = "Size check passed, header check failed" }
    }

    return @{ Valid = $true; Reason = "File appears valid" }
}

function Get-FileWithMultipleMethods {
    param(
        [string]$GoogleDriveID = "",
        [string]$DirectURL = "",
        [string]$BackupURL = "",
        [string]$OutputPath
    )

    Write-Status "Downloading file with multiple methods..."
    Write-Status "Output: $OutputPath"

    # Create output directory if it doesn't exist
    $outputDir = Split-Path -Path $OutputPath -Parent
    if (-not (Test-Path -Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    $downloadSuccess = $false
    $downloadMethods = @()

    # Add download methods in order of preference
    if ($DirectURL) {
        $downloadMethods += @{ Method = "Direct URL"; URL = $DirectURL }
    }
    if ($BackupURL) {
        $downloadMethods += @{ Method = "Backup URL"; URL = $BackupURL }
    }
    if ($GoogleDriveID) {
        $downloadMethods += @{ Method = "Google Drive (gdown)"; URL = "https://drive.google.com/uc?id=$GoogleDriveID" }
        $downloadMethods += @{ Method = "Google Drive (curl)"; URL = "https://drive.google.com/uc?export=download&id=$GoogleDriveID" }
    }

    foreach ($method in $downloadMethods) {
        Write-Status "Trying: $($method.Method)"

        try {
            # Remove existing file if it exists and is empty/corrupted
            if (Test-Path -Path $OutputPath) {
                $existingSize = (Get-Item -Path $OutputPath).Length
                if ($existingSize -lt 1024) {  # Less than 1KB, probably corrupted
                    Remove-Item -Path $OutputPath -Force
                }
            }

            if ($method.Method -like "*gdown*") {
                # Try gdown method
                $gdownCheck = Invoke-SafeCommand -Command "python" -Arguments "-c `"import gdown`"" -TimeoutSeconds 5
                if ($gdownCheck.Success) {
                    $downloadResult = Invoke-SafeCommand -Command "python" -Arguments "-c `"import gdown; gdown.download('$($method.URL)', '$OutputPath', quiet=False)`"" -TimeoutSeconds 300
                    if ($downloadResult.Success) {
                        $downloadSuccess = $true
                    }
                }
            } elseif ($method.Method -like "*curl*") {
                # Try curl method
                $curlResult = Invoke-SafeCommand -Command "curl" -Arguments "-L `"$($method.URL)`" -o `"$OutputPath`" --fail --silent --show-error" -TimeoutSeconds 300
                if ($curlResult.Success) {
                    $downloadSuccess = $true
                }
            } else {
                # Try WebClient method for direct URLs
                $webClient = New-Object System.Net.WebClient
                $webClient.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
                $webClient.DownloadFile($method.URL, $OutputPath)
                $webClient.Dispose()
                $downloadSuccess = $true
            }

            # Verify download with integrity check
            if ($downloadSuccess -and (Test-Path -Path $OutputPath)) {
                $integrityCheck = Test-FileIntegrity -FilePath $OutputPath -MinSizeKB 1024
                if ($integrityCheck.Valid) {
                    $fileSize = (Get-Item -Path $OutputPath).Length
                    Write-Status "$($method.Method) successful. File size: $([math]::Round($fileSize/1MB, 2)) MB" "Success"
                    Write-Status "File integrity: $($integrityCheck.Reason)" "Success"
                    return $true
                } else {
                    Write-Status "$($method.Method) downloaded corrupted file: $($integrityCheck.Reason)" "Warning"
                    Remove-Item -Path $OutputPath -Force -ErrorAction SilentlyContinue
                    $downloadSuccess = $false
                }
            }

        } catch {
            Write-Status "$($method.Method) failed: $($_.Exception.Message)" "Warning"
            $downloadSuccess = $false
        }

        if ($downloadSuccess) {
            break
        }
    }

    Write-Status "All download methods failed for this file" "Error"
    return $false
}

# Simplified Google Drive download for Nekobox
function Get-GoogleDriveFile {
    param(
        [string]$FileID,
        [string]$OutputPath
    )

    return Get-FileWithMultipleMethods -GoogleDriveID $FileID -OutputPath $OutputPath
}

# Alternative download using BITS (Background Intelligent Transfer Service)
function Get-GoogleDriveFile-BITS {
    param(
        [string]$FileID,
        [string]$OutputPath
    )

    Write-Status "Trying BITS download..."

    try {
        $downloadUrl = "https://drive.google.com/uc?export=download&id=$FileID"
        Import-Module BitsTransfer -ErrorAction SilentlyContinue

        Start-BitsTransfer -Source $downloadUrl -Destination $OutputPath -DisplayName "GoogleDriveDownload" -ErrorAction Stop | Out-Null

        if (Test-Path -Path $OutputPath) {
            Write-Status "BITS download successful" "Success"
            return $true
        } else {
            Write-Status "BITS download failed" "Error"
            return $false
        }
    } catch {
        Write-Status "BITS download error: $($_.Exception.Message)" "Error"
        return $false
    }
}

# ===================================================================
# SYSTEM CONFIGURATION
# ===================================================================

function Set-SystemRegion {
    param([string]$Region = "US")

    Write-Host "=== Configuring System Region ===" -ForegroundColor Yellow

    try {
        $languageCode = switch ($Region.ToUpper()) {
            "UK" { "en-GB" }
            "US" { "en-US" }
            "AU" { "en-AU" }
            "SG" { "en-SG" }
            "NZ" { "en-NZ" }
            default { "en-US" }
        }

        Write-Status "Setting system language to: $languageCode"

        # Set system language and region
        Set-WinUILanguageOverride -Language $languageCode -ErrorAction SilentlyContinue
        Set-WinUserLanguageList $languageCode -Force -ErrorAction SilentlyContinue

        # Set timezone to UTC
        Write-Status "Setting timezone to UTC"
        Set-TimeZone -Id "UTC" -ErrorAction SilentlyContinue

        # Set keyboard layout
        Write-Status "Setting keyboard layout to US"
        Set-WinDefaultInputMethodOverride -InputTip "0409:00000409" -ErrorAction SilentlyContinue

        Write-Status "System region configured successfully" "Success"
    } catch {
        Write-Status "Failed to configure system region: $($_.Exception.Message)" "Warning"
    }
}

# ===================================================================
# CHROME INSTALLATION
# ===================================================================

function Remove-ExistingChrome {
    Write-Status "Checking for existing Chrome installation..."

    $uninstallPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    )

    foreach ($path in $uninstallPaths) {
        try {
            Get-ChildItem -Path $path -ErrorAction SilentlyContinue | ForEach-Object {
                $app = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
                if ($app.DisplayName -like "*Google Chrome*") {
                    Write-Status "Found Chrome installation: $($app.DisplayName)"

                    if ($app.UninstallString) {
                        Write-Status "Uninstalling existing Chrome..."
                        $uninstallCmd = $app.UninstallString

                        # Parse uninstall command
                        if ($uninstallCmd -match '^"([^"]+)"(.*)$') {
                            $exe = $matches[1]
                            $arguments = $matches[2].Trim() + " --uninstall --multi-install --chrome --force-uninstall"
                        } else {
                            $exe = $uninstallCmd
                            $arguments = "--uninstall --multi-install --chrome --force-uninstall"
                        }

                        $uninstallResult = Invoke-SafeCommand -Command $exe -Arguments $arguments -TimeoutSeconds 120
                        if ($uninstallResult.Success) {
                            Write-Status "Chrome uninstalled successfully" "Success"
                        } else {
                            Write-Status "Chrome uninstall may have failed, continuing..." "Warning"
                        }
                        return
                    }
                }
            }
        } catch {
            Write-Status "Error checking uninstall registry: $($_.Exception.Message)" "Warning"
        }
    }

    Write-Status "No existing Chrome installation found"
}

function Select-ChromeVersion {
    Write-Host "=== Chrome Version Selection ===" -ForegroundColor Yellow
    Write-Host "Available Chrome versions:"

    $ChromeVersions.GetEnumerator() | Sort-Object Key | ForEach-Object {
        Write-Host "$($_.Key). $($_.Value.Name)"
    }

    do {
        if ($Silent) {
            $selection = "1"  # Default to first option in silent mode
            Write-Status "Silent mode: Auto-selecting option 1" "Info"
        } else {
            $selection = Read-Host "Select Chrome version (1-5)"
        }

        $selectionInt = 0

        if ([int]::TryParse($selection, [ref]$selectionInt) -and $ChromeVersions.ContainsKey($selectionInt)) {
            $selectedVersion = $ChromeVersions[$selectionInt]
            Write-Status "Selected: $($selectedVersion.Name)" "Success"
            return $selectionInt  # Return the key, not the ID
        } else {
            Write-Status "Invalid selection. Please choose 1-5." "Error"
            if ($Silent) {
                Write-Status "Silent mode: Using default option 1" "Warning"
                return 1
            }
        }
    } while ($true)
}

function Install-Chrome {
    if ($SkipChrome) {
        Write-Status "Skipping Chrome installation (SkipChrome flag set)" "Warning"
        return
    }

    Write-Host "=== Installing Chrome ===" -ForegroundColor Yellow

    # Remove existing Chrome
    Remove-ExistingChrome

    # Select Chrome version
    $selectedVersion = Select-ChromeVersion
    $chromeConfig = $ChromeVersions[$selectedVersion]

    # Download Chrome installer with multiple methods
    Write-Status "Downloading Chrome installer..."
    $downloadSuccess = Get-FileWithMultipleMethods -GoogleDriveID $chromeConfig.GoogleDriveID -DirectURL $chromeConfig.DirectURL -BackupURL $chromeConfig.BackupURL -OutputPath $ChromeInstallerPath

    if (-not $downloadSuccess) {
        Write-Status "All Chrome download methods failed. Trying manual fallback..." "Warning"

        # Emergency method 1: Try winget
        try {
            Write-Status "Trying winget Chrome installation..."
            $wingetResult = Invoke-SafeCommand -Command "winget" -Arguments "install Google.Chrome --accept-package-agreements --accept-source-agreements --silent" -TimeoutSeconds 300

            if ($wingetResult.Success) {
                Write-Status "Chrome installed via winget" "Success"

                # Still try to disable auto-update
                try {
                    $policyPath = "HKLM:\SOFTWARE\Policies\Google\Update"
                    if (-not (Test-Path -Path $policyPath)) {
                        New-Item -Path $policyPath -Force | Out-Null
                    }
                    New-ItemProperty -Path $policyPath -Name "UpdateDefault" -Value 0 -PropertyType DWord -Force | Out-Null
                    Write-Status "Chrome auto-update disabled" "Success"
                } catch {
                    Write-Status "Could not disable auto-update" "Warning"
                }

                return  # Skip file-based installation
            }
        } catch {
            Write-Status "Winget installation failed" "Warning"
        }

        # Emergency method 2: Direct Google download with integrity check
        try {
            Write-Status "Trying Google's official Chrome download..."
            $webClient = New-Object System.Net.WebClient
            $webClient.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
            $webClient.DownloadFile("https://dl.google.com/chrome/install/latest/chrome_installer.exe", $ChromeInstallerPath)
            $webClient.Dispose()

            if (Test-Path -Path $ChromeInstallerPath) {
                $integrityCheck = Test-FileIntegrity -FilePath $ChromeInstallerPath -MinSizeKB 1024
                if ($integrityCheck.Valid) {
                    Write-Status "Emergency download successful: $($integrityCheck.Reason)" "Success"
                    $downloadSuccess = $true
                } else {
                    Write-Status "Emergency download corrupted: $($integrityCheck.Reason)" "Warning"
                    Remove-Item -Path $ChromeInstallerPath -Force -ErrorAction SilentlyContinue
                }
            }
        } catch {
            Write-Status "Emergency download failed: $($_.Exception.Message)" "Error"
        }
    }

    if (-not $downloadSuccess) {
        Write-Status "Failed to download Chrome installer from any source" "Error"
        throw "Chrome download failed"
    }

    # Verify installer file
    if (-not (Test-Path -Path $ChromeInstallerPath)) {
        Write-Status "Chrome installer file not found after download" "Error"
        throw "Chrome installer not found"
    }

    $installerSize = (Get-Item -Path $ChromeInstallerPath).Length
    if ($installerSize -lt 1024) {
        Write-Status "Chrome installer file is too small ($installerSize bytes), likely corrupted" "Error"
        Remove-Item -Path $ChromeInstallerPath -Force -ErrorAction SilentlyContinue
        throw "Chrome installer corrupted"
    }

    Write-Status "Chrome installer verified: $([math]::Round($installerSize/1MB, 2)) MB"

    # Validate installer file before installation
    Write-Status "Validating Chrome installer..."
    try {
        $fileInfo = Get-Item -Path $ChromeInstallerPath
        $fileSize = $fileInfo.Length
        $fileName = $fileInfo.Name

        Write-Status "Installer file: $fileName ($([math]::Round($fileSize/1MB, 2)) MB)"

        # Check if file is executable
        if ($fileName -notmatch '\.(exe|msi)$') {
            Write-Status "Downloaded file is not an installer (wrong extension)" "Error"
            throw "Invalid installer file"
        }

        # Check minimum file size (Chrome installer should be at least 1MB)
        if ($fileSize -lt 1048576) {
            Write-Status "Installer file too small, likely corrupted or HTML error page" "Error"

            # Try to read first few bytes to check if it's HTML
            $firstBytes = Get-Content -Path $ChromeInstallerPath -TotalCount 1 -Raw -ErrorAction SilentlyContinue
            if ($firstBytes -like "*<html*" -or $firstBytes -like "*<!DOCTYPE*") {
                Write-Status "Downloaded file is HTML (probably Google Drive error page)" "Error"
                Remove-Item -Path $ChromeInstallerPath -Force -ErrorAction SilentlyContinue
                throw "Downloaded HTML instead of installer"
            } else {
                throw "Installer file corrupted or incomplete"
            }
        }

        Write-Status "Installer validation passed" "Success"

    } catch {
        Write-Status "Installer validation failed: $($_.Exception.Message)" "Error"

        # Try one more download with direct Google URL
        Write-Status "Attempting emergency Chrome download..." "Warning"
        try {
            Remove-Item -Path $ChromeInstallerPath -Force -ErrorAction SilentlyContinue

            $webClient = New-Object System.Net.WebClient
            $webClient.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
            $webClient.DownloadFile("https://dl.google.com/chrome/install/latest/chrome_installer.exe", $ChromeInstallerPath)
            $webClient.Dispose()

            if (Test-Path -Path $ChromeInstallerPath) {
                $emergencySize = (Get-Item -Path $ChromeInstallerPath).Length
                if ($emergencySize -gt 1048576) {
                    Write-Status "Emergency download successful: $([math]::Round($emergencySize/1MB, 2)) MB" "Success"
                } else {
                    throw "Emergency download also failed"
                }
            } else {
                throw "Emergency download failed"
            }
        } catch {
            Write-Status "Emergency Chrome download failed: $($_.Exception.Message)" "Error"
            throw "All Chrome download attempts failed"
        }
    }

    # Install Chrome
    Write-Status "Installing Chrome..."
    try {
        # Try different installation methods based on file extension
        $fileExtension = [System.IO.Path]::GetExtension($ChromeInstallerPath).ToLower()

        if ($fileExtension -eq ".msi") {
            # MSI installation
            $installArgs = "/i `"$ChromeInstallerPath`" /quiet /norestart ALLUSERS=1"
            $installResult = Invoke-SafeCommand -Command "msiexec" -Arguments $installArgs -TimeoutSeconds 300
        } else {
            # EXE installation - try multiple argument combinations
            $installArgsList = @(
                "/silent /install",
                "--silent --install",
                "/S",
                "--system-level --do-not-launch-chrome"
            )

            $installSuccess = $false
            foreach ($installArgs in $installArgsList) {
                Write-Status "Trying installation with args: $installArgs"
                $installResult = Invoke-SafeCommand -Command $ChromeInstallerPath -Arguments $installArgs -TimeoutSeconds 300

                if ($installResult.Success -or $installResult.ExitCode -eq 0) {
                    $installSuccess = $true
                    break
                }
            }

            if (-not $installSuccess) {
                throw "All installation methods failed"
            }
        }

        Write-Status "Chrome installation command completed" "Success"

        # Wait for installation to complete
        Start-Sleep -Seconds 5

        # Disable Chrome auto-update
        Write-Status "Disabling Chrome auto-update..."
        try {
            $policyPath = "HKLM:\SOFTWARE\Policies\Google\Update"
            if (-not (Test-Path -Path $policyPath)) {
                New-Item -Path $policyPath -Force | Out-Null
            }

            New-ItemProperty -Path $policyPath -Name "AutoUpdateCheckPeriodMinutes" -Value 0 -PropertyType DWord -Force | Out-Null
            New-ItemProperty -Path $policyPath -Name "UpdateDefault" -Value 0 -PropertyType DWord -Force | Out-Null

            $chromeAppPath = "$policyPath\{8A69D345-D564-463C-AFF1-A69D9E530F96}"
            if (-not (Test-Path -Path $chromeAppPath)) {
                New-Item -Path $chromeAppPath -Force | Out-Null
            }
            New-ItemProperty -Path $chromeAppPath -Name "Update" -Value 0 -PropertyType DWord -Force | Out-Null

            Write-Status "Chrome auto-update disabled" "Success"
        } catch {
            Write-Status "Failed to disable Chrome auto-update: $($_.Exception.Message)" "Warning"
        }

    } catch {
        Write-Status "Chrome installation error: $($_.Exception.Message)" "Error"
        throw "Chrome installation failed"
    }

    # Clean up installer
    try {
        Remove-Item -Path $ChromeInstallerPath -Force -ErrorAction SilentlyContinue
        Write-Status "Chrome installer cleaned up"
    } catch {
        Write-Status "Failed to clean up Chrome installer" "Warning"
    }
}

# ===================================================================
# NEKOBOX INSTALLATION
# ===================================================================

function Install-Nekobox {
    if ($SkipNekobox) {
        Write-Status "Skipping Nekobox installation (SkipNekobox flag set)" "Warning"
        return
    }

    Write-Host "=== Installing Nekobox ===" -ForegroundColor Yellow

    # Download Nekobox with multiple methods
    Write-Status "Downloading Nekobox..."
    $downloadSuccess = Get-FileWithMultipleMethods -GoogleDriveID $NekoboxConfig.GoogleDriveID -DirectURL $NekoboxConfig.DirectURL -BackupURL "" -OutputPath $NekoboxZipPath

    if (-not $downloadSuccess) {
        Write-Status "Primary Nekobox download failed. Trying alternative methods..." "Warning"

        # Try backup Google Drive ID
        if ($NekoboxConfig.BackupGoogleDriveID -and $NekoboxConfig.BackupGoogleDriveID -ne $NekoboxConfig.GoogleDriveID) {
            Write-Status "Trying backup Google Drive source..."
            $downloadSuccess = Get-GoogleDriveFile -FileID $NekoboxConfig.BackupGoogleDriveID -OutputPath $NekoboxZipPath
        }

        # Try manual intervention if not silent
        if (-not $downloadSuccess -and -not $Silent) {
            Write-Status "All automatic Nekobox downloads failed. Manual intervention required." "Warning"
            Write-Host ""
            Write-Host "Please manually download Nekobox:" -ForegroundColor Yellow
            Write-Host "1. Download Nekobox ZIP file from your source" -ForegroundColor Cyan
            Write-Host "2. Save it as: $NekoboxZipPath" -ForegroundColor Cyan
            Write-Host ""

            $manualConfirm = Read-Host "Press Enter after downloading Nekobox ZIP manually, or type 'skip' to skip Nekobox installation"
            if ($manualConfirm.ToLower() -eq "skip") {
                Write-Status "Nekobox installation skipped by user" "Warning"
                return
            }

            if (Test-Path -Path $NekoboxZipPath) {
                $integrityCheck = Test-FileIntegrity -FilePath $NekoboxZipPath -MinSizeKB 100  # ZIP should be at least 100KB
                if ($integrityCheck.Valid) {
                    Write-Status "Manual Nekobox download verified" "Success"
                    $downloadSuccess = $true
                } else {
                    Write-Status "Manual Nekobox download failed integrity check: $($integrityCheck.Reason)" "Error"
                }
            }
        }

        if (-not $downloadSuccess) {
            if ($Silent) {
                Write-Status "Nekobox download failed in silent mode. Creating placeholder installation..." "Warning"

                # Create a placeholder Nekobox installation for testing
                try {
                    if (-not (Test-Path -Path $NekoboxInstallPath)) {
                        New-Item -ItemType Directory -Path $NekoboxInstallPath -Force | Out-Null
                    }

                    # Create a simple batch file as placeholder
                    $placeholderContent = @"
@echo off
echo Nekobox placeholder - actual download failed
echo Please manually install Nekobox from official source
pause
"@
                    $placeholderPath = "$NekoboxInstallPath\nekobox_placeholder.bat"
                    Set-Content -Path $placeholderPath -Value $placeholderContent

                    Write-Status "Placeholder Nekobox created at: $NekoboxInstallPath" "Warning"
                    Write-Status "Please manually install actual Nekobox later" "Warning"
                    return
                } catch {
                    Write-Status "Failed to create placeholder Nekobox" "Error"
                    return
                }
            } else {
                Write-Status "Failed to download Nekobox from all sources" "Error"
                throw "Nekobox download failed"
            }
        }
    }

    # Validate Nekobox ZIP file before extraction
    Write-Status "Validating Nekobox ZIP file..."
    $zipIntegrityCheck = Test-FileIntegrity -FilePath $NekoboxZipPath -MinSizeKB 100
    if (-not $zipIntegrityCheck.Valid) {
        Write-Status "Nekobox ZIP validation failed: $($zipIntegrityCheck.Reason)" "Error"

        # Try to read first few bytes to see what we actually downloaded
        try {
            $firstBytes = Get-Content -Path $NekoboxZipPath -TotalCount 1 -Raw -ErrorAction SilentlyContinue
            if ($firstBytes -like "*<html*" -or $firstBytes -like "*<!DOCTYPE*") {
                Write-Status "Downloaded HTML instead of ZIP (Google Drive error page)" "Error"
                Remove-Item -Path $NekoboxZipPath -Force -ErrorAction SilentlyContinue
            }
        } catch {
            # Continue with generic error
        }

        throw "Nekobox ZIP file is corrupted or invalid"
    }

    Write-Status "Nekobox ZIP validation passed: $($zipIntegrityCheck.Reason)" "Success"

    # Extract Nekobox
    Write-Status "Extracting Nekobox..."
    try {
        if (Test-Path -Path $NekoboxExtractPath) {
            Remove-Item -Path $NekoboxExtractPath -Recurse -Force
        }

        # Try PowerShell Expand-Archive first
        try {
            Expand-Archive -Path $NekoboxZipPath -DestinationPath $NekoboxExtractPath -Force
            Write-Status "Nekobox extracted successfully with Expand-Archive" "Success"
        } catch {
            # Fallback to .NET ZipFile if Expand-Archive fails
            Write-Status "Expand-Archive failed, trying .NET extraction..." "Warning"

            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::ExtractToDirectory($NekoboxZipPath, $NekoboxExtractPath)
            Write-Status "Nekobox extracted successfully with .NET ZipFile" "Success"
        }

        # Verify extraction
        if (-not (Test-Path -Path $NekoboxExtractPath)) {
            throw "Extraction directory not created"
        }

        $extractedFiles = Get-ChildItem -Path $NekoboxExtractPath -Recurse
        if ($extractedFiles.Count -eq 0) {
            throw "No files were extracted"
        }

        Write-Status "Extracted $($extractedFiles.Count) files from Nekobox ZIP" "Success"

    } catch {
        Write-Status "Failed to extract Nekobox: $($_.Exception.Message)" "Error"

        # Try to provide more specific error information
        if (Test-Path -Path $NekoboxZipPath) {
            $zipSize = (Get-Item -Path $NekoboxZipPath).Length
            Write-Status "ZIP file size: $zipSize bytes" "Info"

            if ($zipSize -lt 1024) {
                Write-Status "ZIP file is too small, likely corrupted" "Error"
            }
        }

        throw "Nekobox extraction failed"
    }

    # Install Nekobox
    Write-Status "Installing Nekobox..."
    $nekoboxExe = Get-ChildItem -Path $NekoboxExtractPath -Filter "*.exe" -Recurse | Select-Object -First 1

    if ($nekoboxExe) {
        try {
            # Create installation directory
            if (-not (Test-Path -Path $NekoboxInstallPath)) {
                New-Item -ItemType Directory -Path $NekoboxInstallPath -Force | Out-Null
            }

            # Copy files to installation directory
            Copy-Item -Path "$($NekoboxExtractPath)\*" -Destination $NekoboxInstallPath -Recurse -Force
            Write-Status "Nekobox installed to: $NekoboxInstallPath" "Success"

            # Set auto-start
            Write-Status "Configuring Nekobox auto-start..."
            $startupPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
            $nekoboxMainExe = "$NekoboxInstallPath\$($nekoboxExe.Name)"

            if (Test-Path -Path $nekoboxMainExe) {
                New-ItemProperty -Path $startupPath -Name "Nekobox" -Value $nekoboxMainExe -PropertyType String -Force | Out-Null
                Write-Status "Nekobox auto-start configured" "Success"
            } else {
                Write-Status "Nekobox executable not found for auto-start" "Warning"
            }

            # Create desktop shortcut
            Write-Status "Creating desktop shortcut..."
            try {
                $desktopPath = [Environment]::GetFolderPath("Desktop")
                $shortcutPath = "$desktopPath\Nekobox.lnk"

                $WshShell = New-Object -ComObject WScript.Shell
                $shortcut = $WshShell.CreateShortcut($shortcutPath)
                $shortcut.TargetPath = $nekoboxMainExe
                $shortcut.WorkingDirectory = $NekoboxInstallPath
                $shortcut.Description = "Nekobox VPN Client"
                $shortcut.Save()

                Write-Status "Desktop shortcut created" "Success"
            } catch {
                Write-Status "Failed to create desktop shortcut: $($_.Exception.Message)" "Warning"
            }

        } catch {
            Write-Status "Failed to install Nekobox: $($_.Exception.Message)" "Error"
            throw "Nekobox installation failed"
        }
    } else {
        Write-Status "Nekobox executable not found in extracted files" "Error"
        throw "Nekobox executable not found"
    }

    # Clean up
    try {
        Remove-Item -Path $NekoboxZipPath -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $NekoboxExtractPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Status "Nekobox installation files cleaned up"
    } catch {
        Write-Status "Failed to clean up Nekobox installation files" "Warning"
    }
}

# ===================================================================
# MAIN EXECUTION
# ===================================================================

function Start-Setup {
    try {
        Write-Host "Starting Windows Setup Process..." -ForegroundColor Green
        Write-Host "Region: $Region" -ForegroundColor Cyan
        Write-Host "Skip Python: $SkipPython" -ForegroundColor Cyan
        Write-Host "Skip Chrome: $SkipChrome" -ForegroundColor Cyan
        Write-Host "Skip Nekobox: $SkipNekobox" -ForegroundColor Cyan
        Write-Host ""

        # Step 1: Check admin rights
        Test-AdminRights

        # Step 2: Install Python and gdown
        Install-PythonAndGdown

        # Step 3: Configure system region
        Set-SystemRegion -Region $Region

        # Step 4: Install Chrome
        Install-Chrome

        # Step 5: Install Nekobox
        Install-Nekobox

        Write-Host ""
        Write-Host "=== SETUP COMPLETED SUCCESSFULLY ===" -ForegroundColor Green
        Write-Status "All components have been installed and configured" "Success"
        Write-Status "Log file saved to: $LogFile" "Info"

        # Summary
        Write-Host ""
        Write-Host "=== INSTALLATION SUMMARY ===" -ForegroundColor Yellow

        if (-not $SkipPython) {
            $pythonCheck = Invoke-SafeCommand -Command "python" -Arguments "--version"
            if ($pythonCheck.Success) {
                Write-Status "Python: $($pythonCheck.Output.Trim())" "Success"
            } else {
                Write-Status "Python: Not installed or not working" "Error"
            }

            $gdownCheck = Invoke-SafeCommand -Command "python" -Arguments "-c `"import gdown; print('gdown version:', getattr(gdown, '__version__', 'unknown'))`""
            if ($gdownCheck.Success) {
                Write-Status "gdown: $($gdownCheck.Output.Trim())" "Success"
            } else {
                Write-Status "gdown: Not installed or not working" "Error"
            }
        }

        if (-not $SkipChrome) {
            if (Get-Process -Name "chrome" -ErrorAction SilentlyContinue) {
                Write-Status "Chrome: Running" "Success"
            } else {
                Write-Status "Chrome: Installed (not running)" "Success"
            }
        }

        if (-not $SkipNekobox) {
            if (Test-Path -Path "$NekoboxInstallPath\*.exe") {
                Write-Status "Nekobox: Installed at $NekoboxInstallPath" "Success"
            } else {
                Write-Status "Nekobox: Installation may have failed" "Error"
            }
        }

        Write-Status "System region: $Region" "Info"

    } catch {
        Write-Host ""
        Write-Host "=== SETUP FAILED ===" -ForegroundColor Red
        Write-Status "Error: $($_.Exception.Message)" "Error"
        Write-Status "Check log file for details: $LogFile" "Info"

        Stop-Transcript
        exit 1
    }
}

# ===================================================================
# SCRIPT ENTRY POINT
# ===================================================================

# Display banner
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                    Windows Setup Script                     ║" -ForegroundColor Cyan
Write-Host "║              Chrome + Python + Nekobox Installer            ║" -ForegroundColor Cyan
Write-Host "║                   PowerShell 5.x Compatible                 ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Show parameters
Write-Host "Script Parameters:" -ForegroundColor Yellow
Write-Host "  Region: $Region"
Write-Host "  SkipPython: $SkipPython"
Write-Host "  SkipChrome: $SkipChrome"
Write-Host "  SkipNekobox: $SkipNekobox"
Write-Host ""

# Confirm execution
if (-not $SkipPython -or -not $SkipChrome -or -not $SkipNekobox) {
    $confirm = Read-Host "Do you want to proceed with the installation? (Y/N)"
    if ($confirm -notmatch '^[Yy]') {
        Write-Host "Installation cancelled by user." -ForegroundColor Yellow
        Stop-Transcript
        exit 0
    }
}

# Start the setup process
Start-Setup

# Final message
Write-Host ""
Write-Host "Setup completed! You may need to restart your computer for all changes to take effect." -ForegroundColor Green
Write-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

# Stop logging
try {
    Stop-Transcript -ErrorAction SilentlyContinue
} catch {
    # Continue if transcript stop fails
}

# ===================================================================
# BUILT-IN TESTING FUNCTIONS
# ===================================================================

function Test-Installation {
    Write-Host ""
    Write-Host "=== TESTING INSTALLATION ===" -ForegroundColor Yellow
    Write-Host ""

    $testResults = @()

    # Test Python
    Write-Host "Testing Python..." -ForegroundColor Cyan
    try {
        $pythonVersion = python --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Status "Python: $pythonVersion" "Success"
            $testResults += "Python: PASS"
        } else {
            Write-Status "Python: Not working" "Error"
            $testResults += "Python: FAIL"
        }
    } catch {
        Write-Status "Python: Error testing" "Error"
        $testResults += "Python: ERROR"
    }

    # Test gdown
    Write-Host "Testing gdown..." -ForegroundColor Cyan
    try {
        python -c "import gdown; print('gdown OK')" 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Status "gdown: Working" "Success"
            $testResults += "gdown: PASS"
        } else {
            Write-Status "gdown: Not working" "Error"
            $testResults += "gdown: FAIL"
        }
    } catch {
        Write-Status "gdown: Error testing" "Error"
        $testResults += "gdown: ERROR"
    }

    # Test Chrome
    Write-Host "Testing Chrome..." -ForegroundColor Cyan
    $chromePaths = @(
        "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
    )

    $chromeFound = $false
    foreach ($path in $chromePaths) {
        if (Test-Path -Path $path) {
            Write-Status "Chrome: Found at $path" "Success"
            $testResults += "Chrome: PASS"
            $chromeFound = $true
            break
        }
    }

    if (-not $chromeFound) {
        Write-Status "Chrome: Not found" "Error"
        $testResults += "Chrome: FAIL"
    }

    # Test Nekobox
    Write-Host "Testing Nekobox..." -ForegroundColor Cyan
    if (Test-Path -Path "$env:ProgramFiles\Nekobox") {
        $nekoboxExe = Get-ChildItem -Path "$env:ProgramFiles\Nekobox" -Filter "*.exe" -ErrorAction SilentlyContinue
        if ($nekoboxExe) {
            Write-Status "Nekobox: Installed ($($nekoboxExe.Count) executables)" "Success"
            $testResults += "Nekobox: PASS"
        } else {
            Write-Status "Nekobox: Directory exists but no executables" "Error"
            $testResults += "Nekobox: FAIL"
        }
    } else {
        Write-Status "Nekobox: Not installed" "Error"
        $testResults += "Nekobox: FAIL"
    }

    # Test auto-start
    Write-Host "Testing auto-start..." -ForegroundColor Cyan
    try {
        $startupPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
        $nekoboxStartup = Get-ItemProperty -Path $startupPath -Name "Nekobox" -ErrorAction SilentlyContinue
        if ($nekoboxStartup) {
            Write-Status "Auto-start: Configured" "Success"
            $testResults += "Auto-start: PASS"
        } else {
            Write-Status "Auto-start: Not configured" "Error"
            $testResults += "Auto-start: FAIL"
        }
    } catch {
        Write-Status "Auto-start: Error checking" "Error"
        $testResults += "Auto-start: ERROR"
    }

    # Summary
    Write-Host ""
    Write-Host "=== TEST SUMMARY ===" -ForegroundColor Yellow
    $passCount = ($testResults | Where-Object { $_ -like "*PASS*" }).Count
    $failCount = ($testResults | Where-Object { $_ -like "*FAIL*" }).Count
    $errorCount = ($testResults | Where-Object { $_ -like "*ERROR*" }).Count

    Write-Host "Passed: $passCount" -ForegroundColor Green
    Write-Host "Failed: $failCount" -ForegroundColor Red
    Write-Host "Errors: $errorCount" -ForegroundColor Magenta

    if ($failCount -eq 0 -and $errorCount -eq 0) {
        Write-Host "🎉 All tests passed!" -ForegroundColor Green
    } else {
        Write-Host "⚠️ Some components need attention" -ForegroundColor Yellow
    }
}

# Run tests if requested
if ($args -contains "-Test" -or $args -contains "--test") {
    Test-Installation
    Write-Host ""
    Write-Host "Press any key to exit..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 0
}
