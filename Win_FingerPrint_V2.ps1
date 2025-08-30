<# ===================================================================
  ADVANCED FONT FINGERPRINT ROTATOR v3.13.5-API-GFKEY-TOKENINLINE-HOTFIX2
  - Nguồn tải qua API: Fontsource Data API, Google Web Fonts API (có key),
    CSS2 (Google/Bunny), FontLibrary API, GitHub Content API (qua jsDelivr/Statically by SHA).
  - Mỗi lần chạy cố gắng đổi cả Inventory (Font Metrics) & Unicode Glyphs.
  - Mặc định KHÔNG gỡ font đã cài (KeepGrowth = $true).
  - Patch default fonts Chrome/Edge (standard/serif/sans/fixed/cursive/fantasy).
  - Log: %USERPROFILE%\Downloads\log.txt
=================================================================== #>

param(
  [int]$InstallMin   = 12,
  [int]$InstallMax   = 18,
  [int]$UninstallMin = 6,
  [int]$UninstallMax = 10,
  [switch]$KeepGrowth = $true,     # giữ nguyên font cũ (no uninstall)
  [switch]$NoChromiumFonts = $false,
  [switch]$NoForceClose    = $false,
  [string]$ChromeProfile = "Default",
  [string]$EdgeProfile   = "Default",
  [int]$MaxRounds = 3,
  [string]$GoogleApiKey = $env:GF_API_KEY   # nếu trống sẽ dùng INLINE bên dưới
)

# ==== ĐIỀN KEY TẠI ĐÂY (tuỳ chọn) ====
$INLINE_GF_API_KEY   = ""   # ví dụ: "AIzaSyDxxxxxxxxxxxxxxxxxxxx"
$INLINE_GITHUB_TOKEN = ""   # ví dụ: "ghp_XXXXXXXXXXXXXXXXXXXXXXXXXXXX" (tùy chọn)

# Ưu tiên: tham số -> INLINE -> env
if ([string]::IsNullOrWhiteSpace($GoogleApiKey) -and -not [string]::IsNullOrWhiteSpace($INLINE_GF_API_KEY)) {
  $GoogleApiKey = $INLINE_GF_API_KEY
}
$Global:GITHUB_TOKEN = if(-not [string]::IsNullOrWhiteSpace($INLINE_GITHUB_TOKEN)){
  $INLINE_GITHUB_TOKEN
} elseif(-not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)){
  $env:GITHUB_TOKEN
} else { $null }

# ---- Admin check ----
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
   ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
  Write-Host "ERROR: Run PowerShell as Administrator!" -ForegroundColor Red
  Read-Host "Press Enter to exit"; exit 1
}

$Version = "3.13.5-API-GFKEY-TOKENINLINE-HOTFIX2"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ---- Logging ----
$DownloadDir = Join-Path $env:USERPROFILE 'Downloads'
if (!(Test-Path $DownloadDir)) { New-Item -ItemType Directory -Path $DownloadDir -Force | Out-Null }
$LogFile = Join-Path $DownloadDir 'log.txt'
Add-Content $LogFile ("`n=== RUN {0} ===" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
function Log { param([string]$msg,[string]$lvl="INFO")
  try { Add-Content $LogFile ("[{0}] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$lvl,$msg) } catch {}
}
function Say { param([string]$m,[string]$c="Cyan",[string]$lvl="INFO")
  Write-Host ("[{0}] {1}" -f (Get-Date -Format HH:mm:ss), $m) -ForegroundColor $c
  Log $m $lvl
}
function Head32 { param($s) if($s -and $s.Length -ge 32){$s.Substring(0,32)}elseif($s){$s}else{"NA"} }

# ---- Paths & State ----
$TempDir  = "$env:TEMP\FontRotator"
$FontsDir = "$env:SystemRoot\Fonts"
$StateKey = "HKLM:\SOFTWARE\FontRotator"
if (!(Test-Path $TempDir)) { New-Item -ItemType Directory -Path $TempDir -Force | Out-Null }
if (!(Test-Path $StateKey)) { New-Item -Path $StateKey -Force | Out-Null }

# ---- Pools ----
$FAMILIES = @{
  Sans  = @("Inter","Open Sans","Roboto","Noto Sans","Work Sans","Manrope","Poppins",
            "DM Sans","Karla","Rubik","Heebo","Outfit","Sora","Plus Jakarta Sans",
            "Nunito Sans","Mulish","Urbanist","Lato","Raleway","Montserrat",
            "Source Sans 3","PT Sans","Fira Sans","IBM Plex Sans")
  Serif = @("Merriweather","Lora","Libre Baskerville","Playfair Display","Source Serif 4",
            "Cardo","Crimson Pro","Cormorant Garamond","Old Standard TT","Domine",
            "Spectral","EB Garamond","Gentium Book Plus","Literata","Tinos")
  Mono  = @("JetBrains Mono","Source Code Pro","Inconsolata","Cousine","Anonymous Pro",
            "Iosevka","Fira Code","IBM Plex Mono","Ubuntu Mono","Red Hat Mono")
}

# Unicode boosters – lấy qua GitHub Content API (rồi tải qua CDN theo SHA)
$UNICODE_BOOST = @(
  @{ Owner="googlefonts"; Repo="noto-emoji"; Path="fonts";
     Pattern="(?i)^NotoColorEmoji\.ttf$"; Name="Noto Color Emoji" },

  @{ Owner="googlefonts"; Repo="noto-fonts"; Path="unhinted/ttf/NotoSansMath";
     Pattern="(?i)NotoSansMath-.*Regular\.ttf$"; Name="Noto Sans Math" },

  @{ Owner="googlefonts"; Repo="noto-fonts"; Path="unhinted/ttf/NotoMusic";
     Pattern="(?i)NotoMusic-.*Regular\.ttf$"; Name="Noto Music" },

  @{ Owner="googlefonts"; Repo="noto-fonts"; Path="unhinted/ttf/NotoSansSymbols2";
     Pattern="(?i)NotoSansSymbols2-.*Regular\.ttf$"; Name="Noto Sans Symbols 2" }
)

# ===================== API RESOLVERS =====================

# GitHub headers
$Global:GHHeaders = @{ 'User-Agent'='FontRotator/3.13.5' }
if($Global:GITHUB_TOKEN){
  $Global:GHHeaders['Authorization'] = "Bearer $Global:GITHUB_TOKEN"
  $Global:GHHeaders['Accept'] = 'application/vnd.github+json'
  $Global:GHHeaders['X-GitHub-Api-Version'] = '2022-11-28'
}


function New-GHCDNUrls {
  param([string]$Owner,[string]$Repo,[string]$Ref,[string]$Path,[string]$Name)
  @(
    "https://raw.githubusercontent.com/$Owner/$Repo/$Ref/$Path/$Name",  # link trực tiếp
    "https://cdn.jsdelivr.net/gh/$Owner/$Repo@$Ref/$Path/$Name",      # CDN jsDelivr
    "https://cdn.statically.io/gh/$Owner/$Repo@$Ref/$Path/$Name"      # CDN Statically
  )
}


# HOTFIX: không pipe ngay sau foreach; tích lũy trước rồi Unique
$__ghCache = @{}
$__ghCache = @{}
function Get-GitHubContentFiles {
  param(
    [string]$Owner,
    [string]$Repo,
    [string]$Path,
    [string]$Pattern = '\.(ttf|otf)$'
  )

  $key = "$Owner/$Repo/$Path/$Pattern"
  if ($__ghCache.ContainsKey($key)) { return $__ghCache[$key] }

  $tryPaths = @($Path)
  if ($Path -match '^hinted/')   { $tryPaths += ($Path -replace '^hinted/','unhinted/') }
  if ($Path -match '^unhinted/') { $tryPaths += ($Path -replace '^unhinted/','hinted/') }
  $tryPaths = $tryPaths | Select-Object -Unique

  # Get the default branch (usually 'main' or 'master')
  $ref  = Get-GHDefaultRef -Owner $Owner -Repo $Repo    
  $urls = @()

  # Ưu tiên các file Emoji theo thứ tự: WindowsCompatible, Emoji, NoFlags, ...
  $prefer = @()
  if ($Owner -eq 'googlefonts' -and $Repo -eq 'noto-emoji' -and $Path -eq 'fonts') {
    $prefer = @(
      'NotoColorEmoji_WindowsCompatible.ttf',
      'NotoColorEmoji.ttf',
      'NotoColorEmoji-noflags.ttf',
      'NotoColorEmoji-emojicompat.ttf',
      'Noto-COLRv1.ttf',
      'Noto-COLRv1-noflags.ttf',
      'Noto-COLRv1-emojiCompat.ttf'
    )
  }

  foreach($p in $tryPaths){
    try {
      $api = "https://api.github.com/repos/$Owner/$Repo/contents/$p"
      $items = Invoke-WebRequest -UseBasicParsing -TimeoutSec 60 -Headers $Global:GHHeaders $api | ConvertFrom-Json
      $files = $items | Where-Object { $_.type -eq 'file' -and $_.name -match $Pattern }

      if ($files) {
        # Sắp xếp file theo thứ tự ưu tiên
        if ($prefer.Count -gt 0) {
          $files = $files | Sort-Object @{Expression={
            $i = $prefer.IndexOf($_.name); if ($i -ge 0) { $i } else { 999 }
          }}
        }

        foreach($f in $files){
          if ($f.download_url) { $urls += $f.download_url }
          $urls += New-GHCDNUrls $Owner $Repo $ref $p $f.name
        }
      }
    } catch {
      Log ("GitHub API error ($Owner/$Repo/$p): $($_.Exception.Message)") "WARN"
    }
  }

  # Nếu không có link nào, dùng fallback bằng branch default 'main'
  if (-not $urls -or $urls.Count -eq 0) {
    foreach($p in $tryPaths){
      $urls += New-GHCDNUrls $Owner $Repo 'main' $p 'NotoColorEmoji.ttf'
    }
  }

  $urls = $urls | Where-Object { $_ -match '\.(ttf|otf)($|\?)' } | Select-Object -Unique
  $__ghCache[$key] = $urls
  return $urls
}



# Fontsource Data API
function Get-FontFromFontsourceAPI {
  param([string]$Family)
  $pkg = ($Family.ToLower() -replace '[\s_]+','-')
  $alias = @{
    "plus-jakarta-sans"="plus-jakarta-sans"; "source-serif-4"="source-serif-4"; "old-standard-tt"="old-standard-tt"
    "eb-garamond"="eb-garamond"; "ibm-plex-sans"="ibm-plex-sans"; "ibm-plex-mono"="ibm-plex-mono"
    "pt-sans"="pt-sans"; "fira-sans"="fira-sans"; "source-sans-3"="source-sans-3"; "red-hat-mono"="red-hat-mono"
    "playfair-display"="playfair-display"; "gentium-book-plus"="gentium-book-plus"; "jetbrains-mono"="jetbrains-mono"
  }
  if($alias.ContainsKey($pkg)){ $pkg = $alias[$pkg] }
  $api = "https://data.jsdelivr.com/v1/package/npm/@fontsource/$pkg@latest"
  try {
    $json = Invoke-WebRequest -UseBasicParsing -TimeoutSec 60 -Headers @{ 'User-Agent'='FontRotator/3.13.5' } $api | ConvertFrom-Json
  } catch { Log ("Fontsource API ($pkg) error: $($_.Exception.Message)") "WARN"; return @() }

  $all=@()
  function Walk($node, $prefix){
    foreach($f in $node.files){
      $p = if($prefix){ "$prefix/$($f.name)" } else { $f.name }
      if($f.type -eq "file"){ $script:all += $p } elseif($f.type -eq "directory"){ Walk $f $p }
    }
  }
  Walk $json ""

  $pick = $all | Where-Object { $_ -match '^files/.+-latin-400-normal\.ttf$' } | Select-Object -First 1
  if(-not $pick){ $pick = $all | Where-Object { $_ -match '^files/.+-all-400-normal\.ttf$' } | Select-Object -First 1 }
  if(-not $pick){ $pick = $all | Where-Object { $_ -match '^files/.+-400-normal\.ttf$' } | Select-Object -First 1 }
  if(-not $pick){ $pick = $all | Where-Object { $_ -match '^files/.+\.ttf$' } | Select-Object -First 1 }

  if($pick){
    return @(
      "https://cdn.jsdelivr.net/npm/@fontsource/$pkg/$pick",
      "https://unpkg.com/@fontsource/$pkg/$pick"
    )
  }
  @()
}

# CSS2 (Google/Bunny)
function Get-FontFromCSS2 {
  param(
    [string]$Family,
    [string]$CssHost = "fonts.googleapis.com",
    [int[]]$Weights = @(400,500,300)
  )
  $ua = 'Mozilla/5.0 (Linux; Android 4.4; Nexus 5 Build/KRT16M) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/30.0.0.0 Mobile Safari/537.36'
  $headers = @{
    'User-Agent' = $ua
    'Accept'     = 'text/css,*/*;q=0.1'
    'Referer'    = ("https://{0}/" -f $CssHost)
  }
  foreach($w in $Weights){
    foreach($fmt in @("wght@$w","ital,wght@0,$w")){
      $famQuery = [uri]::EscapeDataString($Family) -replace '%20','+'
      $cssUrl   = "https://$CssHost/css2?family=$($famQuery):$fmt&display=swap"
      try {
        $css = Invoke-WebRequest -Headers $headers -UseBasicParsing -TimeoutSec 60 $cssUrl
        $urls = @()
        $urls += ([regex]'url\(([^)]+\.ttf)\)').Matches($css.Content)  | ForEach-Object { $_.Groups[1].Value.Trim("'`"") }
        $urls += ([regex]'url\(([^)]+\.otf)\)').Matches($css.Content)  | ForEach-Object { $_.Groups[1].Value.Trim("'`"") }
        $truetype = ([regex]'url\(([^)]+)\)\s*format\("truetype"\)').Matches($css.Content) | ForEach-Object { $_.Groups[1].Value.Trim("'`"") }
        $pick = @($truetype + $urls) | Select-Object -Unique
        if($pick.Count){ return $pick }
      } catch {
        Log ("CSS2 error ($CssHost/$Family/$fmt): $($_.Exception.Message)") "WARN"
      }
    }
  }
  @()
}

# Font Library API
function Get-FontFromFontlibraryAPI {
  param([string]$Family)
  $slug = ($Family.ToLower() -replace '[^a-z0-9]+','-')
  $api  = "https://fontlibrary.org/api/v1/font/$slug"
  try {
    $res = Invoke-WebRequest -UseBasicParsing -TimeoutSec 60 $api | ConvertFrom-Json
    $text = ($res | ConvertTo-Json -Depth 12)
    $urls = [regex]::Matches($text,'https?:\/\/[^"\\s]+?\.(ttf|otf)') | ForEach-Object { $_.Value }
    ($urls | Select-Object -Unique)
  } catch { Log ("FontLibrary API ($slug) error: $($_.Exception.Message)") "WARN"; @() }
}

# Google Web Fonts Developer API (v1)
$Global:GF_API_OK = $false
$Global:GF_Index  = @()
function Init-GFAPI {
  param([string]$Key)
  if($Global:GF_API_OK){ return $true }
  if([string]::IsNullOrWhiteSpace($Key)){ return $false }
  $url = "https://www.googleapis.com/webfonts/v1/webfonts?key=$Key&sort=popularity&prettyPrint=false&fields=items(family,category,files,variants,subsets)"
  try {
    $res = Invoke-WebRequest -UseBasicParsing -TimeoutSec 60 -Headers @{ 'Accept'='application/json' } $url
    $Global:GF_Index = ( $res.Content | ConvertFrom-Json ).items
    if($Global:GF_Index){ $Global:GF_API_OK = $true; Say "GF API: loaded $($Global:GF_Index.Count) families" "Green" }
    return $Global:GF_API_OK
  } catch {
    Log ("GF API init error: $($_.Exception.Message)") "WARN"
    return $false
  }
}
function Get-FontFromGFAPI {
  param([string]$Family)
  if(-not $Global:GF_API_OK -or -not $Global:GF_Index){ return @() }
  $item = $Global:GF_Index | Where-Object { $_.family -ieq $Family } | Select-Object -First 1
  if(-not $item){ return @() }
  $urls=@()
  if($item.files){
    $urls += $item.files.PSObject.Properties | ForEach-Object { $_.Value } |
             Where-Object { $_ -match '\.(ttf|otf)($|\?)' }
  }
  $urls | Select-Object -Unique
}

# Resolver tổng
function Resolve-FontTTF {
  param([string]$Family)
  $urls=@()
  $urls += Get-FontFromFontsourceAPI $Family
  if(-not $urls){ if(Init-GFAPI $GoogleApiKey){ $urls += Get-FontFromGFAPI $Family } }
  if(-not $urls){ $urls += Get-FontFromCSS2 -Family $Family -CssHost "fonts.googleapis.com" }
  if(-not $urls){ $urls += Get-FontFromCSS2 -Family $Family -CssHost "fonts.bunny.net" }
  if(-not $urls){ $urls += Get-FontFromFontlibraryAPI $Family }
  if(-not $urls){
    $folder = ($Family.ToLower() -replace '[^a-z0-9]','')
    $urls += Get-GitHubContentFiles -Owner "googlefonts" -Repo "fonts" -Path ("ofl/{0}" -f $folder) -Pattern '\.(ttf|otf)$'
  }
  $urls | Select-Object -Unique
}

# ===================== Core helpers =====================
function Download-File {
  param([string[]]$Urls,[string]$OutFile,[int]$Retry=3)
  $ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36'
  foreach($u in $Urls){
    for($i=1;$i -le $Retry;$i++){
      try {
        Log ("Download attempt {0}: {1}" -f $i,$u)
        try { Start-BitsTransfer -Source $u -Destination $OutFile -ErrorAction Stop }
        catch { Invoke-WebRequest -Uri $u -OutFile $OutFile -TimeoutSec 240 -Headers @{ 'User-Agent'=$ua } }
        if ((Test-Path $OutFile) -and ((Get-Item $OutFile).Length -gt 10kb)) { Log ("Download OK: {0}" -f $OutFile); return $true }
      } catch { Log ("Download error: {0}" -f $_.Exception.Message) "ERROR" }
      Start-Sleep -Seconds ([Math]::Min((Get-Random -Minimum 1 -Maximum 5)*$i,10))
    }
  }
  return $false
}

function Get-FontFace {
  param([string]$Path)
  try {
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    $pfc = New-Object System.Drawing.Text.PrivateFontCollection
    $pfc.AddFontFile($Path)
    if ($pfc.Families.Count -gt 0) { return $pfc.Families[0].Name }
  } catch { Log ("Get-FontFace error: {0}" -f $_.Exception.Message) "WARN" }
  return [IO.Path]::GetFileNameWithoutExtension($Path)
}

function Install-One {
  param(
    [string]$SrcPath,
    [string]$Fallback = "Custom"
  )
  try {
    $fi = Get-Item $SrcPath
    $dest = Join-Path $FontsDir $fi.Name
    if (Test-Path $dest) { Say ("Exists: {0}" -f $fi.Name) "Gray"; return $null }
    Copy-Item $fi.FullName $dest -Force
    $ext = $fi.Extension.ToLower()
    $type = if ($ext -eq ".ttf" -or $ext -eq ".ttc") { "TrueType" } else { "OpenType" }
    $face = if ($ext -ne ".ttc") { Get-FontFace $dest } else { $Fallback }
    $reg = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
    $key = ("{0} ({1})" -f $face,$type)
    try { Set-ItemProperty -Path $reg -Name $key -Value $fi.Name -ErrorAction Stop }
    catch { New-ItemProperty -Path $reg -Name $key -Value $fi.Name -PropertyType String -Force | Out-Null }
    Say ("Installed: {0} -> {1}" -f $face,$fi.Name) "Green"
    $owned = (Get-ItemProperty -Path $StateKey -Name "Owned" -ErrorAction SilentlyContinue).Owned
    if(-not $owned){ $owned=@() } elseif($owned -is [string]){ $owned=@($owned) }
    $owned = $owned + $fi.Name | Select-Object -Unique
    New-ItemProperty -Path $StateKey -Name "Owned" -Value $owned -PropertyType MultiString -Force | Out-Null
    return @{Face=$face;File=$fi.Name}
  } catch { Say ("Install error: {0}" -f $_.Exception.Message) "Red" "ERROR"; return $null }
}

function Uninstall-One { param([string]$File)
  try {
    $full = Join-Path $FontsDir $File
    $reg = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
    $props = (Get-ItemProperty $reg -ErrorAction SilentlyContinue).PSObject.Properties |
      Where-Object { $_.Value -and ($_.Value -ieq $File) }
    foreach($p in $props){ try { Remove-ItemProperty -Path $reg -Name $p.Name -ErrorAction SilentlyContinue } catch {} }
    if(Test-Path $full){ try { Remove-Item $full -Force -ErrorAction SilentlyContinue } catch {} }
    Say ("Uninstalled file: {0}" -f $File) "Yellow"
    $owned = (Get-ItemProperty -Path $StateKey -Name "Owned" -ErrorAction SilentlyContinue).Owned
    if($owned){
      if($owned -is [string]){ $owned=@($owned) }
      $owned = $owned | Where-Object { $_ -ne $File }
      New-ItemProperty -Path $StateKey -Name "Owned" -Value $owned -PropertyType MultiString -Force | Out-Null
    }
  } catch { Log ("Uninstall warn: {0}" -f $_.Exception.Message) "WARN" }
}

function FaceMap {
  $map=@{}; $reg="HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
  try { (Get-ItemProperty $reg -ErrorAction SilentlyContinue).PSObject.Properties |
      Where-Object { $_.Name -and $_.Name -notmatch '^PS' -and $_.Value } |
      ForEach-Object { $map[($_.Name -replace ' \(TrueType\)$','' -replace ' \(OpenType\)$','')] = $_.Value } } catch {}
  $map
}
function InvHash {
  try {
    $reg="HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
    $rows=@()
    (Get-ItemProperty $reg -ErrorAction SilentlyContinue).PSObject.Properties |
      Where-Object { $_.Name -and $_.Name -notmatch '^PS' -and $_.Value } |
      ForEach-Object {
        $f=Join-Path $FontsDir $_.Value; $s=0; if(Test-Path $f){$s=(Get-Item $f).Length}
        $rows+=("$($_.Name)|$($_.Value)|$s")
      }
    $bytes=[Text.Encoding]::UTF8.GetBytes((($rows|Sort-Object) -join "`n"))
    ([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($bytes)) -replace '-','')
  } catch { "NA" }
}
function FBHash {
  try {
    $bases=@("Segoe UI","Segoe UI Variable","Segoe UI Symbol","Segoe UI Emoji","Arial","Times New Roman","Courier New","Calibri","Cambria","Consolas","Microsoft Sans Serif","Tahoma","MS Shell Dlg","MS Shell Dlg 2","Cambria Math")
    $rows=@()
    foreach($root in @('HKLM','HKCU')){
      $sys=("{0}:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontLink\SystemLink" -f $root)
      $sub=("{0}:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -f $root)
      foreach($b in $bases){ $v=(Get-ItemProperty -Path $sys -Name $b -ErrorAction SilentlyContinue).$b; if($v){$rows+=("SYS[{0}]:{1}={2}" -f $root,$b,($v -join ';'))}}
      foreach($n in $bases){ $vv=(Get-ItemProperty -Path $sub -Name $n -ErrorAction SilentlyContinue).$n; if($vv){$rows+=("SUB[{0}]:{1}={2}" -f $root,$n,$vv)}}
    }
    $bytes=[Text.Encoding]::UTF8.GetBytes(($rows -join "`n"))
    ([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($bytes)) -replace '-','')
  } catch { "NA" }
}

function Prepend-Link { param([string]$Base,[string[]]$Pairs)
  foreach($root in @('HKLM','HKCU')){
    $key=("{0}:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontLink\SystemLink" -f $root)
    try {
      $cur=(Get-ItemProperty -Path $key -Name $Base -ErrorAction SilentlyContinue).$Base
      if (-not $cur){$cur=@()}
      if($cur -is [string]){ $cur=@($cur) }
      $new=($Pairs + $cur) | Select-Object -Unique
      New-ItemProperty -Path $key -Name $Base -Value $new -PropertyType MultiString -Force | Out-Null
      Log ("SystemLink [{0}] ({1}) <= {2}" -f $Base,$root,($Pairs -join ' | '))
    } catch { Say ("Prepend error {0}/{1}: {2}" -f $Base,$root,$_.Exception.Message) "Red" "ERROR" }
  }
}

function PickRandom { param([string[]]$Prefer,[hashtable]$Map,[switch]$Exact)
  $candidates=@()
  foreach($n in $Prefer){
    foreach($k in $Map.Keys){
      $ok = if($Exact){ $k -eq $n } else { ($k -eq $n) -or ($k -like ($n + "*")) }
      if($ok){
        $f=$Map[$k]
        if($f -and (Test-Path (Join-Path $FontsDir $f))){
          $candidates += ,@{Face=$k;Pair=("{0},{1}" -f $f,$k)}
        }
      }
    }
  }
  if($candidates.Count -gt 0){ return ($candidates | Get-Random) } else { $null }
}

# ---- Chromium helpers ----
function Is-ProcRunning { param([string]$Name) try { (Get-Process -Name $Name -ErrorAction SilentlyContinue) -ne $null } catch { $false } }
function Kill-Browsers { foreach($p in @("chrome","msedge")){ try { if(Is-ProcRunning $p){ Stop-Process -Name $p -Force -ErrorAction SilentlyContinue; Start-Sleep 1; Say ("Killed: {0}" -f $p) "Yellow" } } catch {} } }
function Patch-ChromiumFonts {
  param([string]$PrefsPath,[string]$Sans,[string]$Serif,[string]$Mono,[string]$Cursive="Comic Sans MS",[string]$Fantasy="Impact")
  if(!(Test-Path $PrefsPath)){ Log ("Chromium Prefs not found: {0}" -f $PrefsPath) "WARN"; return }
  try {
    $bak = "$PrefsPath.bak_{0}" -f (Get-Date -Format "yyyyMMddHHmmss")
    Copy-Item $PrefsPath $bak -Force -ErrorAction SilentlyContinue | Out-Null
    $json = Get-Content $PrefsPath -Raw | ConvertFrom-Json
    if(!$json.webkit){ $json | Add-Member -NotePropertyName webkit -NotePropertyValue @{webprefs=@{fonts=@{}}} -Force }
    if(!$json.webkit.webprefs){ $json.webkit.webprefs = @{fonts=@{}} }
    if(!$json.webkit.webprefs.fonts){ $json.webkit.webprefs.fonts = @{} }
    $fonts = $json.webkit.webprefs.fonts
    foreach($k in @("standard","serif","sansserif","fixed","cursive","fantasy")){
      if(!$fonts.$k){ $fonts.$k = @{} }
      $fonts.$k.Zyyy = switch($k){
        "standard" { $Serif } "serif" { $Serif } "sansserif" { $Sans } "fixed" { $Mono } "cursive" { $Cursive } "fantasy" { $Fantasy } }
    }
    ($json | ConvertTo-Json -Depth 20) | Set-Content -Encoding UTF8 $PrefsPath
    Say ("Patched Chromium Prefs: {0} (sans={1}, serif={2}, mono={3}, cursive={4}, fantasy={5})" -f $PrefsPath,$Sans,$Serif,$Mono,$Cursive,$Fantasy) "Green"
  } catch { Say ("Chromium patch error: {0}" -f $_.Exception.Message) "Red" "ERROR" }
}

# ---- Refresh-Fonts ----
function Refresh-Fonts {
  try {
    Stop-Service FontCache -Force -ErrorAction SilentlyContinue
    Start-Sleep 1
    Remove-Item "$env:LOCALAPPDATA\FontCache\*" -Force -ErrorAction SilentlyContinue
  } catch {}
  try { Start-Service FontCache -ErrorAction SilentlyContinue } catch {}
  try {
    Add-Type -Namespace Win32 -Name U -MemberDefinition '[DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h,uint m,IntPtr w,IntPtr l,uint f,uint t,out IntPtr r);'
    [void][Win32.U]::SendMessageTimeout([IntPtr]0xffff,0x1D,[IntPtr]0,[IntPtr]0,2,1000,[ref]([IntPtr]::Zero))
  } catch {}
}

# ===================== MAIN =====================
Clear-Host
Write-Host "==============================================================" -ForegroundColor Green
Write-Host ("  ADVANCED FONT FINGERPRINT ROTATOR v{0}" -f $Version) -ForegroundColor Yellow
Write-Host "==============================================================" -ForegroundColor Green
Log ("OS: {0}  PS: {1}" -f [Environment]::OSVersion.VersionString, $PSVersionTable.PSVersion)

$beforeInv = InvHash; $beforeFB = FBHash
Say ("Inventory Hash: {0}..." -f (Head32 $beforeInv)) "Cyan"
Say ("Fallback Hash : {0}..." -f (Head32 $beforeFB)) "Cyan"

for($round=1; $round -le $MaxRounds; $round++){
  Say ("--- ROUND {0} ---" -f $round) "White"

  if(-not $KeepGrowth){
    $owned = (Get-ItemProperty -Path $StateKey -Name "Owned" -ErrorAction SilentlyContinue).Owned
    if($owned -is [string]){ $owned=@($owned) }
    $ownedCount = if($owned){ $owned.Count } else { 0 }
    if($ownedCount -gt 0){
      $rmMax = [Math]::Min($UninstallMax, $ownedCount)
      $rmMin = [Math]::Min($UninstallMin, $rmMax)
      $rmCount = Get-Random -Minimum $rmMin -Maximum ($rmMax+1)
      if($rmCount -gt 0){
        $rmList = $owned | Get-Random -Count $rmCount
        Say ("Uninstalling {0} previously-installed fonts..." -f $rmList.Count) "Yellow"
        foreach($f in $rmList){ Uninstall-One $f }
      } else { Say ("Uninstalling 0 previously-installed fonts...") "Yellow" }
    } else { Say ("Uninstalling 0 previously-installed fonts...") "Yellow" }
  }

  # INSTALL từ API
  $target = Get-Random -Minimum $InstallMin -Maximum ($InstallMax+1)
  $familyBag=@(); foreach($cat in $FAMILIES.Keys){ foreach($fam in $FAMILIES[$cat]){ $familyBag += ,@{Cat=$cat;Fam=$fam} } }
  $familyPick = $familyBag | Get-Random -Count ([Math]::Min($target, $familyBag.Count))
  $installed=0

 # Unicode boosters
foreach($b in ($UNICODE_BOOST | Get-Random -Count ([Math]::Min(3,$UNICODE_BOOST.Count)))) {
  # Lấy các file từ GitHub theo thông tin trong $UNICODE_BOOST
  $urls = Get-GitHubContentFiles -Owner $b.Owner -Repo $b.Repo -Path $b.Path -Pattern $b.Pattern
  if ($urls -and $urls.Count) {
    $name = [IO.Path]::GetFileName(($urls[0] -split '\?')[0])  # Lấy tên file từ URL
    $out = Join-Path $TempDir $name  # Đường dẫn tạm cho font
    # Download file và cài đặt
    if (Download-File -Urls $urls -OutFile $out) {
      if (Install-One -SrcPath $out -Fallback $b.Name) {
        $installed++  # Tăng số lượng font đã cài đặt
      }
    }
  } else {
    # Nếu không tìm thấy file
    Say ("API could not resolve (boost): {0}/{1}/{2}" -f $b.Owner, $b.Repo, $b.Path) "Red" "ERROR"
  }
}

# Tiếp tục xử lý các font từ danh sách đã chọn
foreach($t in $familyPick) {
  $fam = $t.Fam  # Tên font gia đình
  $urls = Resolve-FontTTF $fam  # Lấy URL font gia đình
  if ($urls -and $urls.Count) {
    $fname = [IO.Path]::GetFileName((($urls[0] -split '\?')[0]))  # Lấy tên file
    if (-not $fname.EndsWith(".ttf") -and -not $fname.EndsWith(".otf")) {
      $fname = ($fam -replace '\s','') + ".ttf"  # Đảm bảo phần mở rộng là .ttf
    }
    $out = Join-Path $TempDir $fname  # Đường dẫn lưu font
    # Tải và cài đặt font
    if (Download-File -Urls $urls -OutFile $out) {
      if (Install-One -SrcPath $out -Fallback $fam) {
        $installed++  # Tăng số lượng font đã cài
      }
    } else {
      # Nếu tải xuống không thành công
      Say ("Download failed via API: {0}" -f $fam) "Red" "ERROR"
    }
  } else {
    # Nếu không tìm thấy font
    Say ("API could not resolve: {0}" -f $fam) "Red" "ERROR"
  }
}

# Bổ sung duplicate font nếu không đủ số lượng để thay đổi InventoryHash
if ($installed -lt [Math]::Max(3, [Math]::Floor($target/3))) {
  $owned = (Get-ItemProperty -Path $StateKey -Name "Owned" -ErrorAction SilentlyContinue).Owned
  if ($owned) {
    if ($owned -is [string]) { $owned = @($owned) }
    $dupCount = [Math]::Min(3, $owned.Count)  # Tạo ra tối đa 3 bản sao
    foreach ($f in ($owned | Get-Random -Count $dupCount)) {
      $src = Join-Path $FontsDir $f
      if (Test-Path $src) {
        $new = ([IO.Path]::GetFileNameWithoutExtension($f)) + ("-{0}.ttf" -f (Get-Random -Minimum 1000 -Maximum 9999))
        $dst = Join-Path $FontsDir $new
        try {
          Copy-Item $src $dst -Force
          $reg = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
          $face = Get-FontFace $dst
          $key = ("{0} (TrueType)" -f $face)
          New-ItemProperty -Path $reg -Name $key -Value $new -PropertyType String -Force | Out-Null
          $owned2 = (Get-ItemProperty -Path $StateKey -Name "Owned" -ErrorAction SilentlyContinue).Owned
          if (-not $owned2) { $owned2 = @() } elseif ($owned2 -is [string]) { $owned2 = @($owned2) }
          $owned2 = $owned2 + $new | Select-Object -Unique
          New-ItemProperty -Path $StateKey -Name "Owned" -Value $owned2 -PropertyType MultiString -Force | Out-Null
          Say ("Synthesized duplicate: {0}" -f $new) "Yellow"
        } catch {}
      }
    }
  }
}


  # RANDOMIZE fallbacks + substitutes
  $map = FaceMap
  $sans  = PickRandom -Prefer @("Inter","Open Sans","Noto Sans","Work Sans","Manrope","Poppins","DM Sans","Karla","Rubik","Heebo","Outfit","Sora","Plus Jakarta Sans","Nunito Sans","Mulish","Urbanist","Lato","Raleway","Montserrat") -Map $map
  $serif = PickRandom -Prefer @("Merriweather","Lora","Libre Baskerville","Playfair Display","Source Serif","Source Serif 4","Cardo","Crimson Pro","Cormorant Garamond","Old Standard TT","Domine","Spectral","EB Garamond","Gentium Book Plus","Literata","Tinos") -Map $map
  $mono  = PickRandom -Prefer @("JetBrains Mono","Source Code Pro","Inconsolata","Cousine","Anonymous Pro","IBM Plex Mono","Ubuntu Mono","Red Hat Mono","Consolas","Courier New") -Map $map
  $cursive = PickRandom -Prefer @("Comic Sans MS","Segoe Script","Gabriola","Lucida Handwriting") -Map $map
  $fantasy = PickRandom -Prefer @("Impact","Haettenschweiler","Showcard Gothic","Papyrus","Jokerman","Arial Black") -Map $map
  $sym1  = PickRandom -Prefer @("Noto Sans Math","Noto Sans Symbols 2") -Map $map
  $sym2  = PickRandom -Prefer @("Noto Music","Noto Sans Symbols 2","Noto Sans") -Map $map
  $emoji = PickRandom -Prefer @("Noto Color Emoji") -Map $map -Exact

  $bases = @("Segoe UI","Segoe UI Variable","Arial","Times New Roman","Courier New","Calibri","Cambria","Consolas","Microsoft Sans Serif","Tahoma","MS Shell Dlg","MS Shell Dlg 2") | Get-Random -Count 12
  $pairs=@()
  foreach($p in @($sans,$serif,$mono)){ if($p){ $pairs+=$p.Pair } }
  if($sym1){ $pairs = ,$sym1.Pair + $pairs }
  if($sym2){ $pairs += $sym2.Pair }
  foreach($b in $bases){
    if($pairs.Count -gt 0){
      $take = Get-Random -Minimum 2 -Maximum ([Math]::Min(6,$pairs.Count)+1)
      Prepend-Link -Base $b -Pairs ($pairs | Get-Random -Count $take)
    }
  }
  if($sym1){ Prepend-Link -Base "Segoe UI Symbol" -Pairs @($sym1.Pair); }
  if($emoji){ Prepend-Link -Base "Segoe UI Emoji"  -Pairs @($emoji.Pair); }
  foreach($root in @('HKLM','HKCU')){
    $sub=("{0}:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -f $root)
    if($sans){  New-ItemProperty -Path $sub -Name "Segoe UI" -Value $sans.Face -PropertyType String -Force | Out-Null
                New-ItemProperty -Path $sub -Name "Arial"    -Value $sans.Face -PropertyType String -Force | Out-Null }
    if($serif){ New-ItemProperty -Path $sub -Name "Times New Roman" -Value $serif.Face -PropertyType String -Force | Out-Null
                New-ItemProperty -Path $sub -Name "Cambria"        -Value $serif.Face -PropertyType String -Force | Out-Null }
    if($mono){  New-ItemProperty -Path $sub -Name "Courier New" -Value $mono.Face -PropertyType String -Force | Out-Null
                New-ItemProperty -Path $sub -Name "Consolas"    -Value $mono.Face -PropertyType String -Force | Out-Null }
    if($sym1){  New-ItemProperty -Path $sub -Name "Segoe UI Symbol" -Value $sym1.Face -PropertyType String -Force | Out-Null
                New-ItemProperty -Path $sub -Name "Cambria Math"    -Value $sym1.Face -PropertyType String -Force | Out-Null }
    if($emoji){ New-ItemProperty -Path $sub -Name "Segoe UI Emoji" -Value $emoji.Face -PropertyType String -Force | Out-Null }
    if($cursive){ New-ItemProperty -Path $sub -Name "Comic Sans MS" -Value $cursive.Face -PropertyType String -Force | Out-Null }
    if($fantasy){ New-ItemProperty -Path $sub -Name "Impact" -Value $fantasy.Face -PropertyType String -Force | Out-Null }
  }

  Refresh-Fonts

  # Patch Chromium
  if(-not $NoForceClose){ Kill-Browsers }
  if(-not $NoChromiumFonts){
    $sf = if($sans){$sans.Face}else{"Arial"}
    $rf = if($serif){$serif.Face}else{"Times New Roman"}
    $mf = if($mono){$mono.Face}else{"Consolas"}
    $cf = if($cursive){$cursive.Face}else{"Comic Sans MS"}
    $ff = if($fantasy){$fantasy.Face}else{"Impact"}
    $chrome = Join-Path $env:LOCALAPPDATA ("Google\Chrome/User Data/{0}/Preferences" -f $ChromeProfile)
    $edge   = Join-Path $env:LOCALAPPDATA ("Microsoft/Edge/User Data/{0}/Preferences" -f $EdgeProfile)
    Patch-ChromiumFonts -PrefsPath $chrome -Sans $sf -Serif $rf -Mono $mf -Cursive $cf -Fantasy $ff
    Patch-ChromiumFonts -PrefsPath $edge   -Sans $sf -Serif $rf -Mono $mf -Cursive $cf -Fantasy $ff
  } else { Say "NoChromiumFonts: SKIP patch Chrome/Edge." "Yellow" }

  # Check hashes
  $newInv = InvHash; $newFB = FBHash
  Say ("Round {0} Inventory:  {1} -> {2}" -f $round,(Head32 $beforeInv),(Head32 $newInv)) "White"
  Say ("Round {0} Fallback :  {1} -> {2}" -f $round,(Head32 $beforeFB),(Head32 $newFB)) "White"
  $invChanged = ($newInv -ne $beforeInv)
  $fbChanged  = ($newFB -ne $beforeFB)
  if($invChanged -and $fbChanged){ Say ("SUCCESS: Both hashes changed in round {0}" -f $round) "Green"; break }
  else { Say ("Hashes not both changed (Inv={0}, FB={1}) -> retry" -f ($invChanged),($fbChanged)) "Yellow"; $beforeInv=$newInv; $beforeFB=$newFB }
}

# --- Final
$finalInv = InvHash; $finalFB = FBHash
Say "`n--- FINAL HASHES ---" "Cyan"
Say ("Inventory:  {0}" -f $finalInv) "White"
Say ("Fallback :  {0}" -f $finalFB) "White"
Log ("Run finished. v{0}" -f $Version)
