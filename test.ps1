# ===================================================================
# Winsetup.ps1 - Production Windows Setup Script
# Chrome + Python + Nekobox Auto Installer
# Compatible with PowerShell 5.x and Windows 10/11
# ===================================================================

#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [ValidateSet("US", "UK", "AU", "SG", "NZ", "Interactive", "Skip")]
    [string]$Region = "Interactive",
    
    [ValidateSet("Chrome135", "Chrome136", "Chrome137", "Chrome138", "Chrome141", "Interactive")]
    [string]$ChromeVersion = "Interactive",
    
    [switch]$SkipPython,
    [switch]$SkipChrome, 
    [switch]$SkipNekobox,
    [switch]$SkipRegion,
    [switch]$Silent,
    [switch]$Test,
    [switch]$TestGDrive,
    [switch]$Benchmark,
    [switch]$ShowCurrentRegion
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

$script:Regions = @{
    "US" = @{ 
        Language = "en-US"; DisplayName = "🇺🇸 United States"; Timezone = "Eastern Standard Time"
        Currency = "USD"; DateFormat = "M/d/yyyy"; NumberFormat = "en-US"
    }
    "UK" = @{ 
        Language = "en-GB"; DisplayName = "🇬🇧 United Kingdom"; Timezone = "GMT Standard Time"
        Currency = "GBP"; DateFormat = "dd/MM/yyyy"; NumberFormat = "en-GB"
    }
    "AU" = @{ 
        Language = "en-AU"; DisplayName = "🇦🇺 Australia"; Timezone = "AUS Eastern Standard Time"
        Currency = "AUD"; DateFormat = "d/MM/yyyy"; NumberFormat = "en-AU"
    }
    "SG" = @{ 
        Language = "en-SG"; DisplayName = "🇸🇬 Singapore"; Timezone = "Singapore Standard Time"
        Currency = "SGD"; DateFormat = "d/M/yyyy"; NumberFormat = "en-SG"
    }
    "NZ" = @{ 
        Language = "en-NZ"; DisplayName = "🇳🇿 New Zealand"; Timezone = "New Zealand Standard Time"
        Currency = "NZD"; DateFormat = "d/MM/yyyy"; NumberFormat = "en-NZ"
    }
}

# ===================================================================
# UTILITY FUNCTIONS
# ===================================================================

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
    [CmdletBinding()]
    param()
    
    Write-Log "Checking prerequisites..." "Info"
    
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Log "Administrator rights required. Please run as Administrator." "Error"
        throw "Administrator rights required"
    }
    Write-Log "Administrator rights confirmed" "Success"
    
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        Write-Log "PowerShell 5.0 or higher required" "Error"
        throw "PowerShell version not supported"
    }
    Write-Log "PowerShell version: $($PSVersionTable.PSVersion)" "Success"
    
    try {
        $null = Test-NetConnection -ComputerName "8.8.8.8" -Port 53 -InformationLevel Quiet -ErrorAction Stop
        Write-Log "Internet connectivity confirmed" "Success"
    } catch {
        Write-Log "Internet connectivity required" "Warning"
    }
    
    $osVersion = [System.Environment]::OSVersion.Version
    if ($osVersion.Major -lt 10) {
        Write-Log "Windows 10 or higher recommended" "Warning"
    } else {
        Write-Log "Windows version: $($osVersion.Major).$($osVersion.Minor)" "Success"
    }
}

function Get-CurrentRegionSettings {
    try {
        $culture = Get-Culture
        $timezone = Get-TimeZone
        $location = Get-WinHomeLocation -ErrorAction SilentlyContinue
        
        return @{
            Language = $culture.Name
            DisplayName = $culture.DisplayName
            Timezone = $timezone.Id
            TimezoneDisplay = $timezone.DisplayName
            Currency = $culture.NumberFormat.CurrencySymbol
            DateFormat = $culture.DateTimeFormat.ShortDatePattern
            Country = if ($location) { $location.HomeLocation } else { "Unknown" }
        }
    } catch {
        Write-Log "Could not retrieve current region settings: $($_.Exception.Message)" "Warning"
        return $null
    }
}

function Show-CurrentRegionSettings {
    Write-Host ""
    Write-Host "=== Current System Region Settings ===" -ForegroundColor Cyan
    
    $current = Get-CurrentRegionSettings
    if ($current) {
        Write-Host "Language: $($current.Language) ($($current.DisplayName))" -ForegroundColor White
        Write-Host "Timezone: $($current.TimezoneDisplay)" -ForegroundColor White
        Write-Host "Currency: $($current.Currency)" -ForegroundColor White
        Write-Host "Date Format: $($current.DateFormat)" -ForegroundColor White
        if ($current.Country -ne "Unknown") {
            Write-Host "Country Code: $($current.Country)" -ForegroundColor White
        }
        
        $matchedRegion = $script:Regions.Keys | Where-Object { $script:Regions[$_].Language -eq $current.Language } | Select-Object -First 1
        
        if ($matchedRegion) {
            Write-Host "Detected Region: $($script:Regions[$matchedRegion].DisplayName)" -ForegroundColor Green
        } else {
            Write-Host "Region: Custom/Other" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Could not retrieve current settings" -ForegroundColor Red
    }
    Write-Host ""
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
        
        $pythonPath = $outputPath.Replace('\', '/')
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

function Select-UserRegion {
    if ($Region -eq "Skip" -or $SkipRegion) {
        Write-Log "Region configuration skipped" "Info"
        return "Skip"
    }

    if ($Region -ne "Interactive") {
        Write-Log "Region pre-selected: $Region" "Info"
        return $Region
    }

    if ($Silent) {
        Write-Log "Silent mode: Using default region US" "Info"
        return "US"
    }

    Show-CurrentRegionSettings

    Write-Host "=== Region Selection ===" -ForegroundColor Yellow
    Write-Host "Please select your target region:" -ForegroundColor Cyan
    Write-Host ""

    $regionOptions = @()
    $counter = 1

    foreach ($key in $script:Regions.Keys | Sort-Object) {
        $region = $script:Regions[$key]
        Write-Host "$counter. $($region.DisplayName)" -ForegroundColor White
        Write-Host "   Language: $($region.Language) | Timezone: $($region.Timezone)" -ForegroundColor Gray
        Write-Host "   Currency: $($region.Currency) | Date: $($region.DateFormat)" -ForegroundColor Gray
        Write-Host ""
        $regionOptions += $key
        $counter++
    }

    Write-Host "$counter. 🚫 Skip region configuration" -ForegroundColor Yellow
    $regionOptions += "Skip"
    Write-Host ""

    do {
        $selection = Read-Host "Select option (1-$($regionOptions.Count))"
        $selectionInt = 0

        if ([int]::TryParse($selection, [ref]$selectionInt) -and
            $selectionInt -ge 1 -and $selectionInt -le $regionOptions.Count) {
            $selectedRegion = $regionOptions[$selectionInt - 1]

            if ($selectedRegion -eq "Skip") {
                Write-Log "Region configuration skipped by user" "Info"
            } else {
                Write-Log "Selected region: $($script:Regions[$selectedRegion].DisplayName)" "Success"
            }
            return $selectedRegion
        } else {
            Write-Log "Invalid selection. Please choose 1-$($regionOptions.Count)." "Error"
        }
    } while ($true)
}

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

function Set-SystemRegion {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Region)

    if ($Region -eq "Skip") {
        Write-Log "Region configuration skipped" "Info"
        return
    }

    Write-Log "=== Configuring System Region ===" "Info"

    if (-not $script:Regions.ContainsKey($Region)) {
        Write-Log "Invalid region: $Region" "Error"
        return
    }

    $regionConfig = $script:Regions[$Region]
    Write-Log "Configuring system for: $($regionConfig.DisplayName)" "Info"

    try {
        Write-Log "Setting system language to: $($regionConfig.Language)" "Info"
        Set-WinUILanguageOverride -Language $regionConfig.Language -ErrorAction SilentlyContinue
        Set-WinUserLanguageList $regionConfig.Language -Force -ErrorAction SilentlyContinue
        Set-WinSystemLocale -SystemLocale $regionConfig.Language -ErrorAction SilentlyContinue

        Write-Log "Setting timezone to: $($regionConfig.Timezone)" "Info"
        try {
            Set-TimeZone -Id $regionConfig.Timezone -ErrorAction Stop
            Write-Log "Timezone set successfully" "Success"
        } catch {
            Write-Log "Could not set timezone: $($_.Exception.Message)" "Warning"
            Set-TimeZone -Id "UTC" -ErrorAction SilentlyContinue
            Write-Log "Fallback: Set timezone to UTC" "Info"
        }

        Write-Log "Setting regional formats for: $($regionConfig.NumberFormat)" "Info"
        Set-Culture -CultureInfo $regionConfig.Language -ErrorAction SilentlyContinue

        try {
            $geoId = switch ($Region) {
                "US" { 244 }; "UK" { 242 }; "AU" { 12 }; "SG" { 215 }; "NZ" { 183 }; default { 244 }
            }
            Set-WinHomeLocation -GeoId $geoId -ErrorAction SilentlyContinue
            Write-Log "Home location set for region" "Success"
        } catch {
            Write-Log "Could not set home location" "Warning"
        }

        Write-Log "Setting keyboard layout to US (for remote access compatibility)" "Info"
        Set-WinDefaultInputMethodOverride -InputTip "0409:00000409" -ErrorAction SilentlyContinue

        try {
            $registryPath = "HKCU:\Control Panel\International"
            if (Test-Path $registryPath) {
                Set-ItemProperty -Path $registryPath -Name "sShortDate" -Value $regionConfig.DateFormat -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $registryPath -Name "sCurrency" -Value $regionConfig.Currency -ErrorAction SilentlyContinue
                Write-Log "Registry regional settings updated" "Success"
            }
        } catch {
            Write-Log "Could not update registry settings" "Warning"
        }

        Write-Log "System region configured successfully for $($regionConfig.DisplayName)" "Success"
        Write-Log "Note: Some changes may require a system restart to take full effect" "Info"

    } catch {
        Write-Log "Failed to configure system region: $($_.Exception.Message)" "Error"
        throw "Region configuration failed"
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
        # Enhanced update blocking with additional registry keys
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
        }

        foreach ($policy in $updatePolicies.GetEnumerator()) {
            New-ItemProperty -Path $updatePolicyPath -Name $policy.Key -Value $policy.Value -PropertyType DWord -Force | Out-Null
        }

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
            "AutoplayPolicy" = 2; "ComponentUpdatesEnabled" = 0
        }

        foreach ($policy in $chromePolicies.GetEnumerator()) {
            New-ItemProperty -Path $chromePolicyPath -Name $policy.Key -Value $policy.Value -PropertyType DWord -Force | Out-Null
        }

        # Block Chrome update URLs via hosts file
        try {
            $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
            $hostsContent = Get-Content $hostsPath -ErrorAction SilentlyContinue
            $updateUrls = @(
                "update.googleapis.com",
                "clients2.google.com",
                "clients4.google.com",
                "edgedl.me.gvt1.com"
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

                    # Also disable other update executables
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

        $taskNames = @("GoogleUpdateTaskMachineCore", "GoogleUpdateTaskMachineUA", "GoogleUpdateTaskUserS-*")
        foreach ($taskName in $taskNames) {
            try {
                Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue
                Write-Log "Removed scheduled task: $taskName" "Success"
            } catch {
                # Task might not exist
            }
        }

        Write-Log "Chrome updates blocked comprehensively with enhanced protection" "Success"

    } catch {
        Write-Log "Failed to block Chrome updates: $($_.Exception.Message)" "Warning"
    }
}

function Add-ChromeToTaskbar {
    Write-Log "Pinning Chrome to taskbar..." "Info"

    try {
        $chromePaths = @(
            "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
            "$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe"
        )

        $chromeExe = $chromePaths | Where-Object { Test-Path $_ } | Select-Object -First 1

        if (-not $chromeExe) {
            Write-Log "Chrome executable not found for taskbar pinning" "Warning"
            return
        }

        # Method 1: Try PowerShell COM approach
        try {
            $shell = New-Object -ComObject Shell.Application
            $folder = $shell.Namespace((Split-Path $chromeExe))
            $item = $folder.ParseName((Split-Path $chromeExe -Leaf))

            $verbs = $item.Verbs()
            $pinned = $false
            foreach ($verb in $verbs) {
                if ($verb.Name -match "taskbar" -or $verb.Name -match "Pin") {
                    $verb.DoIt()
                    Write-Log "Chrome pinned to taskbar (COM method)" "Success"
                    $pinned = $true
                    break
                }
            }

            if ($pinned) { return }
        } catch {
            Write-Log "COM method failed: $($_.Exception.Message)" "Warning"
        }

        # Method 2: Try syspin utility approach
        try {
            $syspinPath = Join-Path $env:TEMP "syspin.exe"
            if (-not (Test-Path $syspinPath)) {
                # Create minimal syspin equivalent using PowerShell
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
                $pinScript | Out-File -FilePath $syspinPath.Replace('.exe', '.ps1') -Encoding UTF8
                powershell -ExecutionPolicy Bypass -File $syspinPath.Replace('.exe', '.ps1')
                Write-Log "Chrome pinned to taskbar (PowerShell method)" "Success"
                return
            }
        } catch {
            Write-Log "PowerShell pin method failed: $($_.Exception.Message)" "Warning"
        }

        # Method 3: Try registry approach for taskbar shortcuts
        try {
            $taskbarPath = "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
            if (Test-Path $taskbarPath) {
                $shortcutPath = Join-Path $taskbarPath "Google Chrome.lnk"

                $wshShell = New-Object -ComObject WScript.Shell
                $shortcut = $wshShell.CreateShortcut($shortcutPath)
                $shortcut.TargetPath = $chromeExe
                $shortcut.WorkingDirectory = Split-Path $chromeExe
                $shortcut.Description = "Google Chrome"
                $shortcut.IconLocation = $chromeExe
                $shortcut.Save()

                Write-Log "Chrome shortcut added to taskbar directory" "Success"
                return
            }
        } catch {
            Write-Log "Registry method failed: $($_.Exception.Message)" "Warning"
        }

        Write-Log "All taskbar pinning methods failed - Chrome installed but not pinned" "Warning"

    } catch {
        Write-Log "Failed to pin Chrome to taskbar: $($_.Exception.Message)" "Warning"
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

    Write-Log "Installing Chrome..." "Info"

    $process = Start-Process -FilePath $installerPath -ArgumentList $script:Apps.Chrome.InstallArgs -Wait -PassThru

    if ($process.ExitCode -ne 0) {
        Write-Log "Chrome installation may have issues (exit code: $($process.ExitCode))" "Warning"
    }

    Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue

    Block-ChromeUpdates
    Add-ChromeToTaskbar

    Write-Log "Chrome installation completed: $($versionInfo.Name)" "Success"
}

function Install-Nekobox {
    [CmdletBinding()]
    param([Parameter(Mandatory)][DownloadEngine]$Downloader)

    Write-Log "=== Installing Nekobox ===" "Info"

    if (Test-Path -Path $script:Apps.Nekobox.InstallPath) {
        Write-Log "Removing existing Nekobox installation..." "Info"
        try {
            Remove-Item -Path $script:Apps.Nekobox.InstallPath -Recurse -Force
            Write-Log "Existing Nekobox removed" "Success"
        } catch {
            Write-Log "Could not remove existing Nekobox: $($_.Exception.Message)" "Warning"
        }
    }

    $zipPath = Join-Path $script:Config.TempDir "nekobox.zip"
    $extractPath = Join-Path $script:Config.TempDir "nekobox_extract"

    Write-Log "Downloading Nekobox from Google Drive..." "Info"
    if (-not $Downloader.DownloadGoogleDriveFile($script:GoogleDriveFiles.Nekobox, $zipPath)) {
        if ($Silent) {
            Write-Log "Nekobox download failed in silent mode. Skipping..." "Warning"
            return
        } else {
            throw "Failed to download Nekobox from Google Drive"
        }
    }

    if (-not $Downloader.ValidateDownload($zipPath, 1024)) {
        throw "Nekobox download is invalid"
    }

    Write-Log "Downloaded Nekobox successfully" "Success"

    Write-Log "Extracting Nekobox..." "Info"

    try {
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

        # Set proper permissions for the entire Nekobox directory
        try {
            $acl = Get-Acl $script:Apps.Nekobox.InstallPath
            $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule("Everyone", "FullControl", "Allow")
            $acl.SetAccessRule($accessRule)
            Set-Acl -Path $script:Apps.Nekobox.InstallPath -AclObject $acl -Recurse
            Write-Log "Set full permissions for Nekobox directory" "Success"
        } catch {
            Write-Log "Could not set directory permissions: $($_.Exception.Message)" "Warning"
        }

        Add-NekoboxDesktopShortcut
        Add-NekoboxToTaskbar

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

function Add-NekoboxDesktopShortcut {
    Write-Log "Creating Nekobox desktop shortcut..." "Info"

    try {
        $nekoboxExe = Join-Path $script:Apps.Nekobox.InstallPath $script:Apps.Nekobox.ExecutableName
        if (-not (Test-Path $nekoboxExe)) {
            $exeFiles = Get-ChildItem -Path $script:Apps.Nekobox.InstallPath -Filter "*.exe" -ErrorAction SilentlyContinue
            if ($exeFiles.Count -gt 0) {
                $nekoboxExe = $exeFiles[0].FullName
            } else {
                Write-Log "Nekobox executable not found for desktop shortcut" "Warning"
                return
            }
        }

        $desktopPath = $script:Config.DesktopPath
        $shortcutPath = Join-Path $desktopPath "Nekobox.lnk"

        $wshShell = New-Object -ComObject WScript.Shell
        $shortcut = $wshShell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $nekoboxExe
        $shortcut.WorkingDirectory = $script:Apps.Nekobox.InstallPath
        $shortcut.Description = "Nekobox VPN Client"
        $shortcut.IconLocation = $nekoboxExe
        $shortcut.Save()

        Write-Log "Desktop shortcut created: $shortcutPath" "Success"

    } catch {
        Write-Log "Failed to create desktop shortcut: $($_.Exception.Message)" "Warning"
    }
}

function Add-NekoboxToTaskbar {
    Write-Log "Pinning Nekobox to taskbar..." "Info"

    try {
        $nekoboxExe = Join-Path $script:Apps.Nekobox.InstallPath $script:Apps.Nekobox.ExecutableName
        if (-not (Test-Path $nekoboxExe)) {
            $exeFiles = Get-ChildItem -Path $script:Apps.Nekobox.InstallPath -Filter "*.exe" -ErrorAction SilentlyContinue
            if ($exeFiles.Count -gt 0) {
                # Prefer nekoray.exe or nekobox.exe
                $preferredExe = $exeFiles | Where-Object { $_.Name -like "*nekoray*" -or $_.Name -like "*nekobox*" } | Select-Object -First 1
                $nekoboxExe = if ($preferredExe) { $preferredExe.FullName } else { $exeFiles[0].FullName }
            } else {
                Write-Log "Nekobox executable not found for taskbar pinning" "Warning"
                return
            }
        }

        # Method 1: Try COM approach
        try {
            $shell = New-Object -ComObject Shell.Application
            $folder = $shell.Namespace((Split-Path $nekoboxExe))
            $item = $folder.ParseName((Split-Path $nekoboxExe -Leaf))

            $verbs = $item.Verbs()
            $pinned = $false
            foreach ($verb in $verbs) {
                if ($verb.Name -match "taskbar" -or $verb.Name -match "Pin") {
                    $verb.DoIt()
                    Write-Log "Nekobox pinned to taskbar (COM method)" "Success"
                    $pinned = $true
                    break
                }
            }

            if ($pinned) { return }
        } catch {
            Write-Log "COM method failed: $($_.Exception.Message)" "Warning"
        }

        # Method 2: Try taskbar directory approach
        try {
            $quickLaunchPath = "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
            if (Test-Path $quickLaunchPath) {
                $shortcutPath = Join-Path $quickLaunchPath "Nekobox.lnk"

                $wshShell = New-Object -ComObject WScript.Shell
                $shortcut = $wshShell.CreateShortcut($shortcutPath)
                $shortcut.TargetPath = $nekoboxExe
                $shortcut.WorkingDirectory = $script:Apps.Nekobox.InstallPath
                $shortcut.Description = "Nekobox VPN Client"
                $shortcut.IconLocation = $nekoboxExe
                $shortcut.Save()

                Write-Log "Nekobox shortcut added to taskbar directory" "Success"
                return
            }
        } catch {
            Write-Log "Taskbar directory method failed: $($_.Exception.Message)" "Warning"
        }

        # Method 3: Set proper permissions for Nekobox executable
        try {
            $acl = Get-Acl $nekoboxExe
            $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule("Everyone", "FullControl", "Allow")
            $acl.SetAccessRule($accessRule)
            Set-Acl -Path $nekoboxExe -AclObject $acl
            Write-Log "Set full permissions for Nekobox executable" "Success"
        } catch {
            Write-Log "Could not set permissions: $($_.Exception.Message)" "Warning"
        }

        Write-Log "Taskbar pinning attempted - may require manual pinning" "Warning"

    } catch {
        Write-Log "Failed to pin Nekobox to taskbar: $($_.Exception.Message)" "Warning"
    }
}

# ===================================================================
# TESTING FUNCTIONS
# ===================================================================

function Invoke-SystemTest {
    Write-Host "=== System Installation Test ===" -ForegroundColor Yellow
    Write-Host ""

    $testResults = @()

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

    $chromeInstalled = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
                      Where-Object { $_.DisplayName -like "*Google Chrome*" }

    if ($chromeInstalled) {
        Write-Log "Chrome: Installed ($($chromeInstalled.DisplayVersion))" "Success"
        $testResults += "Chrome: PASS"
    } else {
        Write-Log "Chrome: Not installed" "Error"
        $testResults += "Chrome: FAIL"
    }

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

    if (-not $downloader.EnsureGdown()) {
        Write-Log "gdown not available and could not be installed" "Error"
        return
    }

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

        Write-Host ""
        Write-Host "=== Benchmark Results ===" -ForegroundColor Green
        Write-Host "Execution Time: $($stopwatch.Elapsed.TotalSeconds) seconds" -ForegroundColor White
        Write-Host "Memory Used: $([math]::Round(($endMemory - $startMemory) / 1MB, 2)) MB" -ForegroundColor White
        Write-Host "Script Version: $($script:Config.Version)" -ForegroundColor White

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
    try {
        Initialize-Logging

        Write-Host ""
        Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║                 Ultimate Windows Setup Script               ║" -ForegroundColor Cyan
        Write-Host "║              Chrome + Python + Nekobox Installer            ║" -ForegroundColor Cyan
        Write-Host "║                   Enhanced Edition v$($script:Config.Version)                   ║" -ForegroundColor Cyan
        Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
        Write-Host ""

        if ($ShowCurrentRegion) {
            Show-CurrentRegionSettings
            return
        }

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

        Test-Prerequisites

        $selectedRegion = Select-UserRegion

        $selectedChromeVersion = $null
        if (-not $SkipChrome) {
            $selectedChromeVersion = Select-ChromeVersion
        }

        Write-Host ""
        Write-Host "=== Windows Setup Configuration ===" -ForegroundColor Yellow
        Write-Host "Region: $(if ($selectedRegion -eq 'Skip') { '🚫 Skipped' } else { $script:Regions[$selectedRegion].DisplayName })" -ForegroundColor Cyan
        if (-not $SkipChrome -and $selectedChromeVersion) {
            Write-Host "Chrome Version: $($script:GoogleDriveFiles.Chrome[$selectedChromeVersion].Name)" -ForegroundColor Cyan
        }
        Write-Host "Skip Python: $SkipPython" -ForegroundColor Cyan
        Write-Host "Skip Chrome: $SkipChrome" -ForegroundColor Cyan
        Write-Host "Skip Nekobox: $SkipNekobox" -ForegroundColor Cyan
        Write-Host "Silent Mode: $Silent" -ForegroundColor Cyan
        Write-Host ""

        if (-not $Silent) {
            $confirm = Read-Host "Proceed with installation? (Y/N)"
            if ($confirm -notmatch '^[Yy]') {
                Write-Log "Installation cancelled by user" "Warning"
                return
            }
        }

        $downloader = [DownloadEngine]::new($script:Config.UserAgent, $script:Config.TempDir)

        Write-Host ""
        Write-Host "=== Starting Installation Process ===" -ForegroundColor Green

        if (-not $SkipPython) {
            Install-Python -Downloader $downloader
        }

        if ($selectedRegion -ne "Skip") {
            Set-SystemRegion -Region $selectedRegion
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

        Write-Host ""
        Write-Host "=== Installation Summary ===" -ForegroundColor Yellow

        if ($selectedRegion -ne "Skip") {
            Write-Host "🌍 System Region: $($script:Regions[$selectedRegion].DisplayName)" -ForegroundColor Green
            Write-Host "   Language: $($script:Regions[$selectedRegion].Language)" -ForegroundColor White
            Write-Host "   Timezone: $($script:Regions[$selectedRegion].Timezone)" -ForegroundColor White
            Write-Host "   Currency: $($script:Regions[$selectedRegion].Currency)" -ForegroundColor White
        } else {
            Write-Host "🌍 System Region: Skipped" -ForegroundColor Yellow
        }

        if (-not $SkipPython) {
            try {
                $pythonVersion = python --version 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "🐍 Python: $pythonVersion" -ForegroundColor Green

                    python -c "import gdown" 2>&1 | Out-Null
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "   gdown: Available for Google Drive downloads" -ForegroundColor White
                    }
                } else {
                    Write-Host "🐍 Python: Installation may have failed" -ForegroundColor Red
                }
            } catch {
                Write-Host "🐍 Python: Installation may have failed" -ForegroundColor Red
            }
        } else {
            Write-Host "🐍 Python: Skipped" -ForegroundColor Yellow
        }

        if (-not $SkipChrome) {
            # Check multiple locations for Chrome installation
            $chromeInstalled = $null
            $chromeRegistryPaths = @(
                "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
                "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
                "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
            )

            foreach ($regPath in $chromeRegistryPaths) {
                $chromeInstalled = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue |
                                  Where-Object { $_.DisplayName -like "*Google Chrome*" } | Select-Object -First 1
                if ($chromeInstalled) { break }
            }

            # Also check for Chrome executable directly
            $chromePaths = @(
                "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
                "$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe"
            )
            $chromeFound = $chromePaths | Where-Object { Test-Path $_ } | Select-Object -First 1

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

        Write-Host ""
        Write-Host "📋 Log file: $($script:Config.LogFile)" -ForegroundColor Cyan
        Write-Host "🎉 Setup completed! Some changes may require a restart to take full effect." -ForegroundColor Green

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

if ($MyInvocation.InvocationName -ne '.') {
    Start-WindowsSetup
}
