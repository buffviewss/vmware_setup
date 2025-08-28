<#
Human-grade, real system font changer for Windows 10 — v3.1
(One-click defaults; random real installs; Unicode hash impact; robust network + caching + logs)

What’s new vs v3.0 (patch set 1,3,4,5,6,7):
1) Add 'Comic Sans MS' and 'Impact' to FontLink bases (BrowserLeaks cursive/fantasy).
3) Robust network: retry with backoff around HTTP ops.
4) Persistent cache: %ProgramData%\FontRealCache for ZIP/TTF/OTF so later runs are faster/offline-friendly.
5) Human-like jitter sleeps around network/registry ops.
6) If user doesn't pass FontsPerRun, randomly pick 2 or 3 (natural variability).
7) Structured logging to %ProgramData%\FontReal\logs\YYYYMMDD-HHMMSS.log

Other key behaviors kept:
- True install through Fonts Shell, no JS/extension fake.
- Random Google families each run (Google catalog ➜ GitHub OFL ➜ jsDelivr data fallback).
- Ensure Unicode Glyphs changes: install a coverage family (Noto Sans/Serif/Symbols 2/1), prepend FontLink (incl. Segoe UI Symbol), and map 'Segoe UI Symbol' to coverage by default.
- Update Chrome/Edge default fonts for every profile; refresh Windows Font Cache; restart Explorer.
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

# ---- One-click defaults if user runs with no args ----
if(-not $PSBoundParameters.ContainsKey('IncludeMonospace')) { $IncludeMonospace = $true }
if(-not $PSBoundParameters.ContainsKey('Cleanup')) { $Cleanup = $true }
if(-not $PSBoundParameters.ContainsKey('FontsPerRun')) { $FontsPerRun = Get-Random -InputObject @(2,3) }

# --------------------------- CONSTS ---------------------------
$CoverageFamilies = @('Noto Sans','Noto Serif','Noto Sans Symbols 2','Noto Sans Symbols')
$BaseFamiliesToAugment = @(
  'Segoe UI','Arial','Times New Roman','Courier New','Microsoft Sans Serif',
  'Segoe UI Symbol','Comic Sans MS','Impact' # (1) add cursive/fantasy bases BL uses
)

# --------------------------- PATHS & LOG ---------------------------
$TempRoot    = Join-Path -Path $env:TEMP -ChildPath ("FontInstall-" + (Get-Date -Format yyyyMMdd-HHmmss))
$BackupDir   = Join-Path -Path $TempRoot -ChildPath "RegistryBackup"
$ExtractRoot = Join-Path -Path $TempRoot -ChildPath "unzipped"
$CacheDir    = Join-Path -Path $env:ProgramData -ChildPath "FontRealCache"   # (4) persistent cache
$LogDir      = Join-Path -Path $env:ProgramData -ChildPath "FontReal\logs"   # (7) logs
$LogFile     = Join-Path -Path $LogDir -ChildPath ("run-" + (Get-Date -Format yyyyMMdd-HHmmss) + ".log")

# --------------------------- HELPERS: ENV ---------------------------
function Assert-Admin {
  $id=[Security.Principal.WindowsIdentity]::GetCurrent()
  $p =New-Object Security.Principal.WindowsPrincipal($id)
  if(-not $p.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)){
    throw "Please run PowerShell as Administrator."
  }
}
function Ensure-Dirs {
  foreach($d in @($TempRoot,$BackupDir,$ExtractRoot,$CacheDir,$LogDir)){
    if(-not(Test-Path $d)){ New-Item -ItemType Directory -Path $d | Out-Null }
  }
}
function Ensure-Tls12 { try{ [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.ServicePointManager]::SecurityProtocol } catch {} }

function Write-Log {
  param([string]$Msg)
  $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  $line = "[{0}] {1}" -f $ts, $Msg
  Write-Host $line
  try{ Add-Content -Path $LogFile -Value $line } catch {}
}

function Jitter { param([int]$Min=200,[int]$Max=900) Start-Sleep -Milliseconds (Get-Random -Min $Min -Max $Max) } # (5)

# (3) Retry helper
function Invoke-WithRetry {
  param([scriptblock]$Action,[int]$Times=3,[int]$BaseDelayMs=500)
  for($i=1;$i -le $Times;$i++){
    try{ return & $Action } catch {
      if($i -eq $Times){ throw }
      Start-Sleep -Milliseconds ($BaseDelayMs * [math]::Pow(2, $i-1))
    }
  }
}

function New-HttpClient {
  param([string]$Accept="*/*",[string]$Referer="")
  Ensure-Tls12
  Add-Type -AssemblyName System.Net.Http
  $handler = New-Object System.Net.Http.HttpClientHandler
  $handler.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
  $handler.AllowAutoRedirect = $true
  if($ProxyUrl){
    $wp = New-Object System.Net.WebProxy($ProxyUrl,$true)
    if($ProxyCredential){ $wp.Credentials = $ProxyCredential.GetNetworkCredential() } else { $wp.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials }
    $handler.UseProxy = $true; $handler.Proxy = $wp
  } elseif($UseSystemProxy){
    $handler.UseProxy = $true; $handler.Proxy = [System.Net.WebRequest]::DefaultWebProxy
    if($handler.Proxy){ $handler.Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials }
  } else { $handler.UseProxy = $false }
  $client = New-Object System.Net.Http.HttpClient($handler)
  $client.Timeout = [TimeSpan]::FromMinutes(8)
  $client.DefaultRequestHeaders.UserAgent.ParseAdd("Mozilla/5.0 (Windows NT 10.0; Win64; x64) PowerShell")
  $client.DefaultRequestHeaders.Accept.ParseAdd($Accept)
  if($Referer){ $client.DefaultRequestHeaders.Referrer = [Uri]$Referer }
  return $client
}
function Download-HttpClient {
  param([string]$Url,[string]$OutFile,[string]$Accept="*/*",[string]$Referer="")
  Invoke-WithRetry -Times 3 -Action {
    $client = New-HttpClient -Accept $Accept -Referer $Referer
    try{
      $resp = $client.GetAsync($Url, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).Result
      if(-not $resp.IsSuccessStatusCode){ throw ("HTTP {0} {1}" -f [int]$resp.StatusCode, $resp.ReasonPhrase) }
      $in  = $resp.Content.ReadAsStreamAsync().Result
      $out = [System.IO.File]::Open($OutFile,[System.IO.FileMode]::Create,[System.IO.FileAccess]::Write,[System.IO.FileShare]::None)
      try { $in.CopyTo($out) } finally { $out.Close(); $in.Close(); $client.Dispose() }
    } catch { $client.Dispose(); throw }
  }
}

function Get-String {
  param([string]$Url,[string]$Accept="*/*",[string]$Referer="")
  Invoke-WithRetry -Times 3 -Action {
    $client = New-HttpClient -Accept $Accept -Referer $Referer
    try{ return $client.GetStringAsync($Url).Result } catch { $client.Dispose(); throw } finally { $client.Dispose() }
  }
}

# --------------------------- CACHE (4) ---------------------------
function Get-CachedOrDownload {
  param([string]$Url,[string]$PreferredName,[string]$Accept="*/*",[string]$Referer="")
  $name = $PreferredName
  if(-not $name -or $name.Trim().Length -eq 0){
    try{ $name = [System.IO.Path]::GetFileName([Uri]$Url) } catch { $name = [Guid]::NewGuid().ToString() }
  }
  $cachePath = Join-Path $CacheDir $name
  if(Test-Path $cachePath){
    Write-Log ("Cache hit: {0}" -f $name)
  } else {
    Write-Log ("Cache miss, downloading: {0}" -f $Url)
    Download-HttpClient -Url $Url -OutFile $cachePath -Accept $Accept -Referer $Referer
  }
  return $cachePath
}

# --------------------------- ZIP/FILES ---------------------------
function Test-ZipFileValid {
  param([string]$ZipPath)
  if(-not(Test-Path $ZipPath)){ return $false }
  $fi = Get-Item $ZipPath -ErrorAction SilentlyContinue
  if(-not $fi -or $fi.Length -lt 200){ return $false }
  $fs=[System.IO.File]::Open($ZipPath,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,[System.IO.FileShare]::ReadWrite)
  try{ $b = New-Object byte[] 2; $null = $fs.Read($b,0,2); if($b[0]-ne 0x50 -or $b[1]-ne 0x4B){ return $false } } finally { $fs.Close() }
  try{
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $stream=[System.IO.File]::OpenRead($ZipPath)
    try{ $zip=New-Object System.IO.Compression.ZipArchive($stream,[System.IO.Compression.ZipArchiveMode]::Read,$false); $null=$zip.Entries.Count; $zip.Dispose() }
    finally{ $stream.Dispose() }
    return $true
  } catch { return $false }
}
function Expand-Zip {
  param([string]$ZipPath,[string]$OutDir)
  if(Test-Path $OutDir){ Remove-Item -Recurse -Force $OutDir -ErrorAction SilentlyContinue }
  New-Item -ItemType Directory -Path $OutDir | Out-Null
  try{ Expand-Archive -Path $ZipPath -DestinationPath $OutDir -Force } catch {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath,$OutDir)
  }
}

# --------------------------- GOOGLE CATALOG ---------------------------
function Get-GF-CatalogFamilies {
  $raw = Get-String -Url "https://fonts.google.com/metadata/fonts" -Accept "application/json" -Referer "https://fonts.google.com/"
  if([string]::IsNullOrWhiteSpace($raw)){ return @() }
  $trim = $raw.Trim(); if($trim.StartsWith(")]}'")){ $trim = $trim.Substring(4) }
  try{ ($trim | ConvertFrom-Json).familyMetadataList.family | Select-Object -Unique } catch { @() }
}
function Pick-Random-Families {
  param([int]$Count,[switch]$WantMono)
  $names = Get-GF-CatalogFamilies
  if(-not $names -or $names.Count -eq 0){ return @() }
  $r = New-Object System.Random
  $pick = New-Object System.Collections.Generic.List[string]
  if($WantMono){
    $mono = ($names | Where-Object { $_ -match '(?i)Mono|Code' } | Sort-Object { $r.Next() } | Select-Object -First 1)
    if($mono){ $pick.Add($mono) | Out-Null }
  }
  while($pick.Count -lt $Count){
    $cand = ($names | Sort-Object { $r.Next() } | Select-Object -First 1)
    if($pick -notcontains $cand){ $pick.Add($cand) | Out-Null }
  }
  ,$pick.ToArray()
}
function Get-GoogleZipUrl { param([string]$FamilyName) $enc=[Uri]::EscapeDataString($FamilyName); "https://fonts.google.com/download?family=$enc" }

# --------------------------- GitHub/jsDelivr OFL fallbacks ---------------------------
function Get-GF-OFL-Dirs-GitHub {
  param([int]$MaxPages=6)
  $all = New-Object System.Collections.Generic.List[string]
  for($page=1; $page -le $MaxPages; $page++){
    $api = "https://api.github.com/repos/google/fonts/contents/ofl?page=$page&per_page=100"
    $raw = Get-String -Url $api -Accept "application/vnd.github+json"
    if([string]::IsNullOrWhiteSpace($raw)){ break }
    $json = $raw | ConvertFrom-Json
    $dirs = $json | Where-Object { $_.type -eq 'dir' } | ForEach-Object { $_.name }
    if(-not $dirs -or $dirs.Count -eq 0){ break }
    $dirs | ForEach-Object { $all.Add($_) | Out-Null }
  }
  $all.ToArray()
}
$global:JsDelivrFlat = $null
function Ensure-JsDelivrFlat {
  if($global:JsDelivrFlat -ne $null){ return }
  $raw = Get-String -Url "https://data.jsdelivr.com/v1/package/gh/google/fonts@main/flat" -Accept "application/json"
  if(-not [string]::IsNullOrWhiteSpace($raw)){ $global:JsDelivrFlat = $raw | ConvertFrom-Json } else { $global:JsDelivrFlat = @{} }
}
function Get-GF-OFL-Dirs-JsDelivr {
  Ensure-JsDelivrFlat
  $files = $global:JsDelivrFlat.files
  if(-not $files){ return @() }
  $dirs = New-Object System.Collections.Generic.HashSet[string]
  foreach($f in $files){
    $n = $f.name
    if($n -match '^ofl/([^/]+)/.*\.(ttf|otf)$'){ [void]$dirs.Add($matches[1]) }
  }
  ,$dirs.ToArray()
}
function Fetch-TTFs-FromGF {
  param([string]$GFDir,[string]$OutDir)
  if(-not(Test-Path $OutDir)){ New-Item -ItemType Directory -Path $OutDir | Out-Null }
  $entries = @()

  # GitHub API
  $raw = Get-String -Url ("https://api.github.com/repos/google/fonts/contents/ofl/{0}" -f $GFDir) -Accept "application/vnd.github+json"
  if($raw){
    $json = $raw | ConvertFrom-Json
    $entries += ($json | Where-Object { $_.type -eq 'file' -and $_.name -match '\.(ttf|otf)$' })
    $static = $json | Where-Object { $_.type -eq 'dir' -and $_.name -eq 'static' }
    if($static){
      $raw2 = Get-String -Url ("https://api.github.com/repos/google/fonts/contents/ofl/{0}/static" -f $GFDir) -Accept "application/vnd.github+json"
      if($raw2){
        $json2 = $raw2 | ConvertFrom-Json
        $entries += ($json2 | Where-Object { $_.type -eq 'file' -and $_.name -match '\.(ttf|otf)$' })
      }
    }
  }

  # jsDelivr fallback
  if(-not $entries -or $entries.Count -eq 0){
    Ensure-JsDelivrFlat
    $files = $global:JsDelivrFlat.files
    if($files){
      $entries = @()
      foreach($f in $files){
        $n = $f.name
        if($n -match ("^ofl/{0}/.*\.(ttf|otf)$" -f [Regex]::Escape($GFDir))){
          $entries += [PSCustomObject]@{ name=(Split-Path $n -Leaf); download_url=("https://cdn.jsdelivr.net/gh/google/fonts@main/{0}" -f $n) }
        }
      }
    }
  }

  $downloaded=@()
  foreach($e in $entries){
    $dest = Join-Path $OutDir $e.name
    $url  = if($e.download_url){ $e.download_url } else { "https://raw.githubusercontent.com/google/fonts/main/ofl/$GFDir/$($e.name)" }
    try{
      $cached = Get-CachedOrDownload -Url $url -PreferredName $e.name -Accept "application/octet-stream"
      Copy-Item $cached $dest -Force
      $fi=Get-Item $dest -ErrorAction SilentlyContinue
      if($fi -and $fi.Length -gt 10000){ $downloaded += $dest }
    } catch { Write-Log ("DL fail {0}: {1}" -f $url,$_.Exception.Message) }
    if($downloaded.Count -ge 6){ break }
  }
  $downloaded
}

# --------------------------- FILE FILTER ---------------------------
function Get-UiFontFiles {
  param([string]$Folder)
  $all = Get-ChildItem -Path $Folder -Recurse -Include *.ttf, *.otf -ErrorAction SilentlyContinue
  if(-not $all){ return @() }
  $nonItalic = $all | Where-Object { $_.Name -notmatch '(Italic|Oblique)' }
  $preferred = $nonItalic | Where-Object { $_.Name -match '(?i)(Regular|Book|Roman|Text|Medium|500|400|VariableFont|\[wght\])' }
  $chosen = if($preferred){ $preferred } else { $nonItalic }
  $chosen | Select-Object -First 8
}

# --------------------------- VENDOR QUICK (coverage) ---------------------------
function Get-Vendor-Urls {
  param([string]$FamilyName)
  switch -Regex ($FamilyName) {
    '^Noto Sans$'            { @('https://raw.githubusercontent.com/notofonts/noto-fonts/main/hinted/ttf/NotoSans/NotoSans-Regular.ttf'); break }
    '^Noto Serif$'           { @('https://raw.githubusercontent.com/notofonts/noto-fonts/main/hinted/ttf/NotoSerif/NotoSerif-Regular.ttf'); break }
    '^Noto Sans Symbols 2$'  { @('https://raw.githubusercontent.com/notofonts/noto-fonts/main/hinted/ttf/NotoSansSymbols2/NotoSansSymbols2-Regular.ttf'); break }
    '^Noto Sans Symbols$'    { @('https://raw.githubusercontent.com/notofonts/noto-fonts/main/hinted/ttf/NotoSansSymbols/NotoSansSymbols-Regular.ttf'); break }
    default { @() }
  }
}
function Try-Fetch-From-Urls {
  param([string[]]$Urls,[string]$OutDir)
  $downloaded=$false
  foreach($u in $Urls){
    try{
      $fileName = [System.IO.Path]::GetFileName($u); if($fileName -eq '' -or $fileName -eq $null){ $fileName = [Guid]::NewGuid().ToString() }
      $tmp = Join-Path $TempRoot $fileName
      $cached = Get-CachedOrDownload -Url $u -PreferredName $fileName -Accept "application/octet-stream"
      Copy-Item $cached $tmp -Force
      Copy-Item $tmp (Join-Path $OutDir $fileName) -Force
      $downloaded=$true
    } catch { Write-Log ("Fetch failed: {0}" -f $_.Exception.Message) }
  }
  return $downloaded
}

# --------------------------- INSTALL & VERIFY ---------------------------
function Install-FontFile {
  param([string]$FontPath)
  if(-not(Test-Path $FontPath)){ return }
  $shell = New-Object -ComObject Shell.Application
  $fonts = $shell.Namespace(0x14); if(-not $fonts){ throw "Cannot access Fonts Shell." }
  Write-Log ("Installing font file: {0}" -f $FontPath)
  $fonts.CopyHere($FontPath); Jitter
}
function Install-FontSet {
  param([System.IO.FileInfo[]]$Files)
  $installed=@()
  foreach($f in $Files){
    try{ Install-FontFile -FontPath $f.FullName; $installed += $f.FullName }
    catch{ Write-Log ("Install failed: {0} - {1}" -f $f.Name,$_.Exception.Message) }
  }
  $installed
}
function Guess-FamilyFromFiles {
  param([System.IO.FileInfo[]]$Files)
  $names = New-Object System.Collections.Generic.HashSet[string]
  foreach($f in $Files){
    $n = $f.BaseName -replace '[-_](Regular|Book|Roman|Text|Medium|Light|Bold|Black|Thin|Extra.*|Semi.*|Variable.*|[0-9]+|Italic|Oblique)$',''
    $n = ($n -replace '[-_]+',' ').Trim()
    if($n.Length -gt 1){ [void]$names.Add($n) }
  }
  ,$names.ToArray()
}

# --------------------------- RANDOM HELPERS ---------------------------
function Get-Shuffled { param([object[]]$Array) if(-not $Array){ return @() } $r = New-Object System.Random; $Array | Sort-Object { $r.Next() } }

# --------------------------- SYSTEM MAPPING ---------------------------
function Set-SystemFont {
  param([string]$FontFamily)
  $fsKey='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes'
  New-Item -Path $fsKey -Force | Out-Null
  New-ItemProperty -Path $fsKey -Name 'Segoe UI'       -Value $FontFamily -PropertyType String -Force | Out-Null
  New-ItemProperty -Path $fsKey -Name 'MS Shell Dlg'   -Value $FontFamily -PropertyType String -Force | Out-Null
  New-ItemProperty -Path $fsKey -Name 'MS Shell Dlg 2' -Value $FontFamily -PropertyType String -Force | Out-Null
  Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'FontSmoothing' -Value '2' -Force
  Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'FontSmoothingType' -Value 2 -Type DWord -Force
  Write-Log ("Set system base font -> {0}" -f $FontFamily)
  Jitter
}
function Prepend-FontLink {
  param([string[]]$FamiliesToPrioritize,[string[]]$CoverageFirst)
  if(-not $FamiliesToPrioritize -or $FamiliesToPrioritize.Count -eq 0){ return }
  $linkKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontLink\SystemLink'
  New-Item -Path $linkKey -Force | Out-Null
  $regFonts = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts' -ErrorAction SilentlyContinue
  if(-not $regFonts){ return }

  $linesByFamily = @{}
  foreach($fam in $FamiliesToPrioritize){
    $matches = $regFonts.PSObject.Properties | Where-Object { $_.Name -match [Regex]::Escape($fam).Replace('\ ','\s+') }
    $pairs = @()
    foreach($m in $matches){
      $file = [string]$m.Value
      if($file -and ($file -match '\.ttf$' -or $file -match '\.otf$')){ $pairs += ("{0},{1}" -f $file, $fam) }
    }
    if($pairs.Count -gt 0){ $linesByFamily[$fam] = $pairs }
  }

  $presentCoverage = @(); foreach($cf in $CoverageFirst){ if($linesByFamily.ContainsKey($cf)){ $presentCoverage += $cf } }
  $others = ($FamiliesToPrioritize | Where-Object { $_ -notin $presentCoverage })
  $ordered = @($presentCoverage + (Get-Shuffled -Array $others))

  foreach($base in $BaseFamiliesToAugment){
    $existing = (Get-ItemProperty -Path $linkKey -Name $base -ErrorAction SilentlyContinue).$base
    if(-not $existing){ $existing = @() }

    $ourLines = @()
    foreach($fam in $ordered){
      if($linesByFamily.ContainsKey($fam)){
        foreach($ln in $linesByFamily[$fam]){
          if(-not ($ourLines -contains $ln)){ $ourLines += $ln }
        }
      }
    }
    $combined = @($ourLines + $existing)
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'; $final = New-Object System.Collections.Generic.List[string]
    foreach($ln in $combined){ if([string]::IsNullOrWhiteSpace($ln)){ continue }; if($seen.Add($ln)){ [void]$final.Add($ln) } }
    if($final.Count -gt 0){
      Set-ItemProperty -Path $linkKey -Name $base -Type MultiString -Value $final
      Write-Log ("FontLink prepended for base '{0}' with {1} entries" -f $base,$final.Count)
    }
    Jitter
  }
}
function Map-SegoeUISymbol {
  param([string]$ToFamily)
  if([string]::IsNullOrWhiteSpace($ToFamily)){ return }
  $fsKey='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes'
  try{
    New-Item -Path $fsKey -Force | Out-Null
    New-ItemProperty -Path $fsKey -Name 'Segoe UI Symbol' -Value $ToFamily -PropertyType String -Force | Out-Null
    Write-Log ("Mapped 'Segoe UI Symbol' -> {0}" -f $ToFamily)
  } catch {}
}

# --------------------------- CHROMIUM DEFAULT FONTS ---------------------------
function Stop-ChromiumIfRunning { foreach($name in @('chrome','msedge','chrome.exe','msedge.exe')){ try{ Get-Process $name -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue } catch {} } }
function Get-ChromiumUserDataRoots {
  $roots = New-Object System.Collections.Generic.List[string]
  try{
    $procs = Get-CimInstance Win32_Process -Filter "Name='chrome.exe' OR Name='msedge.exe'"
    foreach($p in $procs){
      $cmd = $p.CommandLine
      if($cmd -and ($cmd -match '--user-data-dir=(?:"([^"]+)"|(\S+))')){
        $ud = if($matches[1]){ $matches[1] } else { $matches[2] }
        if(Test-Path $ud){ $roots.Add($ud) | Out-Null }
      }
    }
  } catch {}
  $userDirs = Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '^(All Users|Default|Default User|Public|DefaultAppPool)$' }
  $chromes = @('Google\Chrome\User Data','Google\Chrome Beta\User Data','Google\Chrome Dev\User Data','Google\Chrome SxS\User Data','Chromium\User Data')
  $edges   = @('Microsoft\Edge\User Data','Microsoft\Edge Beta\User Data','Microsoft\Edge Dev\User Data','Microsoft\Edge SxS\User Data')
  foreach($u in $userDirs){ foreach($suffix in ($chromes + $edges)){ foreach($rootType in @('Local','Roaming')){ $p = Join-Path $u.FullName ("AppData\{0}\{1}" -f $rootType,$suffix); if(Test-Path $p){ $roots.Add($p) | Out-Null } } } }
  $cands = @((Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'),(Join-Path $env:LOCALAPPDATA 'Chromium\User Data'),(Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data'),(Join-Path $env:APPDATA 'Google\Chrome\User Data'),(Join-Path $env:APPDATA 'Microsoft\Edge\User Data'))
  foreach($p in $cands){ if(Test-Path $p){ $roots.Add($p) | Out-Null } }
  ($roots.ToArray() | Where-Object { Test-Path $_ } | Select-Object -Unique)
}
function Set-ChromiumDefaultFonts {
  param([string[]]$UserDataRoots,[string]$SerifFamily,[string]$SansFamily,[string]$MonoFamily)
  foreach($UserDataRoot in $UserDataRoots){
    $profiles = Get-ChildItem -Path $UserDataRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^(Default|Profile \d+|Guest Profile|System Profile)$' }
    foreach($p in $profiles){
      $pref = Join-Path $p.FullName 'Preferences'
      if(-not (Test-Path $pref)){ continue }
      try{
        $stamp = Get-Date -Format yyyyMMdd-HHmmss
        Copy-Item $pref ($pref + ".bak-$stamp") -Force -ErrorAction SilentlyContinue
        $json = Get-Content $pref -Raw -ErrorAction Stop | ConvertFrom-Json
        if(-not $json.fonts){ $json | Add-Member -NotePropertyName fonts -NotePropertyValue (@{}) }
        foreach($k in @('serif','sansserif','standard','fixed','cursive','fantasy')){ if(-not $json.fonts.$k){ $json.fonts.$k = @{} } }
        $json.fonts.serif.Zyyy      = $SerifFamily
        $json.fonts.standard.Zyyy   = $SerifFamily
        $json.fonts.sansserif.Zyyy  = $SansFamily
        $json.fonts.fixed.Zyyy      = $MonoFamily
        if(-not $json.fonts.cursive.Zyyy){  $json.fonts.cursive.Zyyy = $SansFamily }
        if(-not $json.fonts.fantasy.Zyyy){  $json.fonts.fantasy.Zyyy = $SansFamily }
        $json | ConvertTo-Json -Depth 100 | Set-Content -Path $pref -Encoding UTF8
        Write-Log ("Updated Chromium Preferences: {0}" -f $pref)
      } catch { Write-Log ("Failed to update Chromium Preferences {0}: {1}" -f $pref,$_.Exception.Message) }
      Jitter
    }
  }
}

# --------------------------- REGISTRY UTILITIES ---------------------------
function Refresh-FontCache {
  Write-Log "Refreshing Windows Font Cache..."
  $services = @('FontCache','FontCache3.0.0.0')
  foreach($svc in $services){ try{ Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue } catch{} }
  $svcCache = "C:\Windows\ServiceProfiles\LocalService\AppData\Local\FontCache"; $usrCache = Join-Path $env:LOCALAPPDATA "FontCache"
  foreach($p in @($svcCache,$usrCache)){ try{ if(Test-Path $p){ Get-ChildItem $p -Filter "*FontCache*" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue } } catch {} }
  foreach($svc in $services){ try{ Start-Service -Name $svc -ErrorAction SilentlyContinue } catch{} }
  Jitter
}
function Restart-Explorer { Write-Log "Restarting Explorer..."; Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue; Start-Process explorer.exe }

function Backup-FontRegistry {
  Write-Log "Backing up registry keys..."
  $items=@('HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes','HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontLink\SystemLink','HKCU\Control Panel\Desktop')
  foreach($k in $items){
    $safe=($k -replace '[\\/:*?"<>| ]','_')
    $out=Join-Path $BackupDir "$safe.reg"
    & reg.exe export $k $out /y | Out-Null
  }
  Jitter
}
function Restore-DefaultFont {
  Write-Log "Restoring system font mappings to defaults..."
  $fsKey='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes'
  Remove-ItemProperty -Path $fsKey -Name 'Segoe UI' -ErrorAction SilentlyContinue
  Remove-ItemProperty -Path $fsKey -Name 'MS Shell Dlg' -ErrorAction SilentlyContinue
  Remove-ItemProperty -Path $fsKey -Name 'MS Shell Dlg 2' -ErrorAction SilentlyContinue
  Remove-ItemProperty -Path $fsKey -Name 'Segoe UI Symbol' -ErrorAction SilentlyContinue
}

# --------------------------- MAIN ---------------------------
try{
  Assert-Admin; Ensure-Dirs
  Write-Log ("Log file: {0}" -f $LogFile)

  if($RestoreDefault){
    Restore-DefaultFont; Refresh-FontCache; if(-not $NoRestartExplorer){ Restart-Explorer }
    Write-Log "Done. System font reverted. Sign out or reboot may be required."
    if($Cleanup){ if(Test-Path $TempRoot){ Remove-Item -Recurse -Force $TempRoot -ErrorAction SilentlyContinue } }
    exit 0
  }

  # Random families (catalog) else OFL fallbacks
  $randomFamilies = Pick-Random-Families -Count $FontsPerRun -WantMono:$IncludeMonospace
  if(-not $randomFamilies -or $randomFamilies.Count -eq 0){
    $ofl = (Get-GF-OFL-Dirs-GitHub); if(-not $ofl -or $ofl.Count -eq 0){ $ofl = Get-GF-OFL-Dirs-JsDelivr }
    if(-not $ofl -or $ofl.Count -eq 0){ throw "No Google Fonts OFL entries found." }
    $r = New-Object System.Random
    $randomFamilies = @(); while($randomFamilies.Count -lt $FontsPerRun){ $cand = ($ofl | Sort-Object { $r.Next() } | Select-Object -First 1); if($randomFamilies -notcontains $cand){ $randomFamilies += $cand } }
  }
  Write-Log ("Random Google families/dirs: {0}" -f ($randomFamilies -join ", "))

  $sessionFamilies = New-Object System.Collections.Generic.HashSet[string] # only this run

  foreach($fam in $randomFamilies){
    $safe = ($fam -replace '[^a-zA-Z0-9\-]','_')
    $zip  = Join-Path $TempRoot ($safe + ".zip")
    $dest = Join-Path $ExtractRoot $safe
    if(-not (Test-Path $dest)){ New-Item -ItemType Directory -Path $dest | Out-Null }
    $ok = $false

    # Try Google ZIP
    try{
      $url = Get-GoogleZipUrl -FamilyName $fam
      $cachedZip = Get-CachedOrDownload -Url $url -PreferredName ($safe + ".zip") -Accept "application/zip, */*" -Referer "https://fonts.google.com/"
      if(Test-ZipFileValid -ZipPath $cachedZip){ Expand-Zip -ZipPath $cachedZip -OutDir $dest; $ok = $true }
    } catch { Write-Log ("ZIP failed for {0}: {1}" -f $fam,$_.Exception.Message) }

    # If failed, try OFL dir by slug
    if(-not $ok){
      $slug = ($fam.ToLower() -replace '[^a-z0-9]','')
      try{ $ttfs = Fetch-TTFs-FromGF -GFDir $slug -OutDir $dest; if($ttfs -and $ttfs.Count -gt 0){ $ok = $true } } catch { Write-Log ("OFL fetch failed for {0}: {1}" -f $fam,$_.Exception.Message) }
    }

    if(-not $ok -and $ExtraUrls){ if(Try-Fetch-From-Urls -Urls $ExtraUrls -OutDir $dest){ $ok = $true } }
    if(-not $ok -and $LocalFolder -and (Test-Path $LocalFolder)){ Copy-Item -Path (Join-Path $LocalFolder '*') -Destination $dest -Recurse -Force -ErrorAction SilentlyContinue; $ok = $true }

    $uiFiles = Get-UiFontFiles -Folder $dest
    if(-not $ok -or -not $uiFiles -or $uiFiles.Count -eq 0){ Write-Log ("No usable fonts found for {0}. Skipping." -f $fam); continue }

    [void](Install-FontSet -Files $uiFiles)
    foreach($n in (Guess-FamilyFromFiles -Files $uiFiles)){ [void]$sessionFamilies.Add($n) }
    [void]$sessionFamilies.Add($fam)
  }

  # Ensure at least one coverage family
  $coverageInstalled = @()
  foreach($c in $CoverageFamilies){ if($sessionFamilies.Contains($c)){ $coverageInstalled += $c } }
  if($coverageInstalled.Count -eq 0){
    $cov = Get-Random -InputObject $CoverageFamilies
    $cdir = Join-Path $ExtractRoot "coverage"; if(-not (Test-Path $cdir)){ New-Item -ItemType Directory -Path $cdir | Out-Null }
    $vendor = Get-Vendor-Urls -FamilyName $cov
    if($vendor.Count -gt 0 -and (Try-Fetch-From-Urls -Urls $vendor -OutDir $cdir)){
      $files = Get-UiFontFiles -Folder $cdir
      if($files -and $files.Count -gt 0){ [void](Install-FontSet -Files $files); foreach($n in (Guess-FamilyFromFiles -Files $files)){ [void]$sessionFamilies.Add($n) }; [void]$sessionFamilies.Add($cov); $coverageInstalled = @($cov) }
    }
  }

  if($sessionFamilies.Count -eq 0){ throw "No font families were installed this session." }
  $newFamilies = $sessionFamilies.ToArray()
  Write-Log ("New families this run: {0}" -f ($newFamilies -join ", "))

  # Primary = any newly installed non-symbol font
  $primary = ($newFamilies | Where-Object { $_ -notmatch '(?i)symbols|emoji|dingbats|math' } | Get-Random)
  if(-not $primary){ $primary = ($newFamilies | Get-Random) }

  Write-Log "Backing up registry and applying system mappings..."
  Backup-FontRegistry
  Set-SystemFont -FontFamily $primary

  # Prepend into FontLink with coverage-first
  $covFirst = @(); foreach($cf in $CoverageFamilies){ if($newFamilies -contains $cf){ $covFirst += $cf } }
  Prepend-FontLink -FamiliesToPrioritize $newFamilies -CoverageFirst $covFirst

  # Optionally substitute Segoe UI Symbol directly to coverage (first available)
  if(-not $NoSymbolSubstitute){
    $sym = ($CoverageFamilies | Where-Object { $newFamilies -contains $_ } | Select-Object -First 1)
    if($sym){ Map-SegoeUISymbol -ToFamily $sym }
  }

  # Update Chromium preferences to use broad-coverage families from this run
  Stop-ChromiumIfRunning
  $roots = Get-ChromiumUserDataRoots
  $serifPick = ($newFamilies | Where-Object { $_ -match '(?i)noto serif|serif' } | Select-Object -First 1); if(-not $serifPick){ $serifPick = $primary }
  $sansPick  = ($newFamilies | Where-Object { $_ -match '(?i)noto sans|inter|manrope|public sans' } | Select-Object -First 1); if(-not $sansPick){ $sansPick = $primary }
  $monoPick  = ($newFamilies | Where-Object { $_ -match '(?i)mono|code' } | Select-Object -First 1); if(-not $monoPick){ $monoPick = $primary }
  if($roots){ Set-ChromiumDefaultFonts -UserDataRoots $roots -SerifFamily $serifPick -SansFamily $sansPick -MonoFamily $monoPick }

  Refresh-FontCache; if(-not $NoRestartExplorer){ Restart-Explorer }

  Write-Log ("Completed. New families: {0}. Primary system font: {1}" -f ($newFamilies -join ", "), $primary)
  Write-Log ("Temporary working folder: {0}" -f $TempRoot)
  Write-Log "Note: Some UI areas may still require sign out or reboot to fully apply."

} catch {
  Write-Log ("ERROR: {0}" -f $_.Exception.Message)
  Write-Log ("Registry backup (if created): {0}" -f $BackupDir)
  exit 1
} finally {
  if($Cleanup){
    Write-Log "Cleaning up temporary files..."
    try{ if(Test-Path $TempRoot){ Remove-Item -Recurse -Force $TempRoot -ErrorAction SilentlyContinue } } catch {}
  }
}
