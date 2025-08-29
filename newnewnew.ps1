<# ===================================================================
  ADVANCED FONT FINGERPRINT ROTATOR v3.10-API
  Mục tiêu: MỖI LẦN CHẠY đổi được:
    • Font Metrics Fingerprint (Inventory hash)
    • Unicode Glyphs Fingerprint (Fallback hash)
  Cách làm:
    1) Gỡ 1 phần các font do script cài từ trước (không đụng font hệ thống).
    2) Cài mới N font qua API: Fontsource(jsDelivr/unpkg) → Google CSS2(gstatic TTF) → GitHub Contents.
    3) Random SystemLink + FontSubstitutes (HKLM/HKCU), vá default fonts Chrome/Edge, kill tiến trình.
  Log: %USERPROFILE%\Downloads\log.txt
=================================================================== #>

param(
  [int]$InstallMin   = 12,
  [int]$InstallMax   = 18,
  [int]$UninstallMin = 6,
  [int]$UninstallMax = 10,
  [switch]$KeepGrowth = $false,     # không gỡ font cũ (chỉ cộng dồn)
  [switch]$NoChromiumFonts = $false,
  [switch]$NoForceClose    = $false,
  [string]$ChromeProfile = "Default",
  [string]$EdgeProfile   = "Default",
  [int]$MaxRounds = 3               # số vòng thử nếu hash chưa đổi
)

# ---- Admin check ----
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
   ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
  Write-Host "ERROR: Run PowerShell as Administrator!" -ForegroundColor Red
  Read-Host "Press Enter to exit"; exit 1
}

$Version = "3.10-API"
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

# ---- Danh sách family (API sẽ tự tìm file .ttf/.otf)
$FAMILIES = @{
  Sans  = @(
    "Inter","Open Sans","Roboto","Noto Sans","Work Sans","Manrope","Poppins",
    "DM Sans","Karla","Rubik","Cabin","Asap","Lexend","Heebo","Outfit",
    "Sora","Plus Jakarta Sans","Nunito Sans","Mulish","Urbanist","Montserrat",
    "Raleway","Lato","Source Sans 3","PT Sans","Fira Sans","IBM Plex Sans"
  )
  Serif = @(
    "Merriweather","Lora","Libre Baskerville","Playfair Display","Source Serif 4",
    "Cardo","Crimson Pro","Cormorant Garamond","Old Standard TT","Domine",
    "Spectral","EB Garamond","Gentium Book Plus","Literata","Tinos","Georgia Pro"
  )
  Mono  = @(
    "Source Code Pro","JetBrains Mono","Inconsolata","Cousine","Anonymous Pro",
    "Iosevka","Fira Code","IBM Plex Mono","Ubuntu Mono","Red Hat Mono"
  )
}

# ---- Unicode boosters (Noto) – trực tiếp, rất ổn định
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

# ===================== API RESOLVERS =====================
function To-PackageName { param([string]$family)
  ($family.ToLower() -replace '[\s_]+','-')
}

# 1) Fontsource + jsDelivr API
function Get-FontFromFontsource {
  param([string]$Family)
  $pkg = To-PackageName $Family
  $metaUrl = "https://data.jsdelivr.com/v1/package/npm/@fontsource/$pkg"
  try {
    $meta = Invoke-WebRequest -UseBasicParsing -TimeoutSec 60 -Headers @{ 'User-Agent'='FontRotator/3.10' } $metaUrl | ConvertFrom-Json
    $ver  = $meta.versions[0]
    $files = (Invoke-WebRequest -UseBasicParsing -TimeoutSec 60 -Headers @{ 'User-Agent'='FontRotator/3.10' } "https://data.jsdelivr.com/v1/package/npm/@fontsource/$pkg@${ver}") | ConvertFrom-Json
    $all = $files.files | Where-Object { $_ -match '\.ttf$' }
    $pick = $all | Where-Object { $_ -match 'latin.*400.*normal\.ttf$' } | Select-Object -First 1
    if(-not $pick){ $pick = $all | Select-Object -First 1 }
    if($pick){
      $cdn = "https://cdn.jsdelivr.net/npm/@fontsource/$pkg@${ver}/$pick"
      $mirror = "https://unpkg.com/@fontsource/$pkg@${ver}/$pick"
      return ,@($cdn,$mirror)
    }
  } catch { Log ("Fontsource API error ($Family): $($_.Exception.Message)") "WARN" }
  @()
}

# 2) Google Fonts CSS2 → trích TTF từ gstatic bằng UA Android 4.4 (trả 'truetype')
function Get-FontFromGoogleCSS {
  param([string]$Family,[int]$Weight=400)
  $famQuery = [uri]::EscapeDataString($Family) -replace '%20','+'
  $cssUrl = "https://fonts.googleapis.com/css2?family=$famQuery:wght@$Weight&display=swap"
  $ua = 'Mozilla/5.0 (Linux; Android 4.4; Nexus 5 Build/KRT16M) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/30.0.0.0 Mobile Safari/537.36'
  try {
    $css = Invoke-WebRequest -Headers @{ 'User-Agent'=$ua } -UseBasicParsing -TimeoutSec 60 $cssUrl
    $ttf = ([regex]'url\(([^)]+\.ttf)\)').Matches($css.Content) | ForEach-Object { $_.Groups[1].Value.Trim("'`"") }
    $ttf | Select-Object -Unique
  } catch { Log ("GF CSS2 error ($Family): $($_.Exception.Message)") "WARN"; @() }
}

# 3) GitHub Contents API (google/fonts) – lấy tên file hiện tại
function Get-FontFromGitHubGF {
  param([string]$Family)
  $folder = (To-PackageName $Family)
  $api = "https://api.github.com/repos/google/fonts/contents/ofl/$folder"
  try {
    $list = Invoke-WebRequest -UseBasicParsing -TimeoutSec 60 -Headers @{ 'User-Agent'='FontRotator/3.10' } $api | ConvertFrom-Json
    $ttf = $list | Where-Object { $_.type -eq 'file' -and $_.name -match '\.(ttf|otf)$' } | Select-Object -ExpandProperty name
    $pick = ($ttf | Where-Object { $_ -match 'wght' } | Select-Object -First 1)
    if(-not $pick){ $pick = $ttf | Select-Object -First 1 }
    if($pick){
      $raw = "https://raw.githubusercontent.com/google/fonts/main/ofl/$folder/$pick"
      return ,@($raw)
    }
  } catch { Log ("GitHub GF API error ($Family): $($_.Exception.Message)") "WARN" }
  @()
}

# Tổng hợp
function Resolve-FontTTF { param([string]$Family)
  $urls=@()
  $urls += Get-FontFromFontsource $Family
  if(-not $urls -or $urls.Count -lt 2){ $urls += Get-FontFromGoogleCSS $Family }
  if(-not $urls){ $urls += Get-FontFromGitHubGF $Family }
  $urls | Select-Object -Unique
}

# ===================== Core Helpers =====================
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
    # remove registry entries pointing to this file
    $reg = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
    $props = (Get-ItemProperty $reg -ErrorAction SilentlyContinue).PSObject.Properties |
      Where-Object { $_.Value -and ($_.Value -ieq $File) }
    foreach($p in $props){ try { Remove-ItemProperty -Path $reg -Name $p.Name -ErrorAction SilentlyContinue } catch {} }
    if(Test-Path $full){ try { Remove-Item $full -Force -ErrorAction SilentlyContinue } catch {} }
    Say ("Uninstalled file: {0}" -f $File) "Yellow"
    # update ownership list
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
  try {
    $reg="HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
    (Get-ItemProperty $reg -ErrorAction SilentlyContinue).PSObject.Properties |
      Where-Object { $_.Name -and $_.Name -notmatch '^PS' -and $_.Value } |
      ForEach-Object { $_.Name -replace ' \(TrueType\)$','' -replace ' \(OpenType\)$','' } |
      Sort-Object -Unique
  } catch { @() }
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
function PickFirst { param([string[]]$Prefer,[hashtable]$Map,[switch]$Exact)
  foreach($n in $Prefer){ foreach($k in $Map.Keys){
    $ok = if($Exact){ $k -eq $n } else { ($k -eq $n) -or ($k -like ($n + "*")) }
    if($ok){ $f=$Map[$k]; if($f -and (Test-Path (Join-Path $FontsDir $f))){ return @{Face=$k;Pair=("{0},{1}" -f $f,$k)} } }
  }} $null
}

# ---- Chromium helpers ----
function Is-ProcRunning { param([string]$Name) try { (Get-Process -Name $Name -ErrorAction SilentlyContinue) -ne $null } catch { $false } }
function Kill-Browsers {
  foreach($p in @("chrome","msedge")){
    try { if(Is-ProcRunning $p){ Stop-Process -Name $p -Force -ErrorAction SilentlyContinue; Start-Sleep 1; Say ("Killed: {0}" -f $p) "Yellow" } } catch {}
  }
}
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
    Say ("Patched Chromium Prefs: {0} (sans={1}, serif={2}, mono={3})" -f $PrefsPath,$Sans,$Serif,$Mono) "Green"
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

  # 0) Optional remove old owned fonts
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

  # 1) INSTALL fresh fonts via API + Unicode boosters
  $target = Get-Random -Minimum $InstallMin -Maximum ($InstallMax+1)
  $familyBag=@()
  foreach($cat in $FAMILIES.Keys){ foreach($fam in $FAMILIES[$cat]){ $familyBag += ,@{Cat=$cat;Fam=$fam} } }
  $familyPick = $familyBag | Get-Random -Count ([Math]::Min($target, $familyBag.Count))
  $installed=0

  # bắt buộc cài boosters trước
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
      if(Download-File -Urls $urls -OutFile $out){
        if(Install-One -SrcPath $out -Fallback $fam){ $installed++ }
      } else { Say ("Download failed via API: {0}" -f $fam) "Red" "ERROR" }
    } else {
      Say ("API could not resolve: {0}" -f $fam) "Red" "ERROR"
    }
  }

  # Fallback cuối: nếu cài quá ít (network kém) → synth duplicate để đổi Inventory
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

  # 2) RANDOMIZE unicode glyph fallbacks
  $map = FaceMap
  $sans  = PickFirst -Prefer @("Inter","Open Sans","Noto Sans","Roboto","Segoe UI","Work Sans","Manrope") -Map $map
  $serif = PickFirst -Prefer @("Merriweather","Lora","Noto Serif","Source Serif","Cambria","Times New Roman","Playfair Display") -Map $map
  $mono  = PickFirst -Prefer @("JetBrains Mono","Source Code Pro","Inconsolata","Cousine","Anonymous Pro","Consolas","Courier New") -Map $map
  $sym1  = PickFirst -Prefer @("Noto Sans Math","Noto Sans Symbols 2") -Map $map
  $sym2  = PickFirst -Prefer @("Noto Music","Noto Sans Symbols 2","Noto Sans") -Map $map
  $emoji = PickFirst -Prefer @("Noto Color Emoji") -Map $map -Exact

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
  Refresh-Fonts

  # 3) Patch Chromium & kill processes
  if(-not $NoForceClose){ Kill-Browsers }
  if(-not $NoChromiumFonts){
    $sf = if($sans){$sans.Face}else{"Arial"}
    $rf = if($serif){$serif.Face}else{"Times New Roman"}
    $mf = if($mono){$mono.Face}else{"Consolas"}
    $chrome = Join-Path $env:LOCALAPPDATA ("Google\Chrome\User Data\{0}\Preferences" -f $ChromeProfile)
    $edge   = Join-Path $env:LOCALAPPDATA ("Microsoft\Edge\User Data\{0}\Preferences" -f $EdgeProfile)
    Patch-ChromiumFonts -PrefsPath $chrome -Sans $sf -Serif $rf -Mono $mf
    Patch-ChromiumFonts -PrefsPath $edge   -Sans $sf -Serif $rf -Mono $mf
  } else {
    Say "NoChromiumFonts: SKIP patch Chrome/Edge." "Yellow"
  }

  # 4) Check hashes
  $newInv = InvHash; $newFB = FBHash
  Say ("Round {0} Inventory:  {1} -> {2}" -f $round,(Head32 $beforeInv),(Head32 $newInv)) "White"
  Say ("Round {0} Fallback :  {1} -> {2}" -f $round,(Head32 $beforeFB),(Head32 $newFB)) "White"

  $invChanged = ($newInv -ne $beforeInv)
  $fbChanged  = ($newFB -ne $beforeFB)

  if($invChanged -and $fbChanged){
    Say ("SUCCESS: Both hashes changed in round {0}" -f $round) "Green"
    break
  } else {
    Say ("Hashes not both changed (Inv={0}, FB={1}) -> retry next round" -f ($invChanged), ($fbChanged)) "Yellow"
    $beforeInv = $newInv
    $beforeFB  = $newFB
  }
}

# --- Final
$finalInv = InvHash; $finalFB = FBHash
Say "`n--- FINAL HASHES ---" "Cyan"
Say ("Inventory:  {0}" -f $finalInv) "White"
Say ("Fallback :  {0}" -f $finalFB) "White"
Log ("Run finished. v{0}" -f $Version)
