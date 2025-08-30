<# ===================================================================
  ADVANCED FONT FINGERPRINT ROTATOR v3.13-API-ONLY
  - Chỉ tải qua API: Google Fonts CSS2, Fontsource Data API, GitHub Content API
  - Không dùng link phát hành (release) / hard link
  - Mỗi lần chạy: đổi Inventory (Font Metrics) + Unicode Glyphs
  - Patch default fonts Chrome/Edge (tùy chọn)
  Log: %USERPROFILE%\Downloads\log.txt
=================================================================== #>

param(
  [int]$InstallMin   = 12,
  [int]$InstallMax   = 18,
  [int]$UninstallMin = 6,
  [int]$UninstallMax = 10,
  [switch]$KeepGrowth = $true,     # Mặc định KHÔNG gỡ font đã cài
  [switch]$NoChromiumFonts = $false,
  [switch]$NoForceClose    = $false,
  [string]$ChromeProfile = "Default",
  [string]$EdgeProfile   = "Default",
  [int]$MaxRounds = 3
)

# ---- Admin check ----
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
   ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
  Write-Host "ERROR: Run PowerShell as Administrator!" -ForegroundColor Red
  Read-Host "Press Enter to exit"; exit 1
}

$Version = "3.13-API-ONLY"
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

# ---- Pools
$FAMILIES = @{
  Sans  = @("Inter","Open Sans","Roboto","Noto Sans","Work Sans","Manrope","Poppins",
            "DM Sans","Karla","Rubik","Cabin","Asap","Lexend","Heebo","Outfit",
            "Sora","Plus Jakarta Sans","Nunito Sans","Mulish","Urbanist","Montserrat",
            "Raleway","Lato","Source Sans 3","PT Sans","Fira Sans","IBM Plex Sans")
  Serif = @("Merriweather","Lora","Libre Baskerville","Playfair Display","Source Serif 4",
            "Cardo","Crimson Pro","Cormorant Garamond","Old Standard TT","Domine",
            "Spectral","EB Garamond","Gentium Book Plus","Literata","Tinos")
  Mono  = @("Source Code Pro","JetBrains Mono","Inconsolata","Cousine","Anonymous Pro",
            "Iosevka","Fira Code","IBM Plex Mono","Ubuntu Mono","Red Hat Mono")
}

# Unicode boosters – lấy qua GitHub Content API, KHÔNG raw/release
$UNICODE_BOOST = @(
  @{ Owner="googlefonts"; Repo="noto-emoji"; Path="fonts"; Pattern="^NotoColorEmoji\.ttf$";   Name="Noto Color Emoji" },
  @{ Owner="googlefonts"; Repo="noto-fonts"; Path="hinted/ttf/NotoSansSymbols2"; Pattern="Regular\.ttf$"; Name="Noto Sans Symbols 2" },
  @{ Owner="googlefonts"; Repo="noto-fonts"; Path="hinted/ttf/NotoSansMath";     Pattern="Regular\.ttf$"; Name="Noto Sans Math" },
  @{ Owner="googlefonts"; Repo="noto-fonts"; Path="hinted/ttf/NotoMusic";        Pattern="Regular\.ttf$"; Name="Noto Music" }
)

# ===================== API RESOLVERS =====================

# Helper: JSDelivr Data API – liệt kê file của @fontsource/<pkg>
function Get-FontFromFontsourceAPI {
  param([string]$Family)
  $pkg = ( $Family.ToLower() -replace '[\s_]+','-' )
  # Một số alias phổ biến
  $map = @{
    "plus-jakarta-sans"="plus-jakarta-sans"; "source-serif-4"="source-serif-4"; "old-standard-tt"="old-standard-tt"
    "eb-garamond"="eb-garamond"; "ibm-plex-sans"="ibm-plex-sans"; "ibm-plex-mono"="ibm-plex-mono"
    "pt-sans"="pt-sans"; "fira-sans"="fira-sans"; "source-sans-3"="source-sans-3"; "red-hat-mono"="red-hat-mono"
    "playfair-display"="playfair-display"; "gentium-book-plus"="gentium-book-plus"; "jetbrains-mono"="jetbrains-mono"
  }
  if($map.ContainsKey($pkg)){ $pkg = $map[$pkg] }

  $api = "https://data.jsdelivr.com/v1/package/npm/@fontsource/$pkg"
  try {
    $json = Invoke-WebRequest -UseBasicParsing -TimeoutSec 60 -Headers @{ 'User-Agent'='FontRotator/3.13' } $api | ConvertFrom-Json
  } catch {
    Log ("Fontsource Data API error ($Family/$pkg): $($_.Exception.Message)") "WARN"; return @()
  }

  $all=@()
  function Walk($node, $prefix){
    foreach($f in $node.files){
      $p = if($prefix){ "$prefix/$($f.name)" } else { $f.name }
      if($f.type -eq "file"){ $script:all += $p }
      elseif($f.type -eq "directory"){ Walk $f $p }
    }
  }
  Walk $json ""

  # Ưu tiên latin 400 normal, sau đó 400 normal bất kỳ
  $choice = $all | Where-Object { $_ -match '^files/.+-latin-400-normal\.ttf$' } | Select-Object -First 1
  if(-not $choice){ $choice = $all | Where-Object { $_ -match '^files/.+-400-normal\.ttf$' } | Select-Object -First 1 }
  if(-not $choice){ $choice = $all | Where-Object { $_ -match '^files/.+\.ttf$' } | Select-Object -First 1 }
  if($choice){
    ,@("https://cdn.jsdelivr.net/npm/@fontsource/$pkg/$choice",
       "https://unpkg.com/@fontsource/$pkg/$choice")
  } else { @() }
}

# Google Fonts CSS2 (ép trả TTF bằng UA Android 4.4)
function Get-FontFromGoogleCSS {
  param([string]$Family,[int[]]$Weights=@(400,500,300))
  $ua = 'Mozilla/5.0 (Linux; Android 4.4; Nexus 5 Build/KRT16M) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/30.0.0.0 Mobile Safari/537.36'
  $headers = @{ 'User-Agent'=$ua; 'Accept'='text/css,*/*;q=0.1'; 'Referer'='https://fonts.googleapis.com/' }
  foreach($w in $Weights){
    foreach($fmt in @("wght@$w","ital,wght@0,$w")){
      $famQuery = [uri]::EscapeDataString($Family) -replace '%20','+'
      $cssUrl = "https://fonts.googleapis.com/css2?family=$($famQuery):$fmt&display=swap"
      try {
        $css = Invoke-WebRequest -Headers $headers -UseBasicParsing -TimeoutSec 60 $cssUrl
        $ttf = ([regex]'url\(([^)]+\.ttf)\)').Matches($css.Content) | ForEach-Object { $_.Groups[1].Value.Trim("'`"") }
        $uniq = $ttf | Select-Object -Unique
        if($uniq -and $uniq.Count){ return $uniq }
      } catch { Log ("GF CSS2 error ($Family/$fmt): $($_.Exception.Message)") "WARN" }
    }
  }
  @()
}

# GitHub Content API (lấy download_url)
function Get-GitHubContentFiles {
  param([string]$Owner,[string]$Repo,[string]$Path,[string]$Pattern='\.ttf$')
  $api = "https://api.github.com/repos/$Owner/$Repo/contents/$Path"
  try {
    $items = Invoke-WebRequest -UseBasicParsing -TimeoutSec 60 -Headers @{ 'User-Agent'='FontRotator/3.13' } $api | ConvertFrom-Json
    $files = $items | Where-Object { $_.type -eq 'file' -and $_.name -match $Pattern }
    $urls  = $files | Select-Object -ExpandProperty download_url
    $urls | Select-Object -Unique
  } catch { Log ("GitHub API error ($Owner/$Repo/$Path): $($_.Exception.Message)") "WARN"; @() }
}

# Kết hợp: trả list URL TTF/OTF (ưu tiên GF CSS2 → Fontsource API → GitHub GF ofl)
function Resolve-FontTTF {
  param([string]$Family)
  $urls=@()
  $urls += Get-FontFromGoogleCSS $Family
  if(-not $urls){ $urls += Get-FontFromFontsourceAPI $Family }
  if(-not $urls){
    $folder = ($Family.ToLower() -replace '[^a-z0-9]','')
    $urls += Get-GitHubContentFiles -Owner "googlefonts" -Repo "fonts" -Path ("ofl/{0}" -f $folder) -Pattern '\.(ttf|otf)$'
  }
  $urls | Select-Object -Unique
}

# ===================== Core helpers =====================
function Download-File {
  param([string[]]$Urls,[string]$OutFile,[int]$Retry=2)
  $ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36'
  foreach($u in $Urls){
    for($i=1;$i -le $Retry;$i++){
      try {
        Log ("Download attempt {0}: {1}" -f $i,$u)
        if ($PSVersionTable.PSVersion.Major -ge 7) {
          Invoke-WebRequest -Uri $u -OutFile $OutFile -TimeoutSec 240 -Headers @{ 'User-Agent'=$ua }
        } else {
          try { Start-BitsTransfer -Source $u -Destination $OutFile -ErrorAction Stop }
          catch { Invoke-WebRequest -Uri $u -OutFile $OutFile -Headers @{ 'User-Agent'=$ua } }
        }
        if ((Test-Path $OutFile) -and ((Get-Item $OutFile).Length -gt 1000)) { Log ("Download OK: {0}" -f $OutFile); return $true }
      } catch { Log ("Download error: {0}" -f $_.Exception.Message) "ERROR" }
      Start-Sleep -Seconds ([Math]::Min((Get-Random -Minimum 1 -Maximum 5)*$i,8))
    }
  }
  return $false
}

function Get-FontFace { param([string]$Path)
  try {
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    $pfc = New-Object System.Drawing.Text.PrivateFontCollection
    $pfc.AddFontFile($Path)
    if ($pfc.Families.Count -gt 0) { return $pfc.Families[0].Name }
  } catch { Log ("Get-FontFace error: {0}" -f $_.Exception.Message) "WARN" }
  return [IO.Path]::GetFileNameWithoutExtension($Path)
}

function Install-One { param([string]$SrcPath,[string]$Fallback="Custom")
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
    if(-not $owned){ $owned=@() }
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
    if($owned){ $owned = $owned | Where-Object { $_ -ne $File }; New-ItemProperty -Path $StateKey -Name "Owned" -Value $owned -PropertyType MultiString -Force | Out-Null }
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
      $new=($Pairs + $cur) | Select-Object -Unique
      New-ItemProperty -Path $key -Name $Base -Value $new -PropertyType MultiString -Force | Out-Null
      Log ("SystemLink [{0}] ({1}) <= {2}" -f $Base,$root,($Pairs -join ' | '))
    } catch { Say ("Prepend error {0}/{1}: {2}" -f $Base,$root,$_.Exception.Message) "Red" "ERROR" }
  }
}

# --- PickRandom cho generic ---
function PickRandom { param([string[]]$Prefer,[hashtable]$Map,[switch]$Exact)
  $candidates=@()
  foreach($n in $Prefer){
    foreach($k in $Map.Keys){
      $ok = if($Exact){ $k -eq $n } else { ($k -eq $n) -or ($k -like ($n + "*")) }
      if($ok){
        $f=$Map[$k]
        if($f -and (Test-Path (Join-Path $env:SystemRoot\Fonts $f))){
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

  # 0) Uninstall (skip nếu -KeepGrowth)
  if(-not $KeepGrowth){
    $owned = (Get-ItemProperty -Path $StateKey -Name "Owned" -ErrorAction SilentlyContinue).Owned
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

  # 1) INSTALL fresh từ API: Unicode boosters + families
  $target = Get-Random -Minimum $InstallMin -Maximum ($InstallMax+1)
  $familyBag=@(); foreach($cat in $FAMILIES.Keys){ foreach($fam in $FAMILIES[$cat]){ $familyBag += ,@{Cat=$cat;Fam=$fam} } }
  $familyPick = $familyBag | Get-Random -Count ([Math]::Min($target, $familyBag.Count))
  $installed=0

  # Unicode boosters via GitHub Content API
  foreach($b in ($UNICODE_BOOST | Get-Random -Count ([Math]::Min(3,$UNICODE_BOOST.Count)))){
    $urls = Get-GitHubContentFiles -Owner $b.Owner -Repo $b.Repo -Path $b.Path -Pattern $b.Pattern
    if($urls -and $urls.Count){
      $name = [IO.Path]::GetFileName(($urls[0] -split '\?')[0])
      $out = Join-Path $TempDir $name
      if(Download-File -Urls $urls -OutFile $out){ if(Install-One -SrcPath $out -Fallback $b.Name){ $installed++ } }
    } else { Say ("API could not resolve (boost): {0}/{1}/{2}" -f $b.Owner,$b.Repo,$b.Path) "Red" "ERROR" }
  }

  foreach($t in $familyPick){
    $fam = $t.Fam
    $urls = Resolve-FontTTF $fam
    if($urls -and $urls.Count){
      $fname = [IO.Path]::GetFileName((($urls[0] -split '\?')[0]))
      if(-not $fname.EndsWith(".ttf") -and -not $fname.EndsWith(".otf")){ $fname = ($fam -replace '\s','') + ".ttf" }
      $out = Join-Path $TempDir $fname
      if(Download-File -Urls $urls -OutFile $out){ if(Install-One -SrcPath $out -Fallback $fam){ $installed++ } }
      else { Say ("Download failed via API: {0}" -f $fam) "Red" "ERROR" }
    } else { Say ("API could not resolve: {0}" -f $fam) "Red" "ERROR" }
  }

  # 1b) Synth duplicate (tùy mạng) – không tải, chỉ nhân bản để đảm bảo Inventory đổi
  if($installed -lt [Math]::Max(3,[Math]::Floor($target/3))){
    $owned = (Get-ItemProperty -Path $StateKey -Name "Owned" -ErrorAction SilentlyContinue).Owned
    if($owned -and $owned.Count -gt 0){
      $dupCount = [Math]::Min(3, $owned.Count)
      foreach($f in ($owned | Get-Random -Count $dupCount)){
        $src = Join-Path $FontsDir $f
        if(Test-Path $src){
          $new = ([IO.Path]::GetFileNameWithoutExtension($f)) + ("-{0}.ttf" -f (Get-Random -Minimum 1000 -Maximum 9999))
          $dst = Join-Path $FontsDir $new
          try {
            Copy-Item $src $dst -Force
            $reg="HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
            $face = Get-FontFace $dst
            $key = ("{0} (TrueType)" -f $face)
            New-ItemProperty -Path $reg -Name $key -Value $new -PropertyType String -Force | Out-Null
            $owned2 = (Get-ItemProperty -Path $StateKey -Name "Owned" -ErrorAction SilentlyContinue).Owned
            if(-not $owned2){ $owned2=@() }; $owned2 = $owned2 + $new | Select-Object -Unique
            New-ItemProperty -Path $StateKey -Name "Owned" -Value $owned2 -PropertyType MultiString -Force | Out-Null
            Say ("Synthesized duplicate: {0}" -f $new) "Yellow"
          } catch {}
        }
      }
    }
  }

  # 2) RANDOMIZE fallbacks + substitutes (kèm cursive/fantasy)
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
  if($sans){  New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -Name "Segoe UI" -Value $sans.Face -PropertyType String -Force | Out-Null
              New-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -Name "Segoe UI" -Value $sans.Face -PropertyType String -Force | Out-Null
              New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -Name "Arial" -Value $sans.Face -PropertyType String -Force | Out-Null
              New-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -Name "Arial" -Value $sans.Face -PropertyType String -Force | Out-Null }
  if($serif){ Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -Name "Times New Roman" -Value $serif.Face -Force
              Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -Name "Times New Roman" -Value $serif.Face -Force
              New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -Name "Cambria" -Value $serif.Face -PropertyType String -Force | Out-Null
              New-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -Name "Cambria" -Value $serif.Face -PropertyType String -Force | Out-Null }
  if($mono){  Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -Name "Courier New" -Value $mono.Face -Force
              Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -Name "Courier New" -Value $mono.Face -Force
              New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -Name "Consolas" -Value $mono.Face -PropertyType String -Force | Out-Null
              New-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -Name "Consolas" -Value $mono.Face -PropertyType String -Force | Out-Null }
  if($sym1){  Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -Name "Segoe UI Symbol" -Value $sym1.Face -Force
              Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -Name "Segoe UI Symbol" -Value $sym1.Face -Force
              Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -Name "Cambria Math" -Value $sym1.Face -Force
              Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -Name "Cambria Math" -Value $sym1.Face -Force }
  if($emoji){ Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -Name "Segoe UI Emoji" -Value $emoji.Face -Force
              Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -Name "Segoe UI Emoji" -Value $emoji.Face -Force }
  if($cursive){ Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -Name "Comic Sans MS" -Value $cursive.Face -Force
                Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -Name "Comic Sans MS" -Value $cursive.Face -Force }
  if($fantasy){ Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -Name "Impact" -Value $fantasy.Face -Force
                Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -Name "Impact" -Value $fantasy.Face -Force }
  Refresh-Fonts

  # 3) Patch Chromium
  if(-not $NoForceClose){ Kill-Browsers }
  if(-not $NoChromiumFonts){
    $sf = if($sans){$sans.Face}else{"Arial"}
    $rf = if($serif){$serif.Face}else{"Times New Roman"}
    $mf = if($mono){$mono.Face}else{"Consolas"}
    $cf = if($cursive){$cursive.Face}else{"Comic Sans MS"}
    $ff = if($fantasy){$fantasy.Face}else{"Impact"}
    $chrome = Join-Path $env:LOCALAPPDATA ("Google\Chrome\User Data\{0}\Preferences" -f $ChromeProfile)
    $edge   = Join-Path $env:LOCALAPPDATA ("Microsoft\Edge\User Data\{0}\Preferences" -f $EdgeProfile)
    Patch-ChromiumFonts -PrefsPath $chrome -Sans $sf -Serif $rf -Mono $mf -Cursive $cf -Fantasy $ff
    Patch-ChromiumFonts -PrefsPath $edge   -Sans $sf -Serif $rf -Mono $mf -Cursive $cf -Fantasy $ff
  } else { Say "NoChromiumFonts: SKIP patch Chrome/Edge." "Yellow" }

  # 4) Check hashes
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
