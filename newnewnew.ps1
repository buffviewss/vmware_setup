<# ===================================================================
  ADVANCED FONT FINGERPRINT ROTATOR v3.11-API-RAND
  Mục tiêu: mỗi lần chạy đổi được cả Inventory (Font Metrics) & Unicode Glyphs.
  - Gỡ 1 phần font do script cài (không đụng font hệ thống)
  - Cài mới nhiều font qua API (Fontsource -> GF CSS2 -> GitHub)
  - Random SystemLink/Substitutes + đổi default fonts của Chrome/Edge
  Log: %USERPROFILE%\Downloads\log.txt
=================================================================== #>

param(
  [int]$InstallMin   = 12,
  [int]$InstallMax   = 18,
  [int]$UninstallMin = 6,
  [int]$UninstallMax = 10,
  [switch]$KeepGrowth = $false,
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

$Version = "3.11-API-RAND"
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

# ---- Family pools (đã bỏ 'Georgia Pro')
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

# ---- Unicode boosters (ổn định)
$UNICODE_BOOST = @(
  @{ Name="Noto Color Emoji"; Urls=@(
     "https://raw.githubusercontent.com/googlefonts/noto-emoji/main/fonts/NotoColorEmoji.ttf",
     "https://cdn.jsdelivr.net/gh/googlefonts/noto-emoji@main/fonts/NotoColorEmoji.ttf"
  )},
  @{ Name="Noto Sans Symbols 2"; Urls=@(
     "https://raw.githubusercontent.com/googlefonts/noto-fonts/main/hinted/ttf/NotoSansSymbols2/NotoSansSymbols2-Regular.ttf",
     "https://cdn.jsdelivr.net/gh/googlefonts/noto-fonts@main/hinted/ttf/NotoSansSymbols2/NotoSansSymbols2-Regular.ttf"
  )},
  @{ Name="Noto Sans Math"; Urls=@(
     "https://raw.githubusercontent.com/googlefonts/noto-fonts/main/hinted/ttf/NotoSansMath/NotoSansMath-Regular.ttf",
     "https://cdn.jsdelivr.net/gh/googlefonts/noto-fonts@main/hinted/ttf/NotoSansMath/NotoSansMath-Regular.ttf"
  )},
  @{ Name="Noto Music"; Urls=@(
     "https://raw.githubusercontent.com/googlefonts/noto-fonts/main/hinted/ttf/NotoMusic/NotoMusic-Regular.ttf",
     "https://cdn.jsdelivr.net/gh/googlefonts/noto-fonts@main/hinted/ttf/NotoMusic/NotoMusic-Regular.ttf"
  )}
)

# ===================== RESOLVERS (API) =====================

# Map family -> Fontsource package slug nếu khác thường
$FontsourceMap = @{
  "Plus Jakarta Sans" = "plus-jakarta-sans"
  "Source Serif 4"    = "source-serif-4"
  "Old Standard TT"   = "old-standard-tt"
  "EB Garamond"       = "eb-garamond"
  "IBM Plex Sans"     = "ibm-plex-sans"
  "IBM Plex Mono"     = "ibm-plex-mono"
  "PT Sans"           = "pt-sans"
  "Fira Sans"         = "fira-sans"
  "Source Sans 3"     = "source-sans-3"
  "Red Hat Mono"      = "red-hat-mono"
  "Playfair Display"  = "playfair-display"
  "Gentium Book Plus" = "gentium-book-plus"
  "JetBrains Mono"    = "jetbrains-mono"
}

# Map family -> thư mục OFL của Google/fonts (nếu đặc biệt)
$GFNameMap = @{
  "Plus Jakarta Sans" = "plusjakartasans"
  "Source Serif 4"    = "sourceserif4"
  "Old Standard TT"   = "oldstandardtt"
  "EB Garamond"       = "ebgaramond"
  "IBM Plex Sans"     = "ibmplexsans"
  "IBM Plex Mono"     = "ibmplexmono"
  "Source Sans 3"     = "sourcesans3"
  "PT Sans"           = "ptsans"
  "Red Hat Mono"      = "redhatmono"
  "Playfair Display"  = "playfairdisplay"
  "Gentium Book Plus" = "gentiumbookplus"
  "JetBrains Mono"    = "jetbrainsmono"
}

function To-PackageName { param([string]$family)
  if($FontsourceMap.ContainsKey($family)){ return $FontsourceMap[$family] }
  return ($family.ToLower() -replace '[\s_]+','-')
}
function To-GFFolder { param([string]$family)
  if($GFNameMap.ContainsKey($family)){ return $GFNameMap[$family] }
  return ($family.ToLower() -replace '[^a-z0-9]','') # bỏ dấu/cách
}

# 1) Fontsource direct (latest) -> rơi về API nếu cần
function Get-FontFromFontsource {
  param([string]$Family)
  $pkg = To-PackageName $Family
  $file = "$pkg-latin-400-normal.ttf"
  $urls=@(
    "https://cdn.jsdelivr.net/npm/@fontsource/$pkg/files/$file",
    "https://unpkg.com/@fontsource/$pkg/files/$file"
  )
  # thử nhanh direct
  try {
    $test = Invoke-WebRequest -Method Head -TimeoutSec 20 -UseBasicParsing -Uri $urls[0] -ErrorAction Stop
    if($test.StatusCode -ge 200 -and $test.StatusCode -lt 400){ return ,$urls }
  } catch {}

  # rơi về API của jsDelivr để lấy version & file bất kỳ .ttf
  try {
    $meta = Invoke-WebRequest -UseBasicParsing -TimeoutSec 60 -Headers @{ 'User-Agent'='FontRotator/3.11' } "https://data.jsdelivr.com/v1/package/npm/@fontsource/$pkg" | ConvertFrom-Json
    $ver  = $meta.versions[0]
    $files = (Invoke-WebRequest -UseBasicParsing -TimeoutSec 60 -Headers @{ 'User-Agent'='FontRotator/3.11' } "https://data.jsdelivr.com/v1/package/npm/@fontsource/$pkg@${ver}") | ConvertFrom-Json
    $all = $files.files | Where-Object { $_ -match '\.ttf$' }
    $pick = $all | Where-Object { $_ -match 'latin.*400.*normal\.ttf$' } | Select-Object -First 1
    if(-not $pick){ $pick = $all | Select-Object -First 1 }
    if($pick){
      return ,@(
        "https://cdn.jsdelivr.net/npm/@fontsource/$pkg@${ver}/$pick",
        "https://unpkg.com/@fontsource/$pkg@${ver}/$pick"
      )
    }
  } catch { Log ("Fontsource API error ($Family): $($_.Exception.Message)") "WARN" }
  @()
}

# 2) Google Fonts CSS2 -> lấy TTF từ gstatic (UA Android 4.4)
function Get-FontFromGoogleCSS {
  param([string]$Family,[int[]]$Weights=@(400,500,300))
  $ua = 'Mozilla/5.0 (Linux; Android 4.4; Nexus 5 Build/KRT16M) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/30.0.0.0 Mobile Safari/537.36'
  $headers = @{ 'User-Agent'=$ua; 'Accept'='text/css,*/*;q=0.1'; 'Referer'='https://fonts.googleapis.com/' }
  foreach($w in $Weights){
    $famQuery = [uri]::EscapeDataString($Family) -replace '%20','+'
    $cssUrl = "https://fonts.googleapis.com/css2?family=$famQuery:wght@$w&display=swap"
    try {
      $css = Invoke-WebRequest -Headers $headers -UseBasicParsing -TimeoutSec 60 $cssUrl
      $ttf = ([regex]'url\(([^)]+\.ttf)\)').Matches($css.Content) | ForEach-Object { $_.Groups[1].Value.Trim("'`"") }
      $uniq = $ttf | Select-Object -Unique
      if($uniq -and $uniq.Count){ return $uniq }
    } catch { Log ("GF CSS2 error ($Family/$w): $($_.Exception.Message)") "WARN" }
  }
  @()
}

# 3) GitHub google/fonts – đúng thư mục OFL
function Get-FontFromGitHubGF {
  param([string]$Family)
  $folder = To-GFFolder $Family
  $api = "https://api.github.com/repos/google/fonts/contents/ofl/$folder"
  try {
    $list = Invoke-WebRequest -UseBasicParsing -TimeoutSec 60 -Headers @{ 'User-Agent'='FontRotator/3.11' } $api | ConvertFrom-Json
    $ttf = $list | Where-Object { $_.type -eq 'file' -and $_.name -match '\.(ttf|otf)$' } | Select-Object -ExpandProperty name
    $pick = ($ttf | Where-Object { $_ -match 'wght' } | Select-Object -First 1)
    if(-not $pick){ $pick = $ttf | Select-Object -First 1 }
    if($pick){
      return ,@("https://raw.githubusercontent.com/google/fonts/main/ofl/$folder/$pick")
    }
  } catch { Log ("GitHub GF API error ($Family): $($_.Exception.Message)") "WARN" }
  @()
}

function Resolve-FontTTF { param([string]$Family)
  # Thứ tự ưu tiên: Fontsource direct -> Fontsource API -> GF CSS2 -> GitHub GF
  $urls=@()
  $urls += Get-FontFromFontsource $Family
  if(-not $urls -or $urls.Count -lt 2){ $urls += Get-FontFromGoogleCSS $Family }
  if(-not $urls){ $urls += Get-FontFromGitHubGF $Family }
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
    # mark ownership
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
function CurFonts {
  try { $reg="HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
    (Get-ItemProperty $reg -ErrorAction SilentlyContinue).PSObject.Properties |
      Where-Object { $_.Name -and $_.Name -notmatch '^PS' -and $_.Value } |
      ForEach-Object { $_.Name -replace ' \(TrueType\)$','' -replace ' \(OpenType\)$','' } | Sort-Object -Unique } catch { @() }
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
function Set-Sub { param([string]$From,[string]$To)
  foreach($root in @('HKLM','HKCU')){
    $key=("{0}:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -f $root)
    try {
      try { Set-ItemProperty -Path $key -Name $From -Value $To -ErrorAction Stop }
      catch { New-ItemProperty -Path $key -Name $From -Value $To -PropertyType String -Force | Out-Null }
      Say ("Substitute({0}): {1} -> {2}" -f $root,$From,$To) "Yellow"
    } catch { Say ("Substitute error {0}->{1}/{2}: {3}" -f $From,$To,$root,$_.Exception.Message) "Red" "ERROR" }
  }
}
function Refresh-Fonts {
  try { Stop-Service FontCache -Force -ErrorAction SilentlyContinue; Start-Sleep 1; Remove-Item "$env:LOCALAPPDATA\FontCache\*" -Force -ErrorAction SilentlyContinue } catch {}
  try { Start-Service FontCache -ErrorAction SilentlyContinue } catch {}
  try {
    Add-Type -Namespace Win32 -Name U -MemberDefinition '[DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h,uint m,IntPtr w,IntPtr l,uint f,uint t,out IntPtr r);'
    [void][Win32.U]::SendMessageTimeout([IntPtr]0xffff,0x1D,[IntPtr]0,[IntPtr]0,2,1000,[ref]([IntPtr]::Zero))
  } catch {}
}

# --- PickRandom: chọn ngẫu nhiên trong pool hợp lệ (thay vì PickFirst)
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

  # 0) optional uninstall a portion of owned fonts
  if(-not $KeepGrowth){
    $owned = (Get-ItemProperty -Path $StateKey -Name "Owned" -ErrorAction SilentlyContinue).Owned
    if($owned -and $owned.Count -gt 0){
      $rmCount = Get-Random -Minimum $UninstallMin -Maximum ([Math]::Min($UninstallMax, $owned.Count)+1)
      $rmList = $owned | Get-Random -Count $rmCount
      Say ("Uninstalling {0} previously-installed fonts..." -f $rmList.Count) "Yellow"
      Refresh-Fonts
      foreach($f in $rmList){ Uninstall-One $f }
      Refresh-Fonts
    }
  }

  # 1) INSTALL fresh fonts: boosters + families via API
  $target = Get-Random -Minimum $InstallMin -Maximum ($InstallMax+1)
  $familyBag=@(); foreach($cat in $FAMILIES.Keys){ foreach($fam in $FAMILIES[$cat]){ $familyBag += ,@{Cat=$cat;Fam=$fam} } }
  $familyPick = $familyBag | Get-Random -Count ([Math]::Min($target, $familyBag.Count))
  $installed=0

  # boosters (3 cái ngẫu nhiên)
  foreach($b in ($UNICODE_BOOST | Get-Random -Count ([Math]::Min(3,$UNICODE_BOOST.Count)))){
    $first = $b.Urls[0]; $name = $b.Name
    $out = Join-Path $TempDir ([IO.Path]::GetFileName($first))
    if(Download-File -Urls $b.Urls -OutFile $out){ if(Install-One -SrcPath $out -Fallback $name){ $installed++ } }
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

  # fallback cuối: synth duplicate nếu cài quá ít
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

  # 2) RANDOMIZE fallbacks (dùng PickRandom + thêm cursive/fantasy)
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
  if($sym1){ Prepend-Link -Base "Segoe UI Symbol" -Pairs @($sym1.Pair); Set-Sub "Segoe UI Symbol" $sym1.Face; Set-Sub "Cambria Math" $sym1.Face }
  if($emoji){ Prepend-Link -Base "Segoe UI Emoji"  -Pairs @($emoji.Pair); Set-Sub "Segoe UI Emoji"  $emoji.Face }
  if($sans){  Set-Sub "Segoe UI" $sans.Face; Set-Sub "Arial" $sans.Face; Set-Sub "Microsoft Sans Serif" $sans.Face }
  if($serif){ Set-Sub "Times New Roman" $serif.Face; Set-Sub "Cambria" $serif.Face }
  if($mono){  Set-Sub "Courier New" $mono.Face; Set-Sub "Consolas" $mono.Face }
  if($cursive){ Set-Sub "Comic Sans MS" $cursive.Face }
  if($fantasy){ Set-Sub "Impact"        $fantasy.Face }
  Refresh-Fonts

  # 3) Patch Chromium & kill processes
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
  if($invChanged -and $fbChanged){
    Say ("SUCCESS: Both hashes changed in round {0}" -f $round) "Green"; break
  } else {
    Say ("Hashes not both changed (Inv={0}, FB={1}) -> retry next round" -f ($invChanged), ($fbChanged)) "Yellow"
    $beforeInv = $newInv; $beforeFB  = $newFB
  }
}

# --- Final
$finalInv = InvHash; $finalFB = FBHash
Say "`n--- FINAL HASHES ---" "Cyan"
Say ("Inventory:  {0}" -f $finalInv) "White"
Say ("Fallback :  {0}" -f $finalFB) "White"
Log ("Run finished. v{0}" -f $Version)
