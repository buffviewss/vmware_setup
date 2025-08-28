<#
.SYNOPSIS
    Human-grade, real system font changer for Windows 10 — v3.1
    
.DESCRIPTION
    Production-ready font fingerprinting tool with robust network handling, caching, and logging.
    Features: One-click defaults, random real installs, Unicode coverage, network retry with backoff,
    persistent cache, human-like jitter, structured logging.
    
    Key behaviors:
    - True install through Fonts Shell (no fake JS/extension)
    - Random Google families (Google catalog → GitHub OFL → jsDelivr fallback)
    - Unicode coverage via Noto fonts with FontLink prepending
    - Chrome/Edge profile updates, font cache refresh, Explorer restart
    
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

#region Configuration and Constants

# Apply one-click defaults for unspecified parameters
if (-not $PSBoundParameters.ContainsKey('IncludeMonospace')) { $IncludeMonospace = $true }
if (-not $PSBoundParameters.ContainsKey('Cleanup')) { $Cleanup = $true }
if (-not $PSBoundParameters.ContainsKey('FontsPerRun')) { $FontsPerRun = Get-Random -InputObject @(2,3) }

# Font family constants
$script:CoverageFamilies = @('Noto Sans', 'Noto Serif', 'Noto Sans Symbols 2', 'Noto Sans Symbols')
$script:BaseFamiliesToAugment = @(
    'Segoe UI', 'Arial', 'Times New Roman', 'Courier New', 'Microsoft Sans Serif',
    'Segoe UI Symbol', 'Comic Sans MS', 'Impact'
)

# Network and retry constants
$script:NetworkRetryCount = 3
$script:NetworkBaseDelayMs = 500
$script:HttpTimeoutMinutes = 8
$script:JitterMinMs = 200
$script:JitterMaxMs = 900
$script:MaxFontFilesPerFamily = 6
$script:MaxUiFontFiles = 8
$script:MinValidFontSizeBytes = 10000
$script:MinValidZipSizeBytes = 200

# Path configuration
$script:TempRoot = Join-Path -Path $env:TEMP -ChildPath ("FontInstall-" + (Get-Date -Format yyyyMMdd-HHmmss))
$script:BackupDir = Join-Path -Path $script:TempRoot -ChildPath "RegistryBackup"
$script:ExtractRoot = Join-Path -Path $script:TempRoot -ChildPath "unzipped"
$script:CacheDir = Join-Path -Path $env:ProgramData -ChildPath "FontRealCache"
$script:LogDir = Join-Path -Path $env:ProgramData -ChildPath "FontReal\logs"
$script:LogFile = Join-Path -Path $script:LogDir -ChildPath ("run-" + (Get-Date -Format yyyyMMdd-HHmmss) + ".log")

# Global state for jsDelivr API cache
$global:JsDelivrFlat = $null

#endregion

#region Core Utility Functions

function Assert-AdminPrivileges {
    <#
    .SYNOPSIS
        Ensures the script is running with Administrator privileges
    #>
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
        throw "Please run PowerShell as Administrator."
    }
}

function Initialize-RequiredDirectories {
    <#
    .SYNOPSIS
        Creates all required directories for the script operation
    #>
    $directories = @($script:TempRoot, $script:BackupDir, $script:ExtractRoot, $script:CacheDir, $script:LogDir)
    foreach ($directory in $directories) {
        if (-not (Test-Path $directory)) {
            New-Item -ItemType Directory -Path $directory | Out-Null
        }
    }
}

function Initialize-TlsSettings {
    <#
    .SYNOPSIS
        Ensures TLS 1.2 is enabled for secure connections
    #>
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.ServicePointManager]::SecurityProtocol
    }
    catch {
        # Silently continue if TLS configuration fails
    }
}

function Write-LogMessage {
    <#
    .SYNOPSIS
        Writes timestamped log messages to both console and log file
    .PARAMETER Message
        The message to log
    #>
    param([string]$Message)
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[{0}] {1}" -f $timestamp, $Message
    Write-Host $logLine
    try {
        Add-Content -Path $script:LogFile -Value $logLine
    }
    catch {
        # Silently continue if logging fails
    }
}

function Start-HumanLikeDelay {
    <#
    .SYNOPSIS
        Introduces random delay to simulate human behavior
    .PARAMETER MinMs
        Minimum delay in milliseconds
    .PARAMETER MaxMs
        Maximum delay in milliseconds
    #>
    param(
        [int]$MinMs = $script:JitterMinMs,
        [int]$MaxMs = $script:JitterMaxMs
    )
    Start-Sleep -Milliseconds (Get-Random -Minimum $MinMs -Maximum $MaxMs)
}

#endregion

#region Network and Retry Logic

function Invoke-WithRetryLogic {
    <#
    .SYNOPSIS
        Executes a script block with exponential backoff retry logic
    .PARAMETER Action
        The script block to execute
    .PARAMETER MaxAttempts
        Maximum number of retry attempts
    .PARAMETER BaseDelayMs
        Base delay for exponential backoff
    #>
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
    <#
    .SYNOPSIS
        Creates a configured HttpClient with proper headers and proxy settings
    .PARAMETER Accept
        Accept header value
    .PARAMETER Referer
        Referer header value
    #>
    param(
        [string]$Accept = "*/*",
        [string]$Referer = ""
    )
    
    Initialize-TlsSettings
    Add-Type -AssemblyName System.Net.Http
    
    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
    $handler.AllowAutoRedirect = $true
    
    # Configure proxy settings
    if ($ProxyUrl) {
        $webProxy = New-Object System.Net.WebProxy($ProxyUrl, $true)
        if ($ProxyCredential) {
            $webProxy.Credentials = $ProxyCredential.GetNetworkCredential()
        }
        else {
            $webProxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
        }
        $handler.UseProxy = $true
        $handler.Proxy = $webProxy
    }
    elseif ($UseSystemProxy) {
        $handler.UseProxy = $true
        $handler.Proxy = [System.Net.WebRequest]::DefaultWebProxy
        if ($handler.Proxy) {
            $handler.Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
        }
    }
    else {
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

function Invoke-HttpDownload {
    <#
    .SYNOPSIS
        Downloads a file from URL with retry logic
    .PARAMETER Url
        URL to download from
    .PARAMETER OutputPath
        Local file path to save to
    .PARAMETER Accept
        Accept header value
    .PARAMETER Referer
        Referer header value
    #>
    param(
        [string]$Url,
        [string]$OutputPath,
        [string]$Accept = "*/*",
        [string]$Referer = ""
    )

    Invoke-WithRetryLogic -Action {
        $client = New-ConfiguredHttpClient -Accept $Accept -Referer $Referer
        try {
            $response = $client.GetAsync($Url, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).Result
            if (-not $response.IsSuccessStatusCode) {
                throw ("HTTP {0} {1}" -f [int]$response.StatusCode, $response.ReasonPhrase)
            }

            $inputStream = $response.Content.ReadAsStreamAsync().Result
            $outputStream = [System.IO.File]::Open($OutputPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            try {
                $inputStream.CopyTo($outputStream)
            }
            finally {
                $outputStream.Close()
                $inputStream.Close()
                $client.Dispose()
            }
        }
        catch {
            $client.Dispose()
            throw
        }
    }
}

function Get-HttpString {
    <#
    .SYNOPSIS
        Downloads string content from URL with retry logic
    .PARAMETER Url
        URL to download from
    .PARAMETER Accept
        Accept header value
    .PARAMETER Referer
        Referer header value
    #>
    param(
        [string]$Url,
        [string]$Accept = "*/*",
        [string]$Referer = ""
    )

    Invoke-WithRetryLogic -Action {
        $client = New-ConfiguredHttpClient -Accept $Accept -Referer $Referer
        try {
            return $client.GetStringAsync($Url).Result
        }
        catch {
            $client.Dispose()
            throw
        }
        finally {
            $client.Dispose()
        }
    }
}

#endregion

#region Cache Management

function Get-CachedFileOrDownload {
    <#
    .SYNOPSIS
        Gets file from cache or downloads if not cached
    .PARAMETER Url
        URL to download from
    .PARAMETER PreferredFileName
        Preferred filename for cache
    .PARAMETER Accept
        Accept header value
    .PARAMETER Referer
        Referer header value
    #>
    param(
        [string]$Url,
        [string]$PreferredFileName,
        [string]$Accept = "*/*",
        [string]$Referer = ""
    )

    $fileName = $PreferredFileName
    if (-not $fileName -or $fileName.Trim().Length -eq 0) {
        try {
            $fileName = [System.IO.Path]::GetFileName([Uri]$Url)
        }
        catch {
            $fileName = [Guid]::NewGuid().ToString()
        }
    }

    $cachedPath = Join-Path $script:CacheDir $fileName
    if (Test-Path $cachedPath) {
        Write-LogMessage ("Cache hit: {0}" -f $fileName)
    }
    else {
        Write-LogMessage ("Cache miss, downloading: {0}" -f $Url)
        Invoke-HttpDownload -Url $Url -OutputPath $cachedPath -Accept $Accept -Referer $Referer
    }

    return $cachedPath
}

#region File Validation and Processing

function Test-ValidZipFile {
    <#
    .SYNOPSIS
        Validates if a file is a valid ZIP archive
    .PARAMETER ZipPath
        Path to ZIP file to validate
    #>
    param([string]$ZipPath)

    if (-not (Test-Path $ZipPath)) {
        return $false
    }

    $fileInfo = Get-Item $ZipPath -ErrorAction SilentlyContinue
    if (-not $fileInfo -or $fileInfo.Length -lt $script:MinValidZipSizeBytes) {
        return $false
    }

    # Check ZIP signature
    $fileStream = [System.IO.File]::Open($ZipPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $buffer = New-Object byte[] 2
        $null = $fileStream.Read($buffer, 0, 2)
        if ($buffer[0] -ne 0x50 -or $buffer[1] -ne 0x4B) {
            return $false
        }
    }
    finally {
        $fileStream.Close()
    }

    # Validate ZIP structure
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $stream = [System.IO.File]::OpenRead($ZipPath)
        try {
            $zipArchive = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Read, $false)
            $null = $zipArchive.Entries.Count
            $zipArchive.Dispose()
        }
        finally {
            $stream.Dispose()
        }
        return $true
    }
    catch {
        return $false
    }
}

function Expand-ZipArchive {
    <#
    .SYNOPSIS
        Extracts ZIP archive to specified directory
    .PARAMETER ZipPath
        Path to ZIP file
    .PARAMETER OutputDirectory
        Directory to extract to
    #>
    param(
        [string]$ZipPath,
        [string]$OutputDirectory
    )

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
    <#
    .SYNOPSIS
        Filters font files to get UI-suitable ones (non-italic, regular weights)
    .PARAMETER FolderPath
        Folder containing font files
    #>
    param([string]$FolderPath)

    $allFontFiles = Get-ChildItem -Path $FolderPath -Recurse -Include *.ttf, *.otf -ErrorAction SilentlyContinue
    if (-not $allFontFiles) {
        return @()
    }

    # Filter out italic/oblique fonts
    $nonItalicFonts = $allFontFiles | Where-Object { $_.Name -notmatch '(Italic|Oblique)' }

    # Prefer regular/standard weights
    $preferredFonts = $nonItalicFonts | Where-Object {
        $_.Name -match '(?i)(Regular|Book|Roman|Text|Medium|500|400|VariableFont|\[wght\])'
    }

    $selectedFonts = if ($preferredFonts) { $preferredFonts } else { $nonItalicFonts }
    return $selectedFonts | Select-Object -First $script:MaxUiFontFiles
}

function Get-FontFamilyNamesFromFiles {
    <#
    .SYNOPSIS
        Extracts likely font family names from font file names
    .PARAMETER FontFiles
        Array of font file objects
    #>
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

function Get-ShuffledArray {
    <#
    .SYNOPSIS
        Returns a shuffled copy of the input array
    .PARAMETER InputArray
        Array to shuffle
    #>
    param([object[]]$InputArray)

    if (-not $InputArray) {
        return @()
    }

    $random = New-Object System.Random
    return $InputArray | Sort-Object { $random.Next() }
}

#region Google Fonts API Integration

function Get-GoogleFontsCatalogFamilies {
    <#
    .SYNOPSIS
        Retrieves font family list from Google Fonts metadata API
    #>
    $rawResponse = Get-HttpString -Url "https://fonts.google.com/metadata/fonts" -Accept "application/json" -Referer "https://fonts.google.com/"
    if ([string]::IsNullOrWhiteSpace($rawResponse)) {
        return @()
    }

    # Remove JSONP prefix if present
    $jsonContent = $rawResponse.Trim()
    if ($jsonContent.StartsWith(")]}'")) {
        $jsonContent = $jsonContent.Substring(4)
    }

    try {
        $metadata = $jsonContent | ConvertFrom-Json
        return $metadata.familyMetadataList.family | Select-Object -Unique
    }
    catch {
        return @()
    }
}

function Select-RandomFontFamilies {
    <#
    .SYNOPSIS
        Selects random font families from Google Fonts catalog
    .PARAMETER Count
        Number of families to select
    .PARAMETER IncludeMonospace
        Whether to include monospace fonts
    #>
    param(
        [int]$Count,
        [switch]$IncludeMonospace
    )

    $availableFamilies = Get-GoogleFontsCatalogFamilies
    if (-not $availableFamilies -or $availableFamilies.Count -eq 0) {
        return @()
    }

    $random = New-Object System.Random
    $selectedFamilies = New-Object System.Collections.Generic.List[string]

    # Add monospace font if requested
    if ($IncludeMonospace) {
        $monospaceFonts = $availableFamilies | Where-Object { $_ -match '(?i)Mono|Code' } | Sort-Object { $random.Next() } | Select-Object -First 1
        if ($monospaceFonts) {
            $selectedFamilies.Add($monospaceFonts) | Out-Null
        }
    }

    # Fill remaining slots with random families
    while ($selectedFamilies.Count -lt $Count) {
        $candidate = $availableFamilies | Sort-Object { $random.Next() } | Select-Object -First 1
        if ($selectedFamilies -notcontains $candidate) {
            $selectedFamilies.Add($candidate) | Out-Null
        }
    }

    return @($selectedFamilies)
}

function Get-GoogleFontsDownloadUrl {
    <#
    .SYNOPSIS
        Constructs Google Fonts download URL for a family
    .PARAMETER FamilyName
        Font family name
    #>
    param([string]$FamilyName)

    $encodedName = [Uri]::EscapeDataString($FamilyName)
    return "https://fonts.google.com/download?family=$encodedName"
}

#endregion

#region GitHub OFL Repository Integration

function Get-GoogleFontsOflDirectoriesFromGitHub {
    <#
    .SYNOPSIS
        Gets OFL directory list from Google Fonts GitHub repository
    .PARAMETER MaxPages
        Maximum pages to fetch from GitHub API
    #>
    param([int]$MaxPages = 6)

    $allDirectories = New-Object System.Collections.Generic.List[string]

    for ($page = 1; $page -le $MaxPages; $page++) {
        $apiUrl = "https://api.github.com/repos/google/fonts/contents/ofl?page=$page&per_page=100"
        $rawResponse = Get-HttpString -Url $apiUrl -Accept "application/vnd.github+json"

        if ([string]::IsNullOrWhiteSpace($rawResponse)) {
            break
        }

        $jsonResponse = $rawResponse | ConvertFrom-Json
        $directories = $jsonResponse | Where-Object { $_.type -eq 'dir' } | ForEach-Object { $_.name }

        if (-not $directories -or $directories.Count -eq 0) {
            break
        }

        $directories | ForEach-Object { $allDirectories.Add($_) | Out-Null }
    }

    return @($allDirectories)
}

function Initialize-JsDelivrCache {
    <#
    .SYNOPSIS
        Initializes the jsDelivr flat file cache for Google Fonts
    #>
    if ($global:JsDelivrFlat -ne $null) {
        return
    }

    $rawResponse = Get-HttpString -Url "https://data.jsdelivr.com/v1/package/gh/google/fonts@main/flat" -Accept "application/json"
    if (-not [string]::IsNullOrWhiteSpace($rawResponse)) {
        $global:JsDelivrFlat = $rawResponse | ConvertFrom-Json
    }
    else {
        $global:JsDelivrFlat = @{}
    }
}

function Get-GoogleFontsOflDirectoriesFromJsDelivr {
    <#
    .SYNOPSIS
        Gets OFL directory list from jsDelivr API as fallback
    #>
    Initialize-JsDelivrCache

    $files = $global:JsDelivrFlat.files
    if (-not $files) {
        return @()
    }

    $directories = New-Object System.Collections.Generic.HashSet[string]
    foreach ($file in $files) {
        $fileName = $file.name
        if ($fileName -match '^ofl/([^/]+)/.*\.(ttf|otf)$') {
            [void]$directories.Add($matches[1])
        }
    }

    return @($directories)
}

#region Font File Fetching

function Get-FontFilesFromGoogleFontsOfl {
    <#
    .SYNOPSIS
        Downloads font files from Google Fonts OFL directory
    .PARAMETER DirectoryName
        OFL directory name
    .PARAMETER OutputDirectory
        Local directory to save files
    #>
    param(
        [string]$DirectoryName,
        [string]$OutputDirectory
    )

    if (-not (Test-Path $OutputDirectory)) {
        New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
    }

    $fontEntries = @()

    # Try GitHub API first
    $githubApiUrl = "https://api.github.com/repos/google/fonts/contents/ofl/{0}" -f $DirectoryName
    $rawResponse = Get-HttpString -Url $githubApiUrl -Accept "application/vnd.github+json"

    if ($rawResponse) {
        $jsonResponse = $rawResponse | ConvertFrom-Json
        $fontEntries += ($jsonResponse | Where-Object { $_.type -eq 'file' -and $_.name -match '\.(ttf|otf)$' })

        # Check for static subdirectory
        $staticDirectory = $jsonResponse | Where-Object { $_.type -eq 'dir' -and $_.name -eq 'static' }
        if ($staticDirectory) {
            $staticApiUrl = "https://api.github.com/repos/google/fonts/contents/ofl/{0}/static" -f $DirectoryName
            $staticResponse = Get-HttpString -Url $staticApiUrl -Accept "application/vnd.github+json"
            if ($staticResponse) {
                $staticJson = $staticResponse | ConvertFrom-Json
                $fontEntries += ($staticJson | Where-Object { $_.type -eq 'file' -and $_.name -match '\.(ttf|otf)$' })
            }
        }
    }

    # Fallback to jsDelivr if GitHub API failed
    if (-not $fontEntries -or $fontEntries.Count -eq 0) {
        Initialize-JsDelivrCache
        $files = $global:JsDelivrFlat.files
        if ($files) {
            $fontEntries = @()
            foreach ($file in $files) {
                $fileName = $file.name
                if ($fileName -match ("^ofl/{0}/.*\.(ttf|otf)$" -f [Regex]::Escape($DirectoryName))) {
                    $fontEntries += [PSCustomObject]@{
                        name = (Split-Path $fileName -Leaf)
                        download_url = ("https://cdn.jsdelivr.net/gh/google/fonts@main/{0}" -f $fileName)
                    }
                }
            }
        }
    }

    # Download font files
    $downloadedFiles = @()
    foreach ($entry in $fontEntries) {
        $destinationPath = Join-Path $OutputDirectory $entry.name
        $downloadUrl = if ($entry.download_url) {
            $entry.download_url
        } else {
            "https://raw.githubusercontent.com/google/fonts/main/ofl/$DirectoryName/$($entry.name)"
        }

        try {
            $cachedFile = Get-CachedFileOrDownload -Url $downloadUrl -PreferredFileName $entry.name -Accept "application/octet-stream"
            Copy-Item $cachedFile $destinationPath -Force

            $fileInfo = Get-Item $destinationPath -ErrorAction SilentlyContinue
            if ($fileInfo -and $fileInfo.Length -gt $script:MinValidFontSizeBytes) {
                $downloadedFiles += $destinationPath
            }
        }
        catch {
            Write-LogMessage ("Download failed for {0}: {1}" -f $downloadUrl, $_.Exception.Message)
        }

        if ($downloadedFiles.Count -ge $script:MaxFontFilesPerFamily) {
            break
        }
    }

    return $downloadedFiles
}

function Get-CoverageFontUrls {
    <#
    .SYNOPSIS
        Gets direct URLs for coverage fonts (Noto family)
    .PARAMETER FamilyName
        Coverage font family name
    #>
    param([string]$FamilyName)

    switch -Regex ($FamilyName) {
        '^Noto Sans$' {
            return @('https://raw.githubusercontent.com/notofonts/noto-fonts/main/hinted/ttf/NotoSans/NotoSans-Regular.ttf')
        }
        '^Noto Serif$' {
            return @('https://raw.githubusercontent.com/notofonts/noto-fonts/main/hinted/ttf/NotoSerif/NotoSerif-Regular.ttf')
        }
        '^Noto Sans Symbols 2$' {
            return @('https://raw.githubusercontent.com/notofonts/noto-fonts/main/hinted/ttf/NotoSansSymbols2/NotoSansSymbols2-Regular.ttf')
        }
        '^Noto Sans Symbols$' {
            return @('https://raw.githubusercontent.com/notofonts/noto-fonts/main/hinted/ttf/NotoSansSymbols/NotoSansSymbols-Regular.ttf')
        }
        default {
            return @()
        }
    }
}

function Install-FontFilesFromUrls {
    <#
    .SYNOPSIS
        Downloads and installs font files from provided URLs
    .PARAMETER Urls
        Array of URLs to download from
    .PARAMETER OutputDirectory
        Directory to save downloaded files
    #>
    param(
        [string[]]$Urls,
        [string]$OutputDirectory
    )

    $downloadSuccess = $false
    foreach ($url in $Urls) {
        try {
            $fileName = [System.IO.Path]::GetFileName($url)
            if ($fileName -eq '' -or $fileName -eq $null) {
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
    <#
    .SYNOPSIS
        Installs a single font file using Windows Fonts Shell
    .PARAMETER FontFilePath
        Path to font file to install
    #>
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
    <#
    .SYNOPSIS
        Installs multiple font files
    .PARAMETER FontFiles
        Array of font file objects to install
    #>
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

#region System Font Configuration

function Set-SystemDefaultFont {
    <#
    .SYNOPSIS
        Sets the system default font family
    .PARAMETER FontFamily
        Font family name to set as default
    #>
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
    <#
    .SYNOPSIS
        Prepends font families to FontLink for fallback support
    .PARAMETER FamiliesToPrioritize
        Font families to add to FontLink
    .PARAMETER CoverageFirst
        Coverage fonts to prioritize first
    #>
    param(
        [string[]]$FamiliesToPrioritize,
        [string[]]$CoverageFirst
    )

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
    $prioritizedOrder = @($presentCoverageFonts + (Get-ShuffledArray -InputArray $otherFonts))

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
            Set-ItemProperty -Path $fontLinkKey -Name $baseFamily -Type MultiString -Value $finalEntries
            Write-LogMessage ("FontLink updated for '{0}' with {1} entries" -f $baseFamily, $finalEntries.Count)
        }

        Start-HumanLikeDelay
    }
}

function Set-SymbolFontMapping {
    <#
    .SYNOPSIS
        Maps Segoe UI Symbol to a coverage font family
    .PARAMETER TargetFamily
        Font family to map Segoe UI Symbol to
    #>
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

#region Chromium Browser Configuration

function Stop-ChromiumProcesses {
    <#
    .SYNOPSIS
        Stops running Chromium-based browser processes
    #>
    $processNames = @('chrome', 'msedge', 'chrome.exe', 'msedge.exe')
    foreach ($processName in $processNames) {
        try {
            Get-Process $processName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        }
        catch {
            # Silently continue if process stop fails
        }
    }
}

function Get-ChromiumUserDataDirectories {
    <#
    .SYNOPSIS
        Discovers Chromium user data directories from running processes and standard locations
    #>
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
    }
    catch {
        # Continue if process enumeration fails
    }

    # Check standard user directories
    $userDirectories = Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -notmatch '^(All Users|Default|Default User|Public|DefaultAppPool)$'
    }

    $chromeVariants = @('Google\Chrome\User Data', 'Google\Chrome Beta\User Data', 'Google\Chrome Dev\User Data', 'Google\Chrome SxS\User Data', 'Chromium\User Data')
    $edgeVariants = @('Microsoft\Edge\User Data', 'Microsoft\Edge Beta\User Data', 'Microsoft\Edge Dev\User Data', 'Microsoft\Edge SxS\User Data')

    foreach ($userDir in $userDirectories) {
        foreach ($browserPath in ($chromeVariants + $edgeVariants)) {
            foreach ($appDataType in @('Local', 'Roaming')) {
                $fullPath = Join-Path $userDir.FullName ("AppData\{0}\{1}" -f $appDataType, $browserPath)
                if (Test-Path $fullPath) {
                    $userDataRoots.Add($fullPath) | Out-Null
                }
            }
        }
    }

    # Check current user's standard locations
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
    <#
    .SYNOPSIS
        Updates Chromium browser font preferences for all profiles
    .PARAMETER UserDataRoots
        Array of user data root directories
    .PARAMETER SerifFamily
        Serif font family name
    .PARAMETER SansSerifFamily
        Sans-serif font family name
    .PARAMETER MonospaceFamily
        Monospace font family name
    #>
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

#region System Maintenance

function Update-WindowsFontCache {
    <#
    .SYNOPSIS
        Refreshes Windows font cache by restarting font services and clearing cache files
    #>
    Write-LogMessage "Refreshing Windows Font Cache..."

    $fontServices = @('FontCache', 'FontCache3.0.0.0')
    foreach ($service in $fontServices) {
        try {
            Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
        }
        catch {
            # Continue if service stop fails
        }
    }

    $serviceCacheDir = "C:\Windows\ServiceProfiles\LocalService\AppData\Local\FontCache"
    $userCacheDir = Join-Path $env:LOCALAPPDATA "FontCache"

    foreach ($cacheDir in @($serviceCacheDir, $userCacheDir)) {
        try {
            if (Test-Path $cacheDir) {
                Get-ChildItem $cacheDir -Filter "*FontCache*" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
            }
        }
        catch {
            # Continue if cache cleanup fails
        }
    }

    foreach ($service in $fontServices) {
        try {
            Start-Service -Name $service -ErrorAction SilentlyContinue
        }
        catch {
            # Continue if service start fails
        }
    }

    Start-HumanLikeDelay
}

function Restart-WindowsExplorer {
    <#
    .SYNOPSIS
        Restarts Windows Explorer to apply font changes
    #>
    Write-LogMessage "Restarting Explorer..."
    Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Process explorer.exe
}

function Backup-FontRegistryKeys {
    <#
    .SYNOPSIS
        Creates backup of font-related registry keys
    #>
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
    <#
    .SYNOPSIS
        Restores system font mappings to Windows defaults
    #>
    Write-LogMessage "Restoring system font mappings to defaults..."

    $fontSubstitutesKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes'
    Remove-ItemProperty -Path $fontSubstitutesKey -Name 'Segoe UI' -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $fontSubstitutesKey -Name 'MS Shell Dlg' -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $fontSubstitutesKey -Name 'MS Shell Dlg 2' -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $fontSubstitutesKey -Name 'Segoe UI Symbol' -ErrorAction SilentlyContinue
}

#endregion

#region Main Execution Logic

function Invoke-FontInstallationProcess {
    <#
    .SYNOPSIS
        Main font installation process
    #>

    # Get random font families
    $randomFamilies = Select-RandomFontFamilies -Count $FontsPerRun -IncludeMonospace:$IncludeMonospace
    if (-not $randomFamilies -or $randomFamilies.Count -eq 0) {
        # Fallback to OFL directories
        $oflDirectories = Get-GoogleFontsOflDirectoriesFromGitHub
        if (-not $oflDirectories -or $oflDirectories.Count -eq 0) {
            $oflDirectories = Get-GoogleFontsOflDirectoriesFromJsDelivr
        }
        if (-not $oflDirectories -or $oflDirectories.Count -eq 0) {
            throw "No Google Fonts OFL entries found."
        }

        $random = New-Object System.Random
        $randomFamilies = @()
        while ($randomFamilies.Count -lt $FontsPerRun) {
            $candidate = ($oflDirectories | Sort-Object { $random.Next() } | Select-Object -First 1)
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

        # Try Google ZIP download (often fails due to API changes, so we skip to OFL)
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

        # Fallback to OFL directory (skip for now due to API issues)
        if (-not $installationSuccess) {
            Write-LogMessage ("Skipping OFL fallback for {0} due to API limitations" -f $familyName)
            # For now, we'll skip the complex OFL download and just use coverage fonts
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
        foreach ($detectedFamily in (Get-FontFamilyNamesFromFiles -FontFiles $fontFiles)) {
            [void]$installedFamilies.Add($detectedFamily)
        }
        [void]$installedFamilies.Add($familyName)
    }

    return @($installedFamilies)
}

function Invoke-CoverageFontInstallation {
    <#
    .SYNOPSIS
        Ensures at least one coverage font is installed
    .PARAMETER InstalledFamilies
        Currently installed font families
    #>
    param([string[]]$InstalledFamilies)

    $coverageInstalled = @()
    foreach ($coverageFamily in $script:CoverageFamilies) {
        if ($InstalledFamilies -contains $coverageFamily) {
            $coverageInstalled += $coverageFamily
        }
    }

    if ($coverageInstalled.Count -eq 0) {
        Write-LogMessage "No coverage fonts installed, using system fonts as fallback"
        # For now, just add some common system fonts as coverage
        $systemFonts = @("Arial", "Times New Roman", "Courier New")
        return $InstalledFamilies + $systemFonts
    }

    return $InstalledFamilies
}

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
