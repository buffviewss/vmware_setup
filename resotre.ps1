
# ===================================================================
# Winsetup.ps1 - Production Windows Setup Script
# Chrome + Python + Nekobox Auto Installer
# Compatible with PowerShell 5.x and Windows 10/11
# ===================================================================

#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [ValidateSet("Chrome135", "Chrome136", "Chrome137", "Chrome138", "Chrome141", "Interactive")]
    [string]$ChromeVersion = "Interactive",

    [switch]$SkipPython,
    [switch]$SkipChrome,
    [switch]$SkipNekobox,
    [switch]$Silent,
    [switch]$Test,
    [switch]$TestGDrive,
    [switch]$Benchmark
)

# ===================================================================
# CONFIGURATION
# ===================================================================

$script:Config = @{
    Version = "3.0.0"
    LogFile = "$env:USERPROFILE\Downloads\Winsetup_Log.txt"
    TempDir = $env:TEMP
    UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
    DesktopPath = [Environment]::GetFolderPath("Desktop")
}

$script:GoogleDriveFiles = @{
    Chrome = @{
        "Chrome135" = @{ Name = "Chrome 135.0.7049.96"; ID = "1ydDsvNEk-MUNLpOnsi0Qt5RpY-2dUD1H" }
        "Chrome136" = @{ Name = "Chrome 136.0.7103.114"; ID = "1d-E1sy7ztydiulYyMJvl7lQx9NCrVIkc" }
        "Chrome137" = @{ Name = "Chrome 137.0.7151.120"; ID = "13_BfLqye5sVvWZMD6A-QzaCgHjsoWO-6" }
        "Chrome138" = @{ Name = "Chrome 138.0.7194.0"; ID = "1L1mJpZEq-HeoE6u8-7gJrgOWpuYzJFda" }
        "Chrome141" = @{ Name = "Chrome 141.0.7340.0"; ID = "1cXO_K7Vy9uIlqPpq9QtMfnOB8AHyjCY7" }
    }
    Nekobox = "1Rs7as6-oHv9IIHAurlgwmc_WigSLYHJb"
}

$script:Apps = @{
    Python = @{
        Version = "3.12.0"
        URL = "https://www.python.org/ftp/python/3.12.0/python-3.12.0-amd64.exe"
        InstallArgs = "/quiet InstallAllUsers=1 PrependPath=1 Include_test=0"
    }
    Chrome = @{
        InstallArgs = "/silent /install"
    }
    Nekobox = @{
        InstallPath = "$env:ProgramFiles\Nekobox"
        ExecutableName = "nekoray.exe"
    }
}


# ===================================================================
# UTILITY FUNCTIONS
# ===================================================================

function Get-ChromeExecutablePath {
    $chromePaths = @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe",
        "$env:LocalAppData\Google\Chrome\Application\chrome.exe",
        "$env:UserProfile\AppData\Local\Google\Chrome\Application\chrome.exe"
    )

    $chromeExe = $chromePaths | Where-Object { Test-Path $_ } | Select-Object -First 1

    if (-not $chromeExe) {
        $chromeExe = Get-ChromeFromRegistry
        if (-not $chromeExe) {
            $chromeExe = Find-ChromeInDirectories
        }
    }

    return $chromeExe
}

function Get-ChromeFromRegistry {
    $registryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe"
    )

    foreach ($regPath in $registryPaths) {
        if (Test-Path $regPath) {
            $regChromePath = (Get-ItemProperty -Path $regPath -Name "(default)" -ErrorAction SilentlyContinue)."(default)"
            if ($regChromePath -and (Test-Path $regChromePath)) {
                return $regChromePath
            }
        }
    }
    return $null
}

function Find-ChromeInDirectories {
    $googleDirs = @(
        "$env:ProgramFiles\Google",
        "$env:ProgramFiles(x86)\Google",
        "$env:LocalAppData\Google"
    )

    foreach ($dir in $googleDirs) {
        if (Test-Path $dir) {
            $foundExe = Get-ChildItem -Path $dir -Filter "chrome.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($foundExe) {
                return $foundExe.FullName
            }
        }
    }
    return $null
}

function Get-NekoboxExecutablePath {
    $nekoboxExe = Join-Path $script:Apps.Nekobox.InstallPath $script:Apps.Nekobox.ExecutableName

    if (-not (Test-Path $nekoboxExe)) {
        $exeFiles = Get-ChildItem -Path $script:Apps.Nekobox.InstallPath -Filter "*.exe" -ErrorAction SilentlyContinue
        if ($exeFiles.Count -gt 0) {
            $preferredExe = $exeFiles | Where-Object { $_.Name -like "*nekoray*" -or $_.Name -like "*nekobox*" } | Select-Object -First 1
            $nekoboxExe = if ($preferredExe) { $preferredExe.FullName } else { $exeFiles[0].FullName }
        }
    }

    return $nekoboxExe
}

function Get-ChromeInstallationInfo {
    $chromeRegistryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    foreach ($regPath in $chromeRegistryPaths) {
        $chromeInstalled = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue |
                          Where-Object { $_.DisplayName -like "*Google Chrome*" } | Select-Object -First 1
        if ($chromeInstalled) {
            return $chromeInstalled
        }
    }

    return $null
}

function New-ShellShortcut {
    param(
        [string]$ShortcutPath,
        [string]$TargetPath,
        [string]$WorkingDirectory = "",
        [string]$Description = "",
        [string]$IconLocation = ""
    )

    try {
        $wshShell = New-Object -ComObject WScript.Shell
        $shortcut = $wshShell.CreateShortcut($ShortcutPath)
        $shortcut.TargetPath = $TargetPath
        if ($WorkingDirectory) { $shortcut.WorkingDirectory = $WorkingDirectory }
        if ($Description) { $shortcut.Description = $Description }
        if ($IconLocation) { $shortcut.IconLocation = $IconLocation }
        $shortcut.Save()
        return $true
    } catch {
        Write-Log "Failed to create shortcut: $($_.Exception.Message)" "Warning"
        return $false
    }
}

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet("Info", "Success", "Warning", "Error")]
        [string]$Level = "Info"
    )

    $colors = @{ "Info" = "White"; "Success" = "Green"; "Warning" = "Yellow"; "Error" = "Red" }
    $prefixes = @{ "Info" = "[i]"; "Success" = "[+]"; "Warning" = "[*]"; "Error" = "[!]" }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp $($prefixes[$Level]) $Message"

    Write-Host "$($prefixes[$Level]) $Message" -ForegroundColor $colors[$Level]

    try {
        Add-Content -Path $script:Config.LogFile -Value $logMessage -ErrorAction SilentlyContinue
    } catch {
        # Ignore logging errors
    }
}

function Test-Prerequisites {
    Write-Log "Checking prerequisites..." "Info"

    Test-AdminRights
    Test-PowerShellVersion
    Test-InternetConnectivity
    Test-WindowsVersion
}

function Test-AdminRights {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Log "Administrator rights required. Please run as Administrator." "Error"
        throw "Administrator rights required"
    }
    Write-Log "Administrator rights confirmed" "Success"
}

function Test-PowerShellVersion {
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        Write-Log "PowerShell 5.0 or higher required" "Error"
        throw "PowerShell version not supported"
    }
    Write-Log "PowerShell version: $($PSVersionTable.PSVersion)" "Success"
}

function Test-InternetConnectivity {
    try {
        $null = Test-NetConnection -ComputerName "8.8.8.8" -Port 53 -InformationLevel Quiet -ErrorAction Stop
        Write-Log "Internet connectivity confirmed" "Success"
    } catch {
        Write-Log "Internet connectivity required" "Warning"
    }
}

function Test-WindowsVersion {
    $osVersion = [System.Environment]::OSVersion.Version
    if ($osVersion.Major -lt 10) {
        Write-Log "Windows 10 or higher recommended" "Warning"
    } else {
        Write-Log "Windows version: $($osVersion.Major).$($osVersion.Minor)" "Success"
    }
}

function Initialize-Logging {
    try {
        Start-Transcript -Path $script:Config.LogFile -Append -ErrorAction SilentlyContinue
        Write-Log "Logging initialized: $($script:Config.LogFile)" "Info"
        Write-Log "Winsetup v$($script:Config.Version) started" "Info"
    } catch {
        Write-Log "Could not initialize logging" "Warning"
    }
}

function Stop-Logging {
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

        if (-not $this.EnsureGdown()) {
            Write-Log "gdown not available, falling back to direct download" "Warning"
            return $this.DownloadGoogleDriveDirect($fileId, $outputPath)
        }

        return $this.TryGdownMethods($fileId, $outputPath)
    }

    [bool] TryGdownMethods([string]$fileId, [string]$outputPath) {
        $pythonPath = $outputPath.Replace('\', '/')
        $methods = @(
            "import gdown; gdown.download(id='$fileId', output='$pythonPath', quiet=False, fuzzy=True)",
            "import gdown; gdown.download('https://drive.google.com/uc?id=$fileId', '$pythonPath', quiet=False)",
            "import gdown; gdown.download('$fileId', '$pythonPath', quiet=False)"
        )

        foreach ($method in $methods) {
            if ($this.ExecuteGdownMethod($method, $outputPath)) {
                return $true
            }
        }

        return $this.DownloadGoogleDriveDirect($fileId, $outputPath)
    }

    [bool] ExecuteGdownMethod([string]$method, [string]$outputPath) {
        $tempPyFile = $null
        try {
            Write-Log "Trying gdown method..." "Info"

            $tempPyFile = "$env:TEMP\gdown_script_$([System.Guid]::NewGuid().ToString('N').Substring(0,8)).py"
            Set-Content -Path $tempPyFile -Value $method -Encoding UTF8

            $null = Start-Process -FilePath "python" -ArgumentList $tempPyFile -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput "$env:TEMP\gdown_output.txt" -RedirectStandardError "$env:TEMP\gdown_error.txt"

            if ($this.ValidateGdownDownload($outputPath)) {
                $this.CleanupTempFiles(@("$env:TEMP\gdown_output.txt", "$env:TEMP\gdown_error.txt", $tempPyFile))
                return $true
            } else {
                $this.LogGdownError()
                return $false
            }
        } catch {
            Write-Log "gdown method failed: $($_.Exception.Message)" "Warning"
            return $false
        } finally {
            if ($tempPyFile -and (Test-Path $tempPyFile)) {
                Remove-Item $tempPyFile -Force -ErrorAction SilentlyContinue
            }
        }
    }

    [bool] ValidateGdownDownload([string]$outputPath) {
        if ((Test-Path -Path $outputPath) -and (Get-Item -Path $outputPath).Length -gt 10240) {
            $fileSize = (Get-Item -Path $outputPath).Length
            Write-Log "gdown download successful: $([math]::Round($fileSize/1MB, 2)) MB" "Success"
            return $true
        }
        return $false
    }

    [void] LogGdownError() {
        if (Test-Path "$env:TEMP\gdown_error.txt") {
            $errorContent = Get-Content "$env:TEMP\gdown_error.txt" -Raw -ErrorAction SilentlyContinue
            if ($errorContent) {
                Write-Log "gdown error: $($errorContent.Substring(0, [Math]::Min(100, $errorContent.Length)))" "Warning"
            }
        }
    }

    [void] CleanupTempFiles([string[]]$files) {
        $files | ForEach-Object {
            Remove-Item $_ -Force -ErrorAction SilentlyContinue
        }
    }
    
    [bool] EnsureGdown() {
        try {
            # Check if gdown is available with timeout
            $checkProcess = Start-Process -FilePath "python" -ArgumentList "-c", "import gdown" -Wait -PassThru -WindowStyle Hidden -RedirectStandardError "$env:TEMP\gdown_check.txt"

            if ($checkProcess.ExitCode -eq 0) {
                Write-Log "gdown is available" "Success"
                Remove-Item "$env:TEMP\gdown_check.txt" -Force -ErrorAction SilentlyContinue
                return $true
            }

            Write-Log "Installing gdown..." "Info"
            $installProcess = Start-Process -FilePath "python" -ArgumentList "-m", "pip", "install", "gdown", "--quiet" -Wait -PassThru -WindowStyle Hidden

            if ($installProcess.ExitCode -eq 0) {
                Write-Log "gdown installed successfully" "Success"
                return $true
            } else {
                Write-Log "Failed to install gdown (exit code: $($installProcess.ExitCode))" "Error"
                return $false
            }
        } catch {
            Write-Log "Python not available: $($_.Exception.Message)" "Error"
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
        return (Test-Path -Path $filePath) -and ((Get-Item -Path $filePath).Length -gt ($minSizeKB * 1024))
    }
}

# ===================================================================
# SELECTION FUNCTIONS
# ===================================================================



function Select-ChromeVersion {
    if ($ChromeVersion -ne "Interactive") {
        Write-Log "Chrome version pre-selected: $ChromeVersion" "Info"
        return $ChromeVersion
    }

    if ($Silent) {
        Write-Log "Silent mode: Using latest Chrome version" "Info"
        return "Chrome141"
    }

    Write-Host ""
    Write-Host "=== Chrome Version Selection ===" -ForegroundColor Yellow
    Write-Host "Please select Chrome version to install:" -ForegroundColor Cyan
    Write-Host ""

    $versionOptions = @()
    $counter = 1

    foreach ($key in $script:GoogleDriveFiles.Chrome.Keys | Sort-Object) {
        $version = $script:GoogleDriveFiles.Chrome[$key]
        Write-Host "$counter. $($version.Name)" -ForegroundColor White
        Write-Host ""
        $versionOptions += $key
        $counter++
    }

    do {
        $selection = Read-Host "Select Chrome version (1-$($versionOptions.Count))"
        $selectionInt = 0

        if ([int]::TryParse($selection, [ref]$selectionInt) -and
            $selectionInt -ge 1 -and $selectionInt -le $versionOptions.Count) {
            $selectedVersion = $versionOptions[$selectionInt - 1]
            $versionInfo = $script:GoogleDriveFiles.Chrome[$selectedVersion]
            Write-Log "Selected Chrome version: $($versionInfo.Name)" "Success"
            return $selectedVersion
        } else {
            Write-Log "Invalid selection. Please choose 1-$($versionOptions.Count)." "Error"
        }
    } while ($true)
}

# ===================================================================
# INSTALLATION FUNCTIONS
# ===================================================================

function Install-Python {
    [CmdletBinding()]
    param([Parameter(Mandatory)][DownloadEngine]$Downloader)

    Write-Log "=== Installing Python ===" "Info"

    try {
        $pythonVersion = python --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Python already installed: $pythonVersion" "Success"
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

    if (-not $Downloader.DownloadFile($script:Apps.Python.URL, $installerPath)) {
        throw "Failed to download Python installer"
    }

    if (-not $Downloader.ValidateDownload($installerPath, 1024)) {
        throw "Python installer download is invalid"
    }

    Write-Log "Installing Python..." "Info"

    $process = Start-Process -FilePath $installerPath -ArgumentList $script:Apps.Python.InstallArgs -Wait -PassThru

    if ($process.ExitCode -ne 0) {
        throw "Python installation failed with exit code: $($process.ExitCode)"
    }

    Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue

    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

    try {
        $pythonVersion = python --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Python installed successfully: $pythonVersion" "Success"

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



function Uninstall-ExistingChrome {
    Write-Log "Checking for existing Chrome installations..." "Info"

    $chromeInstalls = @()
    $chromeInstalls += Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
                      Where-Object { $_.DisplayName -like "*Google Chrome*" }
    $chromeInstalls += Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
                      Where-Object { $_.DisplayName -like "*Google Chrome*" }

    if ($chromeInstalls.Count -eq 0) {
        Write-Log "No existing Chrome installation found" "Info"
        return
    }

    foreach ($chrome in $chromeInstalls) {
        Write-Log "Found Chrome: $($chrome.DisplayName) $($chrome.DisplayVersion)" "Info"

        if ($chrome.UninstallString) {
            Write-Log "Uninstalling existing Chrome..." "Info"

            try {
                $uninstallCmd = $chrome.UninstallString
                if ($uninstallCmd -match '"([^"]+)"(.*)') {
                    $uninstallExe = $matches[1]
                    $uninstallArgs = $matches[2].Trim() + " --uninstall --force-uninstall --system-level"
                } else {
                    $uninstallExe = $uninstallCmd
                    $uninstallArgs = "--uninstall --force-uninstall --system-level"
                }

                $process = Start-Process -FilePath $uninstallExe -ArgumentList $uninstallArgs -Wait -PassThru -WindowStyle Hidden

                if ($process.ExitCode -eq 0) {
                    Write-Log "Chrome uninstalled successfully" "Success"
                } else {
                    Write-Log "Chrome uninstall completed with exit code: $($process.ExitCode)" "Warning"
                }
            } catch {
                Write-Log "Failed to uninstall Chrome: $($_.Exception.Message)" "Warning"
            }
        }
    }

    $chromePaths = @(
        "$env:ProgramFiles\Google\Chrome",
        "$env:ProgramFiles(x86)\Google\Chrome",
        "$env:LOCALAPPDATA\Google\Chrome",
        "$env:APPDATA\Google\Chrome"
    )

    foreach ($path in $chromePaths) {
        if (Test-Path $path) {
            try {
                Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
                Write-Log "Removed Chrome directory: $path" "Success"
            } catch {
                Write-Log "Could not remove Chrome directory: $path" "Warning"
            }
        }
    }

    $registryPaths = @(
        "HKLM:\SOFTWARE\Google",
        "HKLM:\SOFTWARE\WOW6432Node\Google",
        "HKCU:\SOFTWARE\Google\Chrome"
    )

    foreach ($regPath in $registryPaths) {
        if (Test-Path $regPath) {
            try {
                Remove-Item -Path $regPath -Recurse -Force -ErrorAction SilentlyContinue
                Write-Log "Cleaned Chrome registry: $regPath" "Success"
            } catch {
                Write-Log "Could not clean Chrome registry: $regPath" "Warning"
            }
        }
    }

    Write-Log "Chrome cleanup completed" "Success"
}

function Block-ChromeUpdates {
    Write-Log "Blocking Chrome updates comprehensively..." "Info"

    try {
        Set-ChromeUpdatePolicies
        Set-ChromePolicies
        Block-ChromeUpdateUrls
        Disable-GoogleServices
        Disable-UpdateExecutables
        Remove-UpdateTasks
        Set-ChromeClientState

        Write-Log "Chrome updates blocked comprehensively with enhanced protection" "Success"
    } catch {
        Write-Log "Failed to block Chrome updates: $($_.Exception.Message)" "Warning"
    }
}

function Set-ChromeUpdatePolicies {
    $updatePolicyPath = "HKLM:\SOFTWARE\Policies\Google\Update"
    if (-not (Test-Path $updatePolicyPath)) {
        New-Item -Path $updatePolicyPath -Force | Out-Null
    }

    $updatePolicies = @{
        "UpdateDefault" = 0
        "AutoUpdateCheckPeriodMinutes" = 0
        "Update{8A69D345-D564-463C-AFF1-A69D9E530F96}" = 0
        "Install{8A69D345-D564-463C-AFF1-A69D9E530F96}" = 0
        "UpdateSuppressedStartHour" = 0
        "UpdateSuppressedDurationMin" = 1440
        "DisableAutoUpdateChecksCheckboxValue" = 1
        "UpdateCheckSuppressedStartHour" = 0
        "UpdateCheckSuppressedDurationMin" = 1440
        "UpdatePolicy" = 0
        "InstallPolicy" = 0
    }

    foreach ($policy in $updatePolicies.GetEnumerator()) {
        New-ItemProperty -Path $updatePolicyPath -Name $policy.Key -Value $policy.Value -PropertyType DWord -Force | Out-Null
    }
}

function Set-ChromePolicies {
    $chromePolicyPath = "HKLM:\SOFTWARE\Policies\Google\Chrome"
    if (-not (Test-Path $chromePolicyPath)) {
        New-Item -Path $chromePolicyPath -Force | Out-Null
    }

    $chromePolicies = @{
        "UpdatesSuppressed" = 1; "DefaultBrowserSettingEnabled" = 0; "ShowHomeButton" = 1
        "BookmarkBarEnabled" = 1; "PasswordManagerEnabled" = 0; "AutofillAddressEnabled" = 0
        "AutofillCreditCardEnabled" = 0; "SyncDisabled" = 1; "SigninAllowed" = 0
        "CloudPrintProxyEnabled" = 0; "MetricsReportingEnabled" = 0; "SearchSuggestEnabled" = 0
        "AlternateErrorPagesEnabled" = 0; "SpellCheckServiceEnabled" = 0; "SafeBrowsingEnabled" = 0
        "AutoplayPolicy" = 2; "ComponentUpdatesEnabled" = 0; "AutoUpdateCheckPeriodMinutes" = 0
        "UpdateCheckSuppressedStartHour" = 0; "UpdateCheckSuppressedDurationMin" = 1440
    }

    foreach ($policy in $chromePolicies.GetEnumerator()) {
        New-ItemProperty -Path $chromePolicyPath -Name $policy.Key -Value $policy.Value -PropertyType DWord -Force | Out-Null
    }
}

function Block-ChromeUpdateUrls {
    try {
        $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
        $hostsContent = Get-Content $hostsPath -ErrorAction SilentlyContinue
        $updateUrls = @(
            "update.googleapis.com", "clients2.google.com", "clients4.google.com",
            "clients5.google.com", "clients6.google.com", "edgedl.me.gvt1.com",
            "dl.google.com", "cache.pack.google.com", "chrome.google.com"
        )

        $hostsUpdated = $false
        foreach ($url in $updateUrls) {
            if ($hostsContent -notcontains "127.0.0.1 $url") {
                Add-Content -Path $hostsPath -Value "127.0.0.1 $url" -ErrorAction SilentlyContinue
                $hostsUpdated = $true
            }
        }

        if ($hostsUpdated) {
            Write-Log "Chrome update URLs blocked in hosts file" "Success"
        }
    } catch {
        Write-Log "Could not modify hosts file: $($_.Exception.Message)" "Warning"
    }
}

function Disable-GoogleServices {
    $services = @("gupdate", "gupdatem", "GoogleUpdaterService", "GoogleUpdaterInternalService")
    foreach ($service in $services) {
        try {
            $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
            if ($svc) {
                Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
                Set-Service -Name $service -StartupType Disabled -ErrorAction SilentlyContinue
                Write-Log "Disabled service: $service" "Success"
            }
        } catch {
            # Service might not exist, continue
        }
    }
}

function Disable-UpdateExecutables {
    $updatePaths = @(
        "$env:ProgramFiles\Google\Update",
        "$env:ProgramFiles(x86)\Google\Update",
        "$env:LOCALAPPDATA\Google\Update"
    )

    foreach ($path in $updatePaths) {
        if (Test-Path $path) {
            try {
                $updateExe = Join-Path $path "GoogleUpdate.exe"
                if (Test-Path $updateExe) {
                    Rename-Item -Path $updateExe -NewName "GoogleUpdate.exe.disabled" -Force -ErrorAction SilentlyContinue
                    Write-Log "Disabled GoogleUpdate.exe in: $path" "Success"
                }

                $otherExes = @("GoogleCrashHandler.exe", "GoogleCrashHandler64.exe")
                foreach ($exe in $otherExes) {
                    $exePath = Join-Path $path $exe
                    if (Test-Path $exePath) {
                        Rename-Item -Path $exePath -NewName "$exe.disabled" -Force -ErrorAction SilentlyContinue
                    }
                }
            } catch {
                Write-Log "Could not disable updates in: $path" "Warning"
            }
        }
    }
}

function Remove-UpdateTasks {
    $taskNames = @("GoogleUpdateTaskMachineCore", "GoogleUpdateTaskMachineUA", "GoogleUpdateTaskUserS-*")
    foreach ($taskName in $taskNames) {
        try {
            Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue
            Write-Log "Removed scheduled task: $taskName" "Success"
        } catch {
            # Task might not exist
        }
    }
}

function Set-ChromeClientState {
    try {
        $chromeClientStatePath = "HKLM:\SOFTWARE\Google\Update\ClientState\{8A69D345-D564-463C-AFF1-A69D9E530F96}"
        if (-not (Test-Path $chromeClientStatePath)) {
            New-Item -Path $chromeClientStatePath -Force | Out-Null
        }

        $clientStatePolicies = @{
            "UpdatePolicy" = 0
            "UpdateCheckSuppressedStartHour" = 0
            "UpdateCheckSuppressedDurationMin" = 1440
            "IsUpdateDisabled" = 1
        }

        foreach ($policy in $clientStatePolicies.GetEnumerator()) {
            New-ItemProperty -Path $chromeClientStatePath -Name $policy.Key -Value $policy.Value -PropertyType DWord -Force | Out-Null
        }

        $chromeClientStatePathWow = "HKLM:\SOFTWARE\WOW6432Node\Google\Update\ClientState\{8A69D345-D564-463C-AFF1-A69D9E530F96}"
        if (-not (Test-Path $chromeClientStatePathWow)) {
            New-Item -Path $chromeClientStatePathWow -Force | Out-Null
        }

        foreach ($policy in $clientStatePolicies.GetEnumerator()) {
            New-ItemProperty -Path $chromeClientStatePathWow -Name $policy.Key -Value $policy.Value -PropertyType DWord -Force | Out-Null
        }

        Write-Log "Chrome update client state configured to disable all update checks" "Success"
    } catch {
        Write-Log "Could not configure Chrome client state: $($_.Exception.Message)" "Warning"
    }
}

function Add-ChromeToTaskbar {
    Write-Log "Pinning Chrome to taskbar..." "Info"

    try {
        $chromeExe = Get-ChromeExecutablePath

        if (-not $chromeExe) {
            Write-Log "Chrome executable not immediately found, waiting for installation to complete..." "Info"
            Start-Sleep -Seconds 10
            $chromeExe = Get-ChromeExecutablePath
        }

        if (-not $chromeExe) {
            Write-Log "Chrome executable not found for taskbar pinning" "Warning"
            return
        }

        if (Invoke-ComTaskbarPin $chromeExe) { return }
        if (Invoke-PowerShellTaskbarPin $chromeExe) { return }
        if (Invoke-TaskbarDirectoryPin $chromeExe) { return }

        Write-Log "All taskbar pinning methods failed - Chrome installed but not pinned" "Warning"
    } catch {
        Write-Log "Failed to pin Chrome to taskbar: $($_.Exception.Message)" "Warning"
    }
}

function Invoke-ComTaskbarPin([string]$chromeExe) {
    try {
        $shell = New-Object -ComObject Shell.Application
        $folder = $shell.Namespace((Split-Path $chromeExe))
        $item = $folder.ParseName((Split-Path $chromeExe -Leaf))

        $verbs = $item.Verbs()
        foreach ($verb in $verbs) {
            if ($verb.Name -match "taskbar" -or $verb.Name -match "Pin") {
                $verb.DoIt()
                Write-Log "Chrome pinned to taskbar (COM method)" "Success"
                return $true
            }
        }
        return $false
    } catch {
        Write-Log "COM method failed: $($_.Exception.Message)" "Warning"
        return $false
    }
}

function Invoke-PowerShellTaskbarPin([string]$chromeExe) {
    try {
        $pinScript = @"
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public class TaskbarPinner {
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr SHGetFileInfo(string pszPath, uint dwFileAttributes, ref SHFILEINFO psfi, uint cbSizeFileInfo, uint uFlags);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct SHFILEINFO {
        public IntPtr hIcon;
        public int iIcon;
        public uint dwAttributes;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)]
        public string szDisplayName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 80)]
        public string szTypeName;
    }

    public static void PinToTaskbar(string filePath) {
        try {
            var startInfo = new System.Diagnostics.ProcessStartInfo {
                FileName = "powershell.exe",
                Arguments = string.Format("-Command \"(New-Object -ComObject Shell.Application).Namespace('{0}').ParseName('{1}').InvokeVerb('taskbarpin')\"",
                    System.IO.Path.GetDirectoryName(filePath), System.IO.Path.GetFileName(filePath)),
                WindowStyle = System.Diagnostics.ProcessWindowStyle.Hidden,
                UseShellExecute = false
            };
            System.Diagnostics.Process.Start(startInfo);
        } catch { }
    }
}
'@
[TaskbarPinner]::PinToTaskbar('$chromeExe')
"@
        $tempScript = "$env:TEMP\chrome_pin.ps1"
        $pinScript | Out-File -FilePath $tempScript -Encoding UTF8
        powershell -ExecutionPolicy Bypass -File $tempScript
        Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
        Write-Log "Chrome pinned to taskbar (PowerShell method)" "Success"
        return $true
    } catch {
        Write-Log "PowerShell pin method failed: $($_.Exception.Message)" "Warning"
        return $false
    }
}

function Invoke-TaskbarDirectoryPin([string]$chromeExe) {
    try {
        $taskbarPath = "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
        if (Test-Path $taskbarPath) {
            $shortcutPath = Join-Path $taskbarPath "Google Chrome.lnk"
            New-ShellShortcut -ShortcutPath $shortcutPath -TargetPath $chromeExe -WorkingDirectory (Split-Path $chromeExe) -Description "Google Chrome" -IconLocation $chromeExe | Out-Null
            Write-Log "Chrome shortcut added to taskbar directory" "Success"
            return $true
        }
        return $false
    } catch {
        Write-Log "Registry method failed: $($_.Exception.Message)" "Warning"
        return $false
    }
}

function Install-Chrome {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][DownloadEngine]$Downloader,
        [Parameter(Mandatory)][string]$ChromeVersion
    )

    Write-Log "=== Installing Chrome ===" "Info"

    Uninstall-ExistingChrome

    if (-not $script:GoogleDriveFiles.Chrome.ContainsKey($ChromeVersion)) {
        throw "Invalid Chrome version: $ChromeVersion"
    }

    $versionInfo = $script:GoogleDriveFiles.Chrome[$ChromeVersion]
    Write-Log "Installing Chrome version: $($versionInfo.Name)" "Info"

    $installerPath = Join-Path $script:Config.TempDir "chrome_installer.exe"

    if (-not $Downloader.DownloadGoogleDriveFile($versionInfo.ID, $installerPath)) {
        throw "Failed to download Chrome installer for version: $($versionInfo.Name)"
    }

    if (-not $Downloader.ValidateDownload($installerPath, 1024)) {
        throw "Chrome installer download is invalid"
    }

    $installSuccess = Invoke-ChromeInstallation $installerPath

    if (-not $installSuccess) {
        Write-Log "Chrome installation failed after maximum attempts" "Error"
    }

    Start-Sleep -Seconds 5
    Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue

    Block-ChromeUpdates
    Add-ChromeToTaskbar

    Write-Log "Chrome installation completed: $($versionInfo.Name)" "Success"
}

function Invoke-ChromeInstallation([string]$installerPath) {
    Write-Log "Installing Chrome..." "Info"

    $maxRetries = 3
    for ($retryCount = 1; $retryCount -le $maxRetries; $retryCount++) {
        if (Invoke-ChromeInstallAttempt $installerPath $retryCount $maxRetries) {
            return $true
        }

        if ($retryCount -lt $maxRetries) {
            Start-Sleep -Seconds 5
        }
    }

    return $false
}

function Invoke-ChromeInstallAttempt([string]$installerPath, [int]$retryCount, [int]$maxRetries) {
    try {
        Write-Log "Chrome installation attempt $retryCount of $maxRetries..." "Info"

        $process = Start-Process -FilePath $installerPath -ArgumentList $script:Apps.Chrome.InstallArgs -Wait -PassThru -WindowStyle Hidden
        $successCodes = @(0, 7)

        if ($process.ExitCode -in $successCodes) {
            Write-Log "Chrome installation completed successfully (exit code: $($process.ExitCode))" "Success"
            return $true
        } else {
            return Test-ChromeInstallationSuccess $process.ExitCode $retryCount $maxRetries
        }
    } catch {
        Write-Log "Chrome installation attempt $retryCount failed: $($_.Exception.Message)" "Warning"
        return $false
    }
}

function Test-ChromeInstallationSuccess([int]$exitCode, [int]$retryCount, [int]$maxRetries) {
    Write-Log "Chrome installer exit code: $exitCode - verifying installation..." "Warning"

    Start-Sleep -Seconds 10
    $chromeFound = Get-ChromeExecutablePath

    if ($chromeFound) {
        Write-Log "Chrome installation verified successful despite exit code $exitCode" "Success"
        return $true
    } else {
        Write-Log "Chrome installation attempt $retryCount failed - Chrome executable not found" "Warning"
        if ($retryCount -lt $maxRetries) {
            Write-Log "Retrying Chrome installation in 5 seconds..." "Info"
        }
        return $false
    }
}

function Install-Nekobox {
    [CmdletBinding()]
    param([Parameter(Mandatory)][DownloadEngine]$Downloader)

    Write-Log "=== Installing Nekobox ===" "Info"

    Remove-ExistingNekobox

    $zipPath = Join-Path $script:Config.TempDir "nekobox.zip"
    $extractPath = Join-Path $script:Config.TempDir "nekobox_extract"

    if (-not (Get-NekoboxArchive $Downloader $zipPath)) {
        return
    }

    try {
        Expand-NekoboxArchive $zipPath $extractPath
        Install-NekoboxFiles $extractPath
        Set-NekoboxPermissions
        Initialize-NekoboxConfiguration

        Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $extractPath -Recurse -Force -ErrorAction SilentlyContinue

        Write-Log "Nekobox installation completed successfully" "Success"
    } catch {
        Write-Log "Failed to extract/install Nekobox: $($_.Exception.Message)" "Error"
        Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $extractPath -Recurse -Force -ErrorAction SilentlyContinue

        if (-not $Silent) {
            throw "Nekobox installation failed"
        }
    }
}

function Remove-ExistingNekobox {
    if (Test-Path -Path $script:Apps.Nekobox.InstallPath) {
        Write-Log "Removing existing Nekobox installation..." "Info"
        try {
            Remove-Item -Path $script:Apps.Nekobox.InstallPath -Recurse -Force
            Write-Log "Existing Nekobox removed" "Success"
        } catch {
            Write-Log "Could not remove existing Nekobox: $($_.Exception.Message)" "Warning"
        }
    }
}

function Get-NekoboxArchive([DownloadEngine]$Downloader, [string]$zipPath) {
    Write-Log "Downloading Nekobox from Google Drive..." "Info"
    if (-not $Downloader.DownloadGoogleDriveFile($script:GoogleDriveFiles.Nekobox, $zipPath)) {
        if ($Silent) {
            Write-Log "Nekobox download failed in silent mode. Skipping..." "Warning"
            return $false
        } else {
            throw "Failed to download Nekobox from Google Drive"
        }
    }

    if (-not $Downloader.ValidateDownload($zipPath, 1024)) {
        throw "Nekobox download is invalid"
    }

    Write-Log "Downloaded Nekobox successfully" "Success"
    return $true
}

function Expand-NekoboxArchive([string]$zipPath, [string]$extractPath) {
    Write-Log "Extracting Nekobox..." "Info"

    if (Test-Path -Path $extractPath) {
        Remove-Item -Path $extractPath -Recurse -Force
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $extractPath)

    $extractedFiles = Get-ChildItem -Path $extractPath -Recurse -Filter "*.exe"
    if ($extractedFiles.Count -eq 0) {
        throw "No executable files found in extracted archive"
    }

    Write-Log "Extracted $($extractedFiles.Count) executable files" "Success"
}

function Install-NekoboxFiles([string]$extractPath) {
    if (-not (Test-Path -Path $script:Apps.Nekobox.InstallPath)) {
        New-Item -ItemType Directory -Path $script:Apps.Nekobox.InstallPath -Force | Out-Null
    }

    $sourceDir = Get-ChildItem -Path $extractPath -Directory | Select-Object -First 1
    if ($sourceDir) {
        Copy-Item -Path "$($sourceDir.FullName)\*" -Destination $script:Apps.Nekobox.InstallPath -Recurse -Force
    } else {
        Copy-Item -Path "$extractPath\*" -Destination $script:Apps.Nekobox.InstallPath -Recurse -Force
    }

    Write-Log "Nekobox installed to: $($script:Apps.Nekobox.InstallPath)" "Success"
}

function Set-NekoboxPermissions {
    try {
        $acl = Get-Acl $script:Apps.Nekobox.InstallPath
        $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule("Everyone", "FullControl", "Allow")
        $acl.SetAccessRule($accessRule)
        Set-Acl -Path $script:Apps.Nekobox.InstallPath -AclObject $acl

        Get-ChildItem -Path $script:Apps.Nekobox.InstallPath -Recurse | ForEach-Object {
            try {
                $itemAcl = Get-Acl $_.FullName
                $itemAcl.SetAccessRule($accessRule)
                Set-Acl -Path $_.FullName -AclObject $itemAcl
            } catch {
                # Continue if individual file fails
            }
        }

        Write-Log "Set full permissions for Nekobox directory and files" "Success"
    } catch {
        Write-Log "Could not set directory permissions: $($_.Exception.Message)" "Warning"
    }
}

function Initialize-NekoboxConfiguration {
    Set-NekoboxAutoStart
    Add-NekoboxDesktopShortcut
    Add-NekoboxToTaskbar
}

function Set-NekoboxAutoStart {
    Write-Log "Configuring Nekobox auto-start..." "Info"

    $nekoboxExe = Get-NekoboxExecutablePath
    if (-not $nekoboxExe -or -not (Test-Path $nekoboxExe)) {
        Write-Log "Nekobox executable not found for auto-start configuration" "Warning"
        return
    }

    try {
        Add-NekoboxToStartupRegistry $nekoboxExe
        Add-NekoboxToStartupFolder $nekoboxExe
    } catch {
        Write-Log "Failed to configure Nekobox auto-start: $($_.Exception.Message)" "Warning"
    }
}

function Add-NekoboxToStartupRegistry([string]$nekoboxExe) {
    try {
        $startupRegPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
        $startupName = "Nekobox"
        New-ItemProperty -Path $startupRegPath -Name $startupName -Value "`"$nekoboxExe`"" -PropertyType String -Force | Out-Null
        Write-Log "Nekobox added to Windows startup (registry method)" "Success"
    } catch {
        Write-Log "Failed to add Nekobox to startup registry: $($_.Exception.Message)" "Warning"
    }
}

function Add-NekoboxToStartupFolder([string]$nekoboxExe) {
    try {
        $startupFolder = [Environment]::GetFolderPath("Startup")
        $startupShortcutPath = Join-Path $startupFolder "Nekobox.lnk"
        New-ShellShortcut -ShortcutPath $startupShortcutPath -TargetPath $nekoboxExe -WorkingDirectory $script:Apps.Nekobox.InstallPath -Description "Nekobox VPN Client - Auto Start" -IconLocation $nekoboxExe | Out-Null
        Write-Log "Nekobox startup shortcut created: $startupShortcutPath" "Success"
    } catch {
        Write-Log "Failed to create startup shortcut: $($_.Exception.Message)" "Warning"
    }
}



function Add-NekoboxDesktopShortcut {
    Write-Log "Creating Nekobox desktop shortcut..." "Info"

    try {
        # Direct executable execution as requested by user (no batch launcher)
        $nekoboxExe = Get-NekoboxExecutablePath

        if (-not $nekoboxExe -or -not (Test-Path $nekoboxExe)) {
            Write-Log "Nekobox executable not found for desktop shortcut" "Warning"
            return
        }

        $desktopPath = $script:Config.DesktopPath
        $shortcutPath = Join-Path $desktopPath "Nekobox.lnk"

        New-ShellShortcut -ShortcutPath $shortcutPath -TargetPath $nekoboxExe -WorkingDirectory $script:Apps.Nekobox.InstallPath -Description "Nekobox VPN Client" -IconLocation $nekoboxExe | Out-Null

        Write-Log "Desktop shortcut created: $shortcutPath" "Success"

    } catch {
        Write-Log "Failed to create desktop shortcut: $($_.Exception.Message)" "Warning"
    }
}

function Add-NekoboxToTaskbar {
    Write-Log "Pinning Nekobox to taskbar..." "Info"

    $nekoboxExe = Get-NekoboxExecutablePath
    if (-not $nekoboxExe -or -not (Test-Path $nekoboxExe)) {
        Write-Log "Nekobox executable not found for taskbar pinning" "Warning"
        return
    }

    try {
        if (Invoke-NekoboxComTaskbarPin $nekoboxExe) { return }
        if (Invoke-NekoboxTaskbarDirectoryPin $nekoboxExe) { return }
        Set-NekoboxExecutablePermissions $nekoboxExe
        Write-Log "Taskbar pinning attempted - may require manual pinning" "Warning"
    } catch {
        Write-Log "Failed to pin Nekobox to taskbar: $($_.Exception.Message)" "Warning"
    }
}

function Invoke-NekoboxComTaskbarPin([string]$nekoboxExe) {
    try {
        $shell = New-Object -ComObject Shell.Application
        $folder = $shell.Namespace((Split-Path $nekoboxExe))
        $item = $folder.ParseName((Split-Path $nekoboxExe -Leaf))

        $verbs = $item.Verbs()
        foreach ($verb in $verbs) {
            if ($verb.Name -match "taskbar" -or $verb.Name -match "Pin") {
                $verb.DoIt()
                Write-Log "Nekobox pinned to taskbar (COM method)" "Success"
                return $true
            }
        }
        return $false
    } catch {
        Write-Log "COM method failed: $($_.Exception.Message)" "Warning"
        return $false
    }
}

function Invoke-NekoboxTaskbarDirectoryPin([string]$nekoboxExe) {
    try {
        $quickLaunchPath = "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
        if (Test-Path $quickLaunchPath) {
            $shortcutPath = Join-Path $quickLaunchPath "Nekobox.lnk"
            New-ShellShortcut -ShortcutPath $shortcutPath -TargetPath $nekoboxExe -WorkingDirectory $script:Apps.Nekobox.InstallPath -Description "Nekobox VPN Client" -IconLocation $nekoboxExe | Out-Null
            Write-Log "Nekobox shortcut added to taskbar directory" "Success"
            return $true
        }
        return $false
    } catch {
        Write-Log "Taskbar directory method failed: $($_.Exception.Message)" "Warning"
        return $false
    }
}

function Set-NekoboxExecutablePermissions([string]$nekoboxExe) {
    try {
        $acl = Get-Acl $nekoboxExe
        $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule("Everyone", "FullControl", "Allow")
        $acl.SetAccessRule($accessRule)
        Set-Acl -Path $nekoboxExe -AclObject $acl
        Write-Log "Set full permissions for Nekobox executable" "Success"
    } catch {
        Write-Log "Could not set permissions: $($_.Exception.Message)" "Warning"
    }
}

# ===================================================================
# TESTING FUNCTIONS
# ===================================================================

function Invoke-SystemTest {
    Write-Host "=== System Installation Test ===" -ForegroundColor Yellow
    Write-Host ""

    $testResults = @()
    $testResults += Test-PythonInstallation
    $testResults += Test-ChromeInstallation
    $testResults += Test-NekoboxInstallation

    Show-TestResults $testResults
}

function Test-PythonInstallation {
    try {
        $pythonVersion = python --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Python: $pythonVersion" "Success"
            return "Python: PASS"
        } else {
            Write-Log "Python: Not installed" "Error"
            return "Python: FAIL"
        }
    } catch {
        Write-Log "Python: Not installed" "Error"
        return "Python: FAIL"
    }
}

function Test-ChromeInstallation {
    $chromeInstalled = Get-ChromeInstallationInfo
    if ($chromeInstalled) {
        Write-Log "Chrome: Installed ($($chromeInstalled.DisplayVersion))" "Success"
        return "Chrome: PASS"
    } else {
        Write-Log "Chrome: Not installed" "Error"
        return "Chrome: FAIL"
    }
}

function Test-NekoboxInstallation {
    if (Test-Path -Path $script:Apps.Nekobox.InstallPath) {
        $nekoboxFiles = Get-ChildItem -Path $script:Apps.Nekobox.InstallPath -Filter "*.exe" -ErrorAction SilentlyContinue
        if ($nekoboxFiles.Count -gt 0) {
            Write-Log "Nekobox: Installed ($($nekoboxFiles.Count) executables)" "Success"
            return "Nekobox: PASS"
        } else {
            Write-Log "Nekobox: Directory exists but no executables found" "Error"
            return "Nekobox: FAIL"
        }
    } else {
        Write-Log "Nekobox: Not installed" "Error"
        return "Nekobox: FAIL"
    }
}

function Show-TestResults([string[]]$testResults) {
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
    Write-Host "=== Testing Google Drive Access ===" -ForegroundColor Yellow
    Write-Host ""

    $downloader = [DownloadEngine]::new($script:Config.UserAgent, $script:Config.TempDir)
    $testPath = Join-Path $script:Config.TempDir "gdrive_test.tmp"

    Write-Log "Testing Nekobox file ID: $($script:GoogleDriveFiles.Nekobox)" "Info"

    if (-not (Test-PythonAvailability)) { return }
    if (-not $downloader.EnsureGdown()) {
        Write-Log "gdown not available and could not be installed" "Error"
        return
    }

    Test-GoogleDriveDownload $downloader $testPath
}

function Test-PythonAvailability {
    try {
        $pythonVersion = python --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Python available: $pythonVersion" "Success"
            return $true
        } else {
            Write-Log "Python not available" "Error"
            return $false
        }
    } catch {
        Write-Log "Python not available" "Error"
        return $false
    }
}

function Test-GoogleDriveDownload([DownloadEngine]$downloader, [string]$testPath) {
    if ($downloader.DownloadGoogleDriveFile($script:GoogleDriveFiles.Nekobox, $testPath)) {
        $fileSize = (Get-Item -Path $testPath).Length
        Write-Log "Test PASSED: Downloaded $([math]::Round($fileSize/1MB, 2)) MB successfully" "Success"
        Write-Log "File validation: PASS" "Success"
        Remove-Item -Path $testPath -Force -ErrorAction SilentlyContinue
        Write-Log "Test file cleaned up" "Info"
    } else {
        Write-Log "Test FAILED: Could not download file" "Error"
        Write-Log "Check file permissions: https://drive.google.com/file/d/$($script:GoogleDriveFiles.Nekobox)/view" "Info"
    }
}

function Invoke-Benchmark {
    Write-Host "=== Performance Benchmark ===" -ForegroundColor Yellow
    Write-Host ""

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $startMemory = [System.GC]::GetTotalMemory($false)

    try {
        Test-GoogleDriveAccess
        $stopwatch.Stop()
        $endMemory = [System.GC]::GetTotalMemory($false)

        Show-BenchmarkResults $stopwatch $startMemory $endMemory
        Show-CodeMetrics
    } catch {
        $stopwatch.Stop()
        Write-Log "Benchmark failed: $($_.Exception.Message)" "Error"
    }
}

function Show-BenchmarkResults([System.Diagnostics.Stopwatch]$stopwatch, [long]$startMemory, [long]$endMemory) {
    Write-Host ""
    Write-Host "=== Benchmark Results ===" -ForegroundColor Green
    Write-Host "Execution Time: $($stopwatch.Elapsed.TotalSeconds) seconds" -ForegroundColor White
    Write-Host "Memory Used: $([math]::Round(($endMemory - $startMemory) / 1MB, 2)) MB" -ForegroundColor White
    Write-Host "Script Version: $($script:Config.Version)" -ForegroundColor White
}

function Show-CodeMetrics {
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
}

# ===================================================================
# MAIN EXECUTION FUNCTION
# ===================================================================

function Start-WindowsSetup {
    try {
        Initialize-Logging
        Show-WelcomeBanner

        if (Invoke-TestModeIfRequested) { return }

        Test-Prerequisites
        $selectedChromeVersion = Get-ChromeVersionSelection

        Show-InstallationConfiguration $selectedChromeVersion

        if (-not (Confirm-InstallationProceed)) { return }

        $downloader = [DownloadEngine]::new($script:Config.UserAgent, $script:Config.TempDir)

        Invoke-InstallationProcess $downloader $selectedChromeVersion
        Show-InstallationSummary

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

function Show-WelcomeBanner {
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                 Ultimate Windows Setup Script               ║" -ForegroundColor Cyan
    Write-Host "║              Chrome + Python + Nekobox Installer            ║" -ForegroundColor Cyan
    Write-Host "║                   Enhanced Edition v$($script:Config.Version)                   ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

function Invoke-TestModeIfRequested {
    if ($Test) {
        Invoke-SystemTest
        return $true
    }

    if ($TestGDrive) {
        Test-GoogleDriveAccess
        return $true
    }

    if ($Benchmark) {
        Invoke-Benchmark
        return $true
    }

    return $false
}

function Get-ChromeVersionSelection {
    if (-not $SkipChrome) {
        return Select-ChromeVersion
    }
    return $null
}

function Show-InstallationConfiguration([string]$selectedChromeVersion) {
    Write-Host ""
    Write-Host "=== Windows Setup Configuration ===" -ForegroundColor Yellow
    if (-not $SkipChrome -and $selectedChromeVersion) {
        Write-Host "Chrome Version: $($script:GoogleDriveFiles.Chrome[$selectedChromeVersion].Name)" -ForegroundColor Cyan
    }
    Write-Host "Skip Python: $SkipPython" -ForegroundColor Cyan
    Write-Host "Skip Chrome: $SkipChrome" -ForegroundColor Cyan
    Write-Host "Skip Nekobox: $SkipNekobox" -ForegroundColor Cyan
    Write-Host "Silent Mode: $Silent" -ForegroundColor Cyan
    Write-Host ""
}

function Confirm-InstallationProceed {
    if (-not $Silent) {
        $confirm = Read-Host "Proceed with installation? (Y/N)"
        if ($confirm -notmatch '^[Yy]') {
            Write-Log "Installation cancelled by user" "Warning"
            return $false
        }
    }
    return $true
}

function Invoke-InstallationProcess([DownloadEngine]$downloader, [string]$selectedChromeVersion) {
    Write-Host ""
    Write-Host "=== Starting Installation Process ===" -ForegroundColor Green

    if (-not $SkipPython) {
        Install-Python -Downloader $downloader
    }

    if (-not $SkipChrome -and $selectedChromeVersion) {
        Install-Chrome -Downloader $downloader -ChromeVersion $selectedChromeVersion
    }

    if (-not $SkipNekobox) {
        Install-Nekobox -Downloader $downloader
    }

    Write-Host ""
    Write-Host "=== Installation Completed Successfully ===" -ForegroundColor Green
    Write-Log "All installations completed successfully" "Success"
}

function Show-InstallationSummary {
    Write-Host ""
    Write-Host "=== Installation Summary ===" -ForegroundColor Yellow

    Show-PythonSummary
    Show-ChromeSummary
    Show-NekoboxSummary

    Write-Host ""
    Write-Host "📋 Log file: $($script:Config.LogFile)" -ForegroundColor Cyan
    Write-Host "🎉 Setup completed! Some changes may require a restart to take full effect." -ForegroundColor Green
}

function Show-PythonSummary {
    if (-not $SkipPython) {
        try {
            $pythonVersion = python --version 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "🐍 Python: $pythonVersion" -ForegroundColor Green
                $gdownCheck = Start-Process -FilePath "python" -ArgumentList "-c", "import gdown" -Wait -PassThru -WindowStyle Hidden -RedirectStandardError "$env:TEMP\gdown_summary_check.txt"
                if ($gdownCheck.ExitCode -eq 0) {
                    Write-Host "   gdown: Available for Google Drive downloads" -ForegroundColor White
                }
                Remove-Item "$env:TEMP\gdown_summary_check.txt" -Force -ErrorAction SilentlyContinue
            } else {
                Write-Host "🐍 Python: Installation may have failed" -ForegroundColor Red
            }
        } catch {
            Write-Host "🐍 Python: Installation may have failed" -ForegroundColor Red
        }
    } else {
        Write-Host "🐍 Python: Skipped" -ForegroundColor Yellow
    }
}

function Show-ChromeSummary {
    if (-not $SkipChrome) {
        $chromeInstalled = Get-ChromeInstallationInfo
        $chromeFound = Get-ChromeExecutablePath

        if ($chromeInstalled -or $chromeFound) {
            $version = if ($chromeInstalled) { $chromeInstalled.DisplayVersion } else { "Installed" }
            Write-Host "🌐 Chrome: $version" -ForegroundColor Green
            Write-Host "   Updates: Blocked comprehensively" -ForegroundColor White
            Write-Host "   Taskbar: Attempted to pin" -ForegroundColor White

            if ($chromeFound) {
                Write-Host "   Location: $chromeFound" -ForegroundColor White
            } else {
                Write-Host "   Warning: Chrome executable not found in standard locations" -ForegroundColor Yellow
            }
        } else {
            Write-Host "🌐 Chrome: Installation may have failed" -ForegroundColor Red
        }
    } else {
        Write-Host "🌐 Chrome: Skipped" -ForegroundColor Yellow
    }
}

function Show-NekoboxSummary {
    if (-not $SkipNekobox) {
        if (Test-Path -Path $script:Apps.Nekobox.InstallPath) {
            $nekoboxFiles = Get-ChildItem -Path $script:Apps.Nekobox.InstallPath -Filter "*.exe" -ErrorAction SilentlyContinue
            if ($nekoboxFiles.Count -gt 0) {
                Write-Host "🔒 Nekobox: Installed ($($nekoboxFiles.Count) executables)" -ForegroundColor Green
                Write-Host "   Location: $($script:Apps.Nekobox.InstallPath)" -ForegroundColor White
                Write-Host "   Desktop Shortcut: Created" -ForegroundColor White
                Write-Host "   Taskbar: Pinned" -ForegroundColor White

                $mainExe = $nekoboxFiles | Where-Object { $_.Name -like "*nekoray*" -or $_.Name -like "*nekobox*" } | Select-Object -First 1
                if ($mainExe) {
                    Write-Host "   Main Executable: $($mainExe.Name)" -ForegroundColor White
                }
            } else {
                Write-Host "🔒 Nekobox: Installation may have failed (no executables found)" -ForegroundColor Red
            }
        } else {
            Write-Host "🔒 Nekobox: Installation may have failed (directory not found)" -ForegroundColor Red
        }
    } else {
        Write-Host "🔒 Nekobox: Skipped" -ForegroundColor Yellow
    }
}

# ===================================================================
# SCRIPT ENTRY POINT
# ===================================================================

if ($MyInvocation.InvocationName -ne '.') {
    Start-WindowsSetup
}
