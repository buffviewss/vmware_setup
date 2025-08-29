<#
.SYNOPSIS
    Production-ready Windows font fingerprinting tool v3.1
    
.DESCRIPTION
    Installs random Google Fonts to change system font fingerprint with robust network handling,
    caching, history tracking, and comprehensive system integration.
    
.PARAMETER FontsPerRun
    Number of font families to install (1-3). Default: random 2 or 3
    
.PARAMETER IncludeMonospace
    Include monospace fonts in selection. Default: $true
    
.PARAMETER Cleanup
    Remove temporary files after completion. Default: $true
    
.PARAMETER NoRestartExplorer
    Skip Explorer restart after font changes
    
.PARAMETER RestoreDefault
    Restore system fonts to Windows defaults
    
.PARAMETER UseSystemProxy
    Use system proxy settings for downloads
    
.PARAMETER ProxyUrl
    Custom proxy URL for downloads
    
.PARAMETER ProxyCredential
    Proxy authentication credentials
    
.PARAMETER LocalFolder
    Local folder containing font files to install
    
.PARAMETER ExtraUrls
    Additional URLs to try for font downloads
    
.PARAMETER NoSymbolSubstitute
    Skip mapping Segoe UI Symbol to coverage fonts
#>

[CmdletBinding()]
param(
    [ValidateSet(1,2,3)]
    [int]$FontsPerRun = 3,
    [switch]$IncludeMonospace,
    [switch]$Cleanup,
    [switch]$NoRestartExplorer,
    [switch]$RestoreDefault,
    [switch]$UseSystemProxy,
    [string]$ProxyUrl,
    [System.Management.Automation.PSCredential]$ProxyCredential,
    [string]$LocalFolder,
    [string[]]$ExtraUrls,
    [switch]$NoSymbolSubstitute
)

#region Configuration

# Apply one-click defaults
if (-not $PSBoundParameters.ContainsKey('IncludeMonospace')) { $IncludeMonospace = $true }
if (-not $PSBoundParameters.ContainsKey('Cleanup')) { $Cleanup = $true }
if (-not $PSBoundParameters.ContainsKey('FontsPerRun')) { $FontsPerRun = Get-Random -InputObject @(2,3) }

# Constants
$script:CoverageFamilies = @('Noto Sans', 'Noto Serif', 'Noto Sans Symbols 2', 'Noto Sans Symbols')
$script:BaseFamiliesToAugment = @('Segoe UI', 'Arial', 'Times New Roman', 'Courier New', 'Microsoft Sans Serif', 'Segoe UI Symbol', 'Comic Sans MS', 'Impact')
$script:NetworkRetryCount = 3
$script:NetworkBaseDelayMs = 500
$script:HttpTimeoutMinutes = 8
$script:JitterMinMs = 200
$script:JitterMaxMs = 900
$script:MaxFontFilesPerFamily = 6
$script:MaxUiFontFiles = 8
$script:MinValidFontSizeBytes = 10000
$script:MinValidZipSizeBytes = 200

# Paths
$script:TempRoot = Join-Path $env:TEMP ("FontInstall-" + (Get-Date -Format yyyyMMdd-HHmmss))
$script:BackupDir = Join-Path $script:TempRoot "RegistryBackup"
$script:ExtractRoot = Join-Path $script:TempRoot "unzipped"
$script:CacheDir = Join-Path $env:ProgramData "FontRealCache"
$script:LogDir = Join-Path $env:ProgramData "FontReal\logs"
$script:LogFile = Join-Path $script:LogDir ("run-" + (Get-Date -Format yyyyMMdd-HHmmss) + ".log")
$script:InstalledFontsHistory = Join-Path $env:APPDATA "FontReal\installed_fonts.json"

# Global state
$global:JsDelivrFlat = $null

#endregion

#region Core Utilities

function Assert-AdminPrivileges {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
        throw "Please run PowerShell as Administrator."
    }
}

function Initialize-RequiredDirectories {
    $directories = @($script:TempRoot, $script:BackupDir, $script:ExtractRoot, $script:CacheDir, $script:LogDir)
    foreach ($directory in $directories) {
        if (-not (Test-Path $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
    }
}

function Write-LogMessage {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[{0}] {1}" -f $timestamp, $Message
    Write-Host $logLine
    try {
        Add-Content -Path $script:LogFile -Value $logLine -ErrorAction SilentlyContinue
    } catch {}
}

function Start-HumanLikeDelay {
    param(
        [int]$MinMs = $script:JitterMinMs,
        [int]$MaxMs = $script:JitterMaxMs
    )
    Start-Sleep -Milliseconds (Get-Random -Minimum $MinMs -Maximum $MaxMs)
}

function Initialize-TlsSettings {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.ServicePointManager]::SecurityProtocol
    } catch {}
}

#endregion

#region Font History Management

function Get-InstalledFontsHistory {
    if (Test-Path $script:InstalledFontsHistory) {
        try {
            $content = Get-Content $script:InstalledFontsHistory -Raw | ConvertFrom-Json
            return $content.installedFonts
        }
        catch {
            Write-LogMessage ("Failed to read font history: {0}" -f $_.Exception.Message)
            return @()
        }
    }
    return @()
}

function Add-ToInstalledFontsHistory {
    param([string[]]$FontFamilies)
    
    if (-not $FontFamilies -or $FontFamilies.Count -eq 0) {
        return
    }
    
    $existingHistory = Get-InstalledFontsHistory
    $allFonts = @($existingHistory + $FontFamilies) | Select-Object -Unique
    
    # Keep only last 100 fonts to prevent file from growing too large
    if ($allFonts.Count -gt 100) {
        $allFonts = $allFonts | Select-Object -Last 100
    }
    
    $historyData = @{
        lastUpdated = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        installedFonts = $allFonts
    }
    
    try {
        $historyDir = Split-Path $script:InstalledFontsHistory -Parent
        if (-not (Test-Path $historyDir)) {
            New-Item -ItemType Directory -Path $historyDir -Force | Out-Null
        }
        
        $historyData | ConvertTo-Json -Depth 3 | Set-Content $script:InstalledFontsHistory -Encoding UTF8
        Write-LogMessage ("Updated font history with {0} fonts" -f $FontFamilies.Count)
    }
    catch {
        Write-LogMessage ("Failed to update font history: {0}" -f $_.Exception.Message)
    }
}

#endregion

#region Network Operations

function Invoke-WithRetryLogic {
    param(
        [scriptblock]$Action,
        [int]$MaxAttempts = $script:NetworkRetryCount,
        [int]$BaseDelayMs = $script:NetworkBaseDelayMs
    )
    
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            return & $Action
        }
        catch {
            if ($attempt -eq $MaxAttempts) {
                throw
            }
            Start-Sleep -Milliseconds ($BaseDelayMs * [math]::Pow(2, $attempt - 1))
        }
    }
}

function New-ConfiguredHttpClient {
    param(
        [string]$Accept = "*/*",
        [string]$Referer = ""
    )
    
    Initialize-TlsSettings
    Add-Type -AssemblyName System.Net.Http
    
    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
    $handler.AllowAutoRedirect = $true
    
    # Configure proxy
    if ($ProxyUrl) {
        $webProxy = New-Object System.Net.WebProxy($ProxyUrl, $true)
        if ($ProxyCredential) {
            $webProxy.Credentials = $ProxyCredential.GetNetworkCredential()
        } else {
            $webProxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
        }
        $handler.UseProxy = $true
        $handler.Proxy = $webProxy
    } elseif ($UseSystemProxy) {
        $handler.UseProxy = $true
        $handler.Proxy = [System.Net.WebRequest]::DefaultWebProxy
        if ($handler.Proxy) {
            $handler.Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
        }
    } else {
        $handler.UseProxy = $false
    }
    
    $client = New-Object System.Net.Http.HttpClient($handler)
    $client.Timeout = [TimeSpan]::FromMinutes($script:HttpTimeoutMinutes)
    $client.DefaultRequestHeaders.UserAgent.ParseAdd("Mozilla/5.0 (Windows NT 10.0; Win64; x64) PowerShell")
    $client.DefaultRequestHeaders.Accept.ParseAdd($Accept)
    if ($Referer) {
        $client.DefaultRequestHeaders.Referrer = [Uri]$Referer
    }
    
    return $client
}

function Get-HttpStringSimple {
    param(
        [string]$Url,
        [hashtable]$Headers = @{}
    )
    
    $defaultHeaders = @{
        'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
        'Accept' = 'application/json, text/plain, */*'
        'Accept-Language' = 'en-US,en;q=0.9'
        'Cache-Control' = 'no-cache'
    }
    
    foreach ($key in $Headers.Keys) {
        $defaultHeaders[$key] = $Headers[$key]
    }
    
    try {
        return Invoke-RestMethod -Uri $Url -Headers $defaultHeaders -TimeoutSec 30
    }
    catch {
        return Invoke-RestMethod -Uri $Url -TimeoutSec 30
    }
}

function Get-CachedFileOrDownload {
    param(
        [string]$Url,
        [string]$PreferredFileName,
        [string]$Accept = "*/*",
        [string]$Referer = ""
    )
    
    $fileName = if ($PreferredFileName) { $PreferredFileName } else {
        try {
            [System.IO.Path]::GetFileName([Uri]$Url)
        } catch {
            [Guid]::NewGuid().ToString()
        }
    }
    
    $cachedPath = Join-Path $script:CacheDir $fileName
    if (Test-Path $cachedPath) {
        Write-LogMessage ("Cache hit: {0}" -f $fileName)
    } else {
        Write-LogMessage ("Cache miss, downloading: {0}" -f $Url)
        Invoke-WithRetryLogic -Action {
            $client = New-ConfiguredHttpClient -Accept $Accept -Referer $Referer
            try {
                $response = $client.GetAsync($Url, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).Result
                if (-not $response.IsSuccessStatusCode) {
                    throw ("HTTP {0} {1}" -f [int]$response.StatusCode, $response.ReasonPhrase)
                }
                
                $inputStream = $response.Content.ReadAsStreamAsync().Result
                $outputStream = [System.IO.File]::Open($cachedPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
                try {
                    $inputStream.CopyTo($outputStream)
                } finally {
                    $outputStream.Close()
                    $inputStream.Close()
                }
            } finally {
                $client.Dispose()
            }
        }
    }
    
    return $cachedPath
}

#endregion

#region File Processing

function Test-ValidZipFile {
    param([string]$ZipPath)

    if (-not (Test-Path $ZipPath)) {
        return $false
    }

    $fileInfo = Get-Item $ZipPath -ErrorAction SilentlyContinue
    if (-not $fileInfo -or $fileInfo.Length -lt $script:MinValidZipSizeBytes) {
        return $false
    }

    # Check ZIP signature and validate structure
    try {
        $fileStream = [System.IO.File]::Open($ZipPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $buffer = New-Object byte[] 2
            $null = $fileStream.Read($buffer, 0, 2)
            if ($buffer[0] -ne 0x50 -or $buffer[1] -ne 0x4B) {
                return $false
            }
        } finally {
            $fileStream.Close()
        }

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $stream = [System.IO.File]::OpenRead($ZipPath)
        try {
            $zipArchive = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Read, $false)
            $null = $zipArchive.Entries.Count
            $zipArchive.Dispose()
        } finally {
            $stream.Dispose()
        }
        return $true
    }
    catch {
        return $false
    }
}

function Expand-ZipArchive {
    param([string]$ZipPath, [string]$OutputDirectory)

    if (Test-Path $OutputDirectory) {
        Remove-Item -Recurse -Force $OutputDirectory -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $OutputDirectory | Out-Null

    try {
        Expand-Archive -Path $ZipPath -DestinationPath $OutputDirectory -Force
    }
    catch {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $OutputDirectory)
    }
}

function Get-UiSuitableFontFiles {
    param([string]$FolderPath)

    $allFontFiles = Get-ChildItem -Path $FolderPath -Recurse -Include *.ttf, *.otf -ErrorAction SilentlyContinue
    if (-not $allFontFiles) {
        return @()
    }

    # Filter out italic/oblique fonts and prefer regular weights
    $nonItalicFonts = $allFontFiles | Where-Object { $_.Name -notmatch '(Italic|Oblique)' }
    $preferredFonts = $nonItalicFonts | Where-Object {
        $_.Name -match '(?i)(Regular|Book|Roman|Text|Medium|500|400|VariableFont|\[wght\])'
    }

    $selectedFonts = if ($preferredFonts) { $preferredFonts } else { $nonItalicFonts }
    return $selectedFonts | Select-Object -First $script:MaxUiFontFiles
}

function Get-FontFamilyNamesFromFiles {
    param([System.IO.FileInfo[]]$FontFiles)

    $familyNames = New-Object System.Collections.Generic.HashSet[string]
    foreach ($fontFile in $FontFiles) {
        $baseName = $fontFile.BaseName -replace '[-_](Regular|Book|Roman|Text|Medium|Light|Bold|Black|Thin|Extra.*|Semi.*|Variable.*|[0-9]+|Italic|Oblique)$', ''
        $cleanName = ($baseName -replace '[-_]+', ' ').Trim()
        if ($cleanName.Length -gt 1) {
            [void]$familyNames.Add($cleanName)
        }
    }
    return @($familyNames)
}

#region Google Fonts Integration

function Get-GoogleFontsCatalogFamilies {
    try {
        $headers = @{
            'Referer' = 'https://fonts.google.com/'
            'Accept' = 'application/json'
        }

        $rawResponse = Get-HttpStringSimple -Url "https://fonts.google.com/metadata/fonts" -Headers $headers
        if (-not $rawResponse) {
            return @()
        }

        # Handle both string and object responses
        if ($rawResponse -is [string]) {
            $jsonContent = $rawResponse.Trim()
            if ($jsonContent.StartsWith(")]}'")) {
                $jsonContent = $jsonContent.Substring(4)
            }
            $metadata = $jsonContent | ConvertFrom-Json
        } else {
            $metadata = $rawResponse
        }

        return $metadata.familyMetadataList.family | Select-Object -Unique
    }
    catch {
        Write-LogMessage ("Google Fonts API failed: {0}" -f $_.Exception.Message)
        return @()
    }
}

function Select-RandomFontFamilies {
    param([int]$Count, [switch]$IncludeMonospace)

    $availableFamilies = Get-GoogleFontsCatalogFamilies
    if (-not $availableFamilies -or $availableFamilies.Count -eq 0) {
        return @()
    }

    # Get previously installed fonts to avoid duplicates
    $installedHistory = Get-InstalledFontsHistory
    Write-LogMessage ("Found {0} previously installed fonts in history" -f $installedHistory.Count)

    # Filter out previously installed fonts
    $uninstalledFamilies = $availableFamilies | Where-Object { $installedHistory -notcontains $_ }
    Write-LogMessage ("Available uninstalled families: {0}" -f $uninstalledFamilies.Count)

    # If we've installed too many fonts, reset and use all families
    if ($uninstalledFamilies.Count -lt ($Count * 2)) {
        Write-LogMessage "Low number of uninstalled fonts, using all families"
        $uninstalledFamilies = $availableFamilies
    }

    $random = New-Object System.Random
    $selectedFamilies = New-Object System.Collections.Generic.List[string]

    # Add monospace font if requested
    if ($IncludeMonospace) {
        $monospaceFonts = $uninstalledFamilies | Where-Object { $_ -match '(?i)Mono|Code' } | Sort-Object { $random.Next() } | Select-Object -First 1
        if ($monospaceFonts) {
            $selectedFamilies.Add($monospaceFonts) | Out-Null
        }
    }

    # Fill remaining slots with random families
    $attempts = 0
    while ($selectedFamilies.Count -lt $Count -and $attempts -lt 50) {
        $candidate = $uninstalledFamilies | Sort-Object { $random.Next() } | Select-Object -First 1
        if ($selectedFamilies -notcontains $candidate) {
            $selectedFamilies.Add($candidate) | Out-Null
        }
        $attempts++
    }

    # If still not enough, fill with any available fonts
    while ($selectedFamilies.Count -lt $Count) {
        $candidate = $availableFamilies | Sort-Object { $random.Next() } | Select-Object -First 1
        if ($selectedFamilies -notcontains $candidate) {
            $selectedFamilies.Add($candidate) | Out-Null
        }
    }

    return @($selectedFamilies)
}

function Get-GoogleFontsDownloadUrl {
    param([string]$FamilyName)
    $encodedName = [Uri]::EscapeDataString($FamilyName)
    return "https://fonts.google.com/download?family=$encodedName"
}

#endregion

#region Font File Fetching

function Get-FontFilesFromGoogleFontsOfl {
    param([string]$DirectoryName, [string]$OutputDirectory)

    if (-not (Test-Path $OutputDirectory)) {
        New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
    }

    # Try common font file patterns with direct GitHub raw URLs
    $commonFontPatterns = @(
        "{0}-Regular.ttf", "{0}-Bold.ttf", "{0}-Light.ttf", "{0}-Medium.ttf",
        "{0}[wght].ttf", "{0}-VariableFont_wght.ttf"
    )

    $downloadedFiles = @()

    # Try main directory first, then static directory
    foreach ($pattern in $commonFontPatterns) {
        $fileName = $pattern -f ($DirectoryName -replace '([a-z])([A-Z])', '$1-$2')
        $urls = @(
            "https://raw.githubusercontent.com/google/fonts/main/ofl/$DirectoryName/$fileName",
            "https://raw.githubusercontent.com/google/fonts/main/ofl/$DirectoryName/static/$fileName"
        )

        foreach ($downloadUrl in $urls) {
            try {
                $destinationPath = Join-Path $OutputDirectory $fileName
                Invoke-WebRequest -Uri $downloadUrl -OutFile $destinationPath -TimeoutSec 30 -ErrorAction Stop

                $fileInfo = Get-Item $destinationPath -ErrorAction SilentlyContinue
                if ($fileInfo -and $fileInfo.Length -gt $script:MinValidFontSizeBytes) {
                    $downloadedFiles += $destinationPath
                    Write-LogMessage ("Downloaded: {0} ({1} bytes)" -f $fileName, $fileInfo.Length)
                    break
                } else {
                    Remove-Item $destinationPath -ErrorAction SilentlyContinue
                }
            }
            catch {
                # Continue to next URL
            }
        }

        if ($downloadedFiles.Count -ge $script:MaxFontFilesPerFamily) {
            break
        }
    }

    Write-LogMessage ("Downloaded {0} font files for {1}" -f $downloadedFiles.Count, $DirectoryName)
    return $downloadedFiles
}

function Get-CoverageFontUrls {
    param([string]$FamilyName)

    $urlMap = @{
        'Noto Sans' = 'https://raw.githubusercontent.com/notofonts/noto-fonts/main/hinted/ttf/NotoSans/NotoSans-Regular.ttf'
        'Noto Serif' = 'https://raw.githubusercontent.com/notofonts/noto-fonts/main/hinted/ttf/NotoSerif/NotoSerif-Regular.ttf'
        'Noto Sans Symbols 2' = 'https://raw.githubusercontent.com/notofonts/noto-fonts/main/hinted/ttf/NotoSansSymbols2/NotoSansSymbols2-Regular.ttf'
        'Noto Sans Symbols' = 'https://raw.githubusercontent.com/notofonts/noto-fonts/main/hinted/ttf/NotoSansSymbols/NotoSansSymbols-Regular.ttf'
    }

    return if ($urlMap.ContainsKey($FamilyName)) { @($urlMap[$FamilyName]) } else { @() }
}

function Install-FontFilesFromUrls {
    param([string[]]$Urls, [string]$OutputDirectory)

    $downloadSuccess = $false
    foreach ($url in $Urls) {
        try {
            $fileName = [System.IO.Path]::GetFileName($url)
            if (-not $fileName) {
                $fileName = [Guid]::NewGuid().ToString()
            }

            $tempPath = Join-Path $script:TempRoot $fileName
            $cachedFile = Get-CachedFileOrDownload -Url $url -PreferredFileName $fileName -Accept "application/octet-stream"
            Copy-Item $cachedFile $tempPath -Force
            Copy-Item $tempPath (Join-Path $OutputDirectory $fileName) -Force
            $downloadSuccess = $true
        }
        catch {
            Write-LogMessage ("URL fetch failed: {0}" -f $_.Exception.Message)
        }
    }

    return $downloadSuccess
}

#region Font Installation

function Install-SingleFontFile {
    param([string]$FontFilePath)

    if (-not (Test-Path $FontFilePath)) {
        return
    }

    $shell = New-Object -ComObject Shell.Application
    $fontsFolder = $shell.Namespace(0x14)
    if (-not $fontsFolder) {
        throw "Cannot access Fonts Shell."
    }

    Write-LogMessage ("Installing font file: {0}" -f $FontFilePath)
    $fontsFolder.CopyHere($FontFilePath)
    Start-HumanLikeDelay
}

function Install-FontFileSet {
    param([System.IO.FileInfo[]]$FontFiles)

    $installedFiles = @()
    foreach ($fontFile in $FontFiles) {
        try {
            Install-SingleFontFile -FontFilePath $fontFile.FullName
            $installedFiles += $fontFile.FullName
        }
        catch {
            Write-LogMessage ("Install failed for {0}: {1}" -f $fontFile.Name, $_.Exception.Message)
        }
    }

    return $installedFiles
}

#endregion

#region System Configuration

function Set-SystemDefaultFont {
    param([string]$FontFamily)

    $fontSubstitutesKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes'
    New-Item -Path $fontSubstitutesKey -Force | Out-Null

    New-ItemProperty -Path $fontSubstitutesKey -Name 'Segoe UI' -Value $FontFamily -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $fontSubstitutesKey -Name 'MS Shell Dlg' -Value $FontFamily -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $fontSubstitutesKey -Name 'MS Shell Dlg 2' -Value $FontFamily -PropertyType String -Force | Out-Null

    Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'FontSmoothing' -Value '2' -Force
    Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'FontSmoothingType' -Value 2 -Type DWord -Force

    Write-LogMessage ("Set system base font -> {0}" -f $FontFamily)
    Start-HumanLikeDelay
}

function Add-FontLinkEntries {
    param([string[]]$FamiliesToPrioritize, [string[]]$CoverageFirst)

    if (-not $FamiliesToPrioritize -or $FamiliesToPrioritize.Count -eq 0) {
        return
    }

    $fontLinkKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontLink\SystemLink'
    New-Item -Path $fontLinkKey -Force | Out-Null

    $registeredFonts = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts' -ErrorAction SilentlyContinue
    if (-not $registeredFonts) {
        return
    }

    # Build font file mappings
    $fontMappingsByFamily = @{}
    foreach ($family in $FamiliesToPrioritize) {
        $matchingEntries = $registeredFonts.PSObject.Properties | Where-Object {
            $_.Name -match [Regex]::Escape($family).Replace('\ ', '\s+')
        }

        $fontPairs = @()
        foreach ($entry in $matchingEntries) {
            $fontFile = [string]$entry.Value
            if ($fontFile -and ($fontFile -match '\.ttf$' -or $fontFile -match '\.otf$')) {
                $fontPairs += ("{0},{1}" -f $fontFile, $family)
            }
        }

        if ($fontPairs.Count -gt 0) {
            $fontMappingsByFamily[$family] = $fontPairs
        }
    }

    # Determine priority order (coverage fonts first)
    $presentCoverageFonts = @()
    foreach ($coverageFont in $CoverageFirst) {
        if ($fontMappingsByFamily.ContainsKey($coverageFont)) {
            $presentCoverageFonts += $coverageFont
        }
    }

    $otherFonts = ($FamiliesToPrioritize | Where-Object { $_ -notin $presentCoverageFonts })
    $random = New-Object System.Random
    $shuffledOtherFonts = $otherFonts | Sort-Object { $random.Next() }
    $prioritizedOrder = @($presentCoverageFonts + $shuffledOtherFonts)

    # Update FontLink for each base family
    foreach ($baseFamily in $script:BaseFamiliesToAugment) {
        $existingEntries = (Get-ItemProperty -Path $fontLinkKey -Name $baseFamily -ErrorAction SilentlyContinue).$baseFamily
        if (-not $existingEntries) {
            $existingEntries = @()
        }

        $newEntries = @()
        foreach ($family in $prioritizedOrder) {
            if ($fontMappingsByFamily.ContainsKey($family)) {
                foreach ($fontPair in $fontMappingsByFamily[$family]) {
                    if (-not ($newEntries -contains $fontPair)) {
                        $newEntries += $fontPair
                    }
                }
            }
        }

        $combinedEntries = @($newEntries + $existingEntries)
        $uniqueEntries = New-Object System.Collections.Generic.HashSet[string]
        $finalEntries = New-Object System.Collections.Generic.List[string]

        foreach ($entry in $combinedEntries) {
            if ([string]::IsNullOrWhiteSpace($entry)) {
                continue
            }
            if ($uniqueEntries.Add($entry)) {
                [void]$finalEntries.Add($entry)
            }
        }

        if ($finalEntries.Count -gt 0) {
            Set-ItemProperty -Path $fontLinkKey -Name $baseFamily -Type MultiString -Value @($finalEntries)
            Write-LogMessage ("FontLink updated for '{0}' with {1} entries" -f $baseFamily, $finalEntries.Count)
        }

        Start-HumanLikeDelay
    }
}

function Set-SymbolFontMapping {
    param([string]$TargetFamily)

    if ([string]::IsNullOrWhiteSpace($TargetFamily)) {
        return
    }

    $fontSubstitutesKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes'
    try {
        New-Item -Path $fontSubstitutesKey -Force | Out-Null
        New-ItemProperty -Path $fontSubstitutesKey -Name 'Segoe UI Symbol' -Value $TargetFamily -PropertyType String -Force | Out-Null
        Write-LogMessage ("Mapped 'Segoe UI Symbol' -> {0}" -f $TargetFamily)
    }
    catch {
        # Silently continue if mapping fails
    }
}

#region System Maintenance

function Update-WindowsFontCache {
    Write-LogMessage "Refreshing Windows Font Cache..."

    $fontServices = @('FontCache', 'FontCache3.0.0.0')
    foreach ($service in $fontServices) {
        try {
            Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
        } catch {}
    }

    $serviceCacheDir = "C:\Windows\ServiceProfiles\LocalService\AppData\Local\FontCache"
    $userCacheDir = Join-Path $env:LOCALAPPDATA "FontCache"

    foreach ($cacheDir in @($serviceCacheDir, $userCacheDir)) {
        try {
            if (Test-Path $cacheDir) {
                Get-ChildItem $cacheDir -Filter "*FontCache*" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
            }
        } catch {}
    }

    foreach ($service in $fontServices) {
        try {
            Start-Service -Name $service -ErrorAction SilentlyContinue
        } catch {}
    }

    Start-HumanLikeDelay
}

function Restart-WindowsExplorer {
    Write-LogMessage "Restarting Explorer..."
    Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Process explorer.exe
}

function Backup-FontRegistryKeys {
    Write-LogMessage "Backing up registry keys..."

    $registryKeys = @(
        'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes',
        'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontLink\SystemLink',
        'HKCU\Control Panel\Desktop'
    )

    foreach ($registryKey in $registryKeys) {
        $safeKeyName = ($registryKey -replace '[\\/:*?"<>| ]', '_')
        $backupFile = Join-Path $script:BackupDir "$safeKeyName.reg"
        & reg.exe export $registryKey $backupFile /y | Out-Null
    }

    Start-HumanLikeDelay
}

function Restore-DefaultFontSettings {
    Write-LogMessage "Restoring system font mappings to defaults..."

    $fontSubstitutesKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes'
    Remove-ItemProperty -Path $fontSubstitutesKey -Name 'Segoe UI' -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $fontSubstitutesKey -Name 'MS Shell Dlg' -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $fontSubstitutesKey -Name 'MS Shell Dlg 2' -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $fontSubstitutesKey -Name 'Segoe UI Symbol' -ErrorAction SilentlyContinue
}

#endregion

#region Chromium Browser Configuration

function Stop-ChromiumProcesses {
    $processNames = @('chrome', 'msedge', 'chrome.exe', 'msedge.exe')
    foreach ($processName in $processNames) {
        try {
            Get-Process $processName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        } catch {}
    }
}

function Get-ChromiumUserDataDirectories {
    $userDataRoots = New-Object System.Collections.Generic.List[string]

    # Check running processes for custom user data directories
    try {
        $chromiumProcesses = Get-CimInstance Win32_Process -Filter "Name='chrome.exe' OR Name='msedge.exe'"
        foreach ($process in $chromiumProcesses) {
            $commandLine = $process.CommandLine
            if ($commandLine -and ($commandLine -match '--user-data-dir=(?:"([^"]+)"|(\S+))')) {
                $userDataDir = if ($matches[1]) { $matches[1] } else { $matches[2] }
                if (Test-Path $userDataDir) {
                    $userDataRoots.Add($userDataDir) | Out-Null
                }
            }
        }
    } catch {}

    # Check standard locations
    $standardPaths = @(
        (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'),
        (Join-Path $env:LOCALAPPDATA 'Chromium\User Data'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data'),
        (Join-Path $env:APPDATA 'Google\Chrome\User Data'),
        (Join-Path $env:APPDATA 'Microsoft\Edge\User Data')
    )

    foreach ($path in $standardPaths) {
        if (Test-Path $path) {
            $userDataRoots.Add($path) | Out-Null
        }
    }

    return (@($userDataRoots) | Where-Object { Test-Path $_ } | Select-Object -Unique)
}

function Set-ChromiumFontPreferences {
    param(
        [string[]]$UserDataRoots,
        [string]$SerifFamily,
        [string]$SansSerifFamily,
        [string]$MonospaceFamily
    )

    foreach ($userDataRoot in $UserDataRoots) {
        $profileDirectories = Get-ChildItem -Path $userDataRoot -Directory -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -match '^(Default|Profile \d+|Guest Profile|System Profile)$'
        }

        foreach ($profileDir in $profileDirectories) {
            $preferencesFile = Join-Path $profileDir.FullName 'Preferences'
            if (-not (Test-Path $preferencesFile)) {
                continue
            }

            try {
                $timestamp = Get-Date -Format yyyyMMdd-HHmmss
                Copy-Item $preferencesFile ($preferencesFile + ".bak-$timestamp") -Force -ErrorAction SilentlyContinue

                $preferencesJson = Get-Content $preferencesFile -Raw -ErrorAction Stop | ConvertFrom-Json

                # Initialize fonts object if it doesn't exist
                if (-not $preferencesJson.fonts) {
                    $preferencesJson | Add-Member -NotePropertyName fonts -NotePropertyValue (@{})
                }

                # Initialize font category objects
                foreach ($category in @('serif', 'sansserif', 'standard', 'fixed', 'cursive', 'fantasy')) {
                    if (-not $preferencesJson.fonts.$category) {
                        $preferencesJson.fonts.$category = @{}
                    }
                }

                # Set font preferences
                $preferencesJson.fonts.serif.Zyyy = $SerifFamily
                $preferencesJson.fonts.standard.Zyyy = $SerifFamily
                $preferencesJson.fonts.sansserif.Zyyy = $SansSerifFamily
                $preferencesJson.fonts.fixed.Zyyy = $MonospaceFamily

                if (-not $preferencesJson.fonts.cursive.Zyyy) {
                    $preferencesJson.fonts.cursive.Zyyy = $SansSerifFamily
                }
                if (-not $preferencesJson.fonts.fantasy.Zyyy) {
                    $preferencesJson.fonts.fantasy.Zyyy = $SansSerifFamily
                }

                $preferencesJson | ConvertTo-Json -Depth 100 | Set-Content -Path $preferencesFile -Encoding UTF8
                Write-LogMessage ("Updated Chromium preferences: {0}" -f $preferencesFile)
            }
            catch {
                Write-LogMessage ("Failed to update Chromium preferences {0}: {1}" -f $preferencesFile, $_.Exception.Message)
            }

            Start-HumanLikeDelay
        }
    }
}

#endregion

#region Main Execution Logic

function Invoke-FontInstallationProcess {
    # Get random font families
    $randomFamilies = Select-RandomFontFamilies -Count $FontsPerRun -IncludeMonospace:$IncludeMonospace
    if (-not $randomFamilies -or $randomFamilies.Count -eq 0) {
        # Fallback to hardcoded list
        $popularFonts = @('opensans', 'roboto', 'lato', 'montserrat', 'poppins', 'nunito')
        $random = New-Object System.Random
        $randomFamilies = @()
        while ($randomFamilies.Count -lt $FontsPerRun) {
            $candidate = ($popularFonts | Sort-Object { $random.Next() } | Select-Object -First 1)
            if ($randomFamilies -notcontains $candidate) {
                $randomFamilies += $candidate
            }
        }
    }

    Write-LogMessage ("Selected font families: {0}" -f ($randomFamilies -join ", "))

    $installedFamilies = New-Object System.Collections.Generic.HashSet[string]

    # Process each font family
    foreach ($familyName in $randomFamilies) {
        $safeName = ($familyName -replace '[^a-zA-Z0-9\-]', '_')
        $extractDirectory = Join-Path $script:ExtractRoot $safeName
        if (-not (Test-Path $extractDirectory)) {
            New-Item -ItemType Directory -Path $extractDirectory | Out-Null
        }

        $installationSuccess = $false

        # Try Google ZIP download
        try {
            $downloadUrl = Get-GoogleFontsDownloadUrl -FamilyName $familyName
            $cachedZipFile = Get-CachedFileOrDownload -Url $downloadUrl -PreferredFileName ($safeName + ".zip") -Accept "application/zip, */*" -Referer "https://fonts.google.com/"
            Write-LogMessage ("Downloaded file: {0}, Size: {1} bytes" -f $cachedZipFile, (Get-Item $cachedZipFile -ErrorAction SilentlyContinue).Length)
            if (Test-ValidZipFile -ZipPath $cachedZipFile) {
                Write-LogMessage ("ZIP file is valid, extracting to: {0}" -f $extractDirectory)
                Expand-ZipArchive -ZipPath $cachedZipFile -OutputDirectory $extractDirectory
                $installationSuccess = $true
                Write-LogMessage ("ZIP extraction completed for {0}" -f $familyName)
            } else {
                Write-LogMessage ("ZIP file validation failed for {0}, falling back to OFL" -f $familyName)
            }
        }
        catch {
            Write-LogMessage ("ZIP download failed for {0}: {1}, falling back to OFL" -f $familyName, $_.Exception.Message)
        }

        # Fallback to OFL directory
        if (-not $installationSuccess) {
            $oflSlug = ($familyName.ToLower() -replace '[^a-z0-9]', '')
            Write-LogMessage ("Trying OFL fallback for {0} -> {1}" -f $familyName, $oflSlug)
            try {
                $downloadedFiles = Get-FontFilesFromGoogleFontsOfl -DirectoryName $oflSlug -OutputDirectory $extractDirectory
                if ($downloadedFiles -and $downloadedFiles.Count -gt 0) {
                    $installationSuccess = $true
                    Write-LogMessage ("OFL fallback successful: {0} files downloaded" -f $downloadedFiles.Count)
                }
                else {
                    Write-LogMessage ("OFL fallback found no files for {0}" -f $oflSlug)
                }
            }
            catch {
                Write-LogMessage ("OFL fetch failed for {0}: {1}" -f $familyName, $_.Exception.Message)
            }
        }

        # Try extra URLs if provided
        if (-not $installationSuccess -and $ExtraUrls) {
            if (Install-FontFilesFromUrls -Urls $ExtraUrls -OutputDirectory $extractDirectory) {
                $installationSuccess = $true
            }
        }

        # Try local folder if provided
        if (-not $installationSuccess -and $LocalFolder -and (Test-Path $LocalFolder)) {
            Copy-Item -Path (Join-Path $LocalFolder '*') -Destination $extractDirectory -Recurse -Force -ErrorAction SilentlyContinue
            $installationSuccess = $true
        }

        # Install fonts if we have any
        $fontFiles = Get-UiSuitableFontFiles -FolderPath $extractDirectory
        if (-not $installationSuccess -or -not $fontFiles -or $fontFiles.Count -eq 0) {
            Write-LogMessage ("No usable fonts found for {0}. Skipping." -f $familyName)
            continue
        }

        [void](Install-FontFileSet -FontFiles $fontFiles)
        Write-LogMessage ("Extracting family names from {0} font files" -f $fontFiles.Count)
        try {
            $detectedFamilies = Get-FontFamilyNamesFromFiles -FontFiles $fontFiles
            Write-LogMessage ("Detected families: {0}" -f ($detectedFamilies -join ", "))
            foreach ($detectedFamily in $detectedFamilies) {
                [void]$installedFamilies.Add($detectedFamily)
            }
        }
        catch {
            Write-LogMessage ("Error extracting family names: {0}" -f $_.Exception.Message)
        }
        [void]$installedFamilies.Add($familyName)
    }

    return @($installedFamilies)
}

function Invoke-CoverageFontInstallation {
    param([string[]]$InstalledFamilies)

    $coverageInstalled = @()
    foreach ($coverageFamily in $script:CoverageFamilies) {
        if ($InstalledFamilies -contains $coverageFamily) {
            $coverageInstalled += $coverageFamily
        }
    }

    if ($coverageInstalled.Count -eq 0) {
        Write-LogMessage "No coverage fonts installed, trying to download one..."
        $selectedCoverageFont = Get-Random -InputObject $script:CoverageFamilies
        $coverageDirectory = Join-Path $script:ExtractRoot "coverage"
        if (-not (Test-Path $coverageDirectory)) {
            New-Item -ItemType Directory -Path $coverageDirectory | Out-Null
        }

        $coverageUrls = Get-CoverageFontUrls -FamilyName $selectedCoverageFont
        if ($coverageUrls.Count -gt 0) {
            Write-LogMessage ("Trying to download coverage font: {0}" -f $selectedCoverageFont)
            try {
                if (Install-FontFilesFromUrls -Urls $coverageUrls -OutputDirectory $coverageDirectory) {
                    $fontFiles = Get-UiSuitableFontFiles -FolderPath $coverageDirectory
                    if ($fontFiles -and $fontFiles.Count -gt 0) {
                        [void](Install-FontFileSet -FontFiles $fontFiles)
                        Write-LogMessage ("Extracting family names from {0} coverage font files" -f $fontFiles.Count)
                        try {
                            $detectedFamilies = Get-FontFamilyNamesFromFiles -FontFiles $fontFiles
                            Write-LogMessage ("Coverage font families detected: {0}" -f ($detectedFamilies -join ", "))
                            Write-LogMessage ("Coverage font installed successfully: {0}" -f $selectedCoverageFont)
                            return $InstalledFamilies + $detectedFamilies + $selectedCoverageFont
                        }
                        catch {
                            Write-LogMessage ("Error extracting coverage font families: {0}" -f $_.Exception.Message)
                            return $InstalledFamilies + $selectedCoverageFont
                        }
                    }
                }
            }
            catch {
                Write-LogMessage ("Coverage font download failed: {0}" -f $_.Exception.Message)
            }
        }

        # Final fallback to system fonts
        Write-LogMessage "Using system fonts as final fallback"
        $systemFonts = @("Arial", "Times New Roman", "Courier New")
        return $InstalledFamilies + $systemFonts
    }

    return $InstalledFamilies
}

#endregion

#region Main Script Execution

try {
    # Initialize environment
    Assert-AdminPrivileges
    Initialize-RequiredDirectories
    Write-LogMessage ("Log file: {0}" -f $script:LogFile)

    # Handle restore default mode
    if ($RestoreDefault) {
        Restore-DefaultFontSettings
        Update-WindowsFontCache
        if (-not $NoRestartExplorer) {
            Restart-WindowsExplorer
        }
        Write-LogMessage "Done. System font reverted. Sign out or reboot may be required."
        if ($Cleanup) {
            if (Test-Path $script:TempRoot) {
                Remove-Item -Recurse -Force $script:TempRoot -ErrorAction SilentlyContinue
            }
        }
        exit 0
    }

    # Install fonts
    $installedFamilies = Invoke-FontInstallationProcess
    $allInstalledFamilies = Invoke-CoverageFontInstallation -InstalledFamilies $installedFamilies

    if ($allInstalledFamilies.Count -eq 0) {
        throw "No font families were installed this session."
    }

    Write-LogMessage ("New families this run: {0}" -f ($allInstalledFamilies -join ", "))

    # Add newly installed fonts to history
    Add-ToInstalledFontsHistory -FontFamilies $allInstalledFamilies

    # Select primary font (non-symbol font preferred)
    $primaryFont = ($allInstalledFamilies | Where-Object { $_ -notmatch '(?i)symbols|emoji|dingbats|math' } | Get-Random)
    if (-not $primaryFont) {
        $primaryFont = ($allInstalledFamilies | Get-Random)
    }

    # Apply system configuration
    Write-LogMessage "Backing up registry and applying system mappings..."
    Backup-FontRegistryKeys
    Set-SystemDefaultFont -FontFamily $primaryFont

    # Configure FontLink with coverage fonts prioritized
    $coverageFirst = @()
    foreach ($coverageFamily in $script:CoverageFamilies) {
        if ($allInstalledFamilies -contains $coverageFamily) {
            $coverageFirst += $coverageFamily
        }
    }
    Add-FontLinkEntries -FamiliesToPrioritize $allInstalledFamilies -CoverageFirst $coverageFirst

    # Configure symbol font substitution
    if (-not $NoSymbolSubstitute) {
        $symbolFont = ($script:CoverageFamilies | Where-Object { $allInstalledFamilies -contains $_ } | Select-Object -First 1)
        if ($symbolFont) {
            Set-SymbolFontMapping -TargetFamily $symbolFont
        }
    }

    # Update browser preferences
    Stop-ChromiumProcesses
    $chromiumDataRoots = Get-ChromiumUserDataDirectories
    $serifFont = ($allInstalledFamilies | Where-Object { $_ -match '(?i)noto serif|serif' } | Select-Object -First 1)
    if (-not $serifFont) { $serifFont = $primaryFont }

    $sansFont = ($allInstalledFamilies | Where-Object { $_ -match '(?i)noto sans|inter|manrope|public sans' } | Select-Object -First 1)
    if (-not $sansFont) { $sansFont = $primaryFont }

    $monoFont = ($allInstalledFamilies | Where-Object { $_ -match '(?i)mono|code' } | Select-Object -First 1)
    if (-not $monoFont) { $monoFont = $primaryFont }

    if ($chromiumDataRoots) {
        Set-ChromiumFontPreferences -UserDataRoots $chromiumDataRoots -SerifFamily $serifFont -SansSerifFamily $sansFont -MonospaceFamily $monoFont
    }

    # Finalize system changes
    Update-WindowsFontCache
    if (-not $NoRestartExplorer) {
        Restart-WindowsExplorer
    }

    Write-LogMessage ("Completed. New families: {0}. Primary system font: {1}" -f ($allInstalledFamilies -join ", "), $primaryFont)
    Write-LogMessage ("Temporary working folder: {0}" -f $script:TempRoot)
    Write-LogMessage "Note: Some UI areas may still require sign out or reboot to fully apply."

}
catch {
    Write-LogMessage ("ERROR: {0}" -f $_.Exception.Message)
    Write-LogMessage ("Registry backup (if created): {0}" -f $script:BackupDir)
    exit 1
}
finally {
    if ($Cleanup) {
        Write-LogMessage "Cleaning up temporary files..."
        try {
            if (Test-Path $script:TempRoot) {
                Remove-Item -Recurse -Force $script:TempRoot -ErrorAction SilentlyContinue
            }
        }
        catch {
            # Silently continue if cleanup fails
        }
    }
}

#endregion
