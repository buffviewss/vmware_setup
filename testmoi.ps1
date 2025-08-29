<# ===================================================================
  ADVANCED FONT FINGERPRINT ROTATOR v3.7.0 (EU/US ONLY • PS 5.x SAFE)
  - Mục tiêu bản 3.7: Tăng độ biến thiên "Unicode Glyphs" fingerprint
    + Ưu tiên/chen nguồn glyph Math/Symbols/Emoji/Mono/Serif vào fallback chain
    + (Tuỳ chọn) Sửa default fonts của Chrome/Edge theo face đã chọn
  - KHÔNG can thiệp spoof tên font dò phổ biến (Font Metrics) trong bản này
  - Chỉ dùng font Âu–Mỹ. KHÔNG xoá font hệ thống.
  - Random cài font + random SystemLink & FontSubstitutes (HKLM & HKCU).
  - BẮT BUỘC đổi cả InventoryHash & FallbackHash (re-roll nhiều lần).
  - Logging: %USERPROFILE%\Downloads\log.txt
=================================================================== #>

param(
  [switch]$ChromiumFonts = $false,      # Bật vá default fonts Chrome/Edge
  [string]$ChromeProfile = "Default",   # Tên profile trình duyệt (thư mục)
  [string]$EdgeProfile   = "Default"    # Tên profile trình duyệt (thư mục)
)

# ---- Admin check ----
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
   ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
  Write-Host "ERROR: Run PowerShell as Administrator!" -ForegroundColor Red
  Read-Host "Press Enter to exit"; exit 1
}

$Version = "3.7.0"

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

# ---- Paths ----
$TempDir  = "$env:TEMP\FontRotator"
$FontsDir = "$env:SystemRoot\Fonts"
if (!(Test-Path $TempDir)) { New-Item -ItemType Directory -Path $TempDir -Force | Out-Null }

# ---- Sources (Âu–Mỹ) ----
$DB = @{
  Sans = @{
    "Inter"          = "https://github.com/rsms/inter/releases/download/v3.19/Inter-3.19.zip"
    "OpenSans"       = "https://github.com/googlefonts/opensans/releases/download/v3.000/opensans.zip"
    "Roboto"         = "https://github.com/googlefonts/roboto/releases/download/v2.138/roboto-unhinted.zip"
    "IBMPlex"        = "https://github.com/IBM/plex/releases/download/v6.4.0/TrueType.zip"
    "DejaVu"         = "https://github.com/dejavu-fonts/dejavu-fonts/releases/download/version_2_37/dejavu-fonts-ttf-2.37.zip"
    "Lato"           = "https://github.com/latofonts/lato-source/releases/download/Lato2OFL/latofonts-opensource.zip"
    "Raleway"        = "https://github.com/impallari/Raleway/archive/refs/heads/master.zip"
    "Montserrat"     = "https://github.com/JulietaUla/Montserrat/archive/refs/heads/master.zip"
  }
  Serif = @{
    "Merriweather"   = "https://github.com/SorkinType/Merriweather/archive/refs/heads/master.zip"
    "Lora"           = "https://github.com/cyrealtype/Lora-Cyrillic/archive/refs/heads/master.zip"
    "LibreBaskerville"="https://github.com/impallari/Libre-Baskerville/archive/refs/heads/master.zip"
    "DejaVuSerif"    = "https://github.com/dejavu-fonts/dejavu-fonts/releases/download/version_2_37/dejavu-fonts-ttf-2.37.zip"
  }
  Mono = @{
    "CascadiaCode"   = "https://github.com/microsoft/cascadia-code/releases/download/v2111.01/CascadiaCode-2111.01.zip"
    "FiraCode"       = "https://github.com/tonsky/FiraCode/releases/download/6.2/Fira_Code_v6.2.zip"
    "JetBrainsMono"  = "https://github.com/JetBrains/JetBrainsMono/releases/download/v2.304/JetBrainsMono-2.304.zip"
    "Inconsolata"    = "https://github.com/googlefonts/Inconsolata/releases/download/v3.000/fonts_ttf.zip"
    "DejaVuMono"     = "https://github.com/dejavu-fonts/dejavu-fonts/releases/download/version_2_37/dejavu-fonts-ttf-2.37.zip"
  }
  SymbolsMath = @{
    "XITSMath"       = "https://github.com/khaledhosny/xits-fonts/releases/download/v1.301/xits-math-otf-1.301.zip"
    "LibertinusMath" = "https://github.com/alerque/libertinus/releases/download/v7.040/LibertinusMath-Regular.otf"
    "DejaVuSans"     = "https://github.com/dejavu-fonts/dejavu-fonts/releases/download/version_2_37/dejavu-fonts-ttf-2.37.zip"
    "NotoSansMath"   = "https://raw.githubusercontent.com/googlefonts/noto-fonts/main/hinted/ttf/NotoSansMath/NotoSansMath-Regular.ttf"
  }
  Emoji = @{
    "NotoColorEmoji" = "https://raw.githubusercontent.com/googlefonts/noto-emoji/main/fonts/NotoColorEmoji.ttf"
  }
}

# ---- Helpers ----
function Download-File {
  param([string]$Url,[string]$OutFile,[int]$Retry=3)
  for($i=1;$i -le $Retry;$i++){
    try {
      Log ("Download attempt {0}: {1}" -f $i,$Url)
      if ($PSVersionTable.PSVersion.Major -ge 7) {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -TimeoutSec 300
      } else {
        try { Start-BitsTransfer -Source $Url -Destination $OutFile -ErrorAction Stop }
        catch { Invoke-WebRequest -Uri $Url -OutFile $OutFile }
      }
      if ((Test-Path $OutFile) -and ((Get-Item $OutFile).Length -gt 1000)) { Log ("Download OK: {0}" -f $OutFile); return $true }
    } catch { Log ("Download error: {0}" -f $_.Exception.Message) "ERROR" }
    Start-Sleep -Seconds ([Math]::Min(2*$i,10))
  }
  Log ("Download failed: {0}" -f $Url) "ERROR"; return $false
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

function Install-One { param([string]$File,[string]$Fallback="Custom") }
  try {
    $fi = Get-Item $File
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
    return @{Face=$face;File=$fi.Name}
  } catch { Say ("Install error: {0}" -f $_.Exception.Message) "Red" "ERROR"; return $null }
}

function Install-FromUrl { param([string]$Name,[string]$Url) }
  try {
    $lower = $Url.ToLower()
    if ($lower.EndsWith(".ttf") -or $lower.EndsWith(".otf")) {
      $out = Join-Path $TempDir ([IO.Path]::GetFileName($Url))
      if (!(Download-File $Url $out)) { Say ("Download failed: {0}" -f $Name) "Red" "ERROR"; return @() }
      $r = Install-One -File $out -Fallback $Name
      if ($r){,@($r)} else {@()}
    } elseif ($lower.EndsWith(".zip")) {
      $zip = Join-Path $TempDir "$Name.zip"
      if (!(Download-File $Url $zip)) { Say ("Download failed: {0}" -f $Name) "Red" "ERROR"; return @() }
      $ex = Join-Path $TempDir ("ex_" + $Name)
      if (Test-Path $ex) { Remove-Item $ex -Recurse -Force -ErrorAction SilentlyContinue }
      try { Expand-Archive -Path $zip -DestinationPath $ex -Force }
      catch { Say ("Unzip error {0}: {1}" -f $Name,$_.Exception.Message) "Red" "ERROR"; return @() }
      $pick = Get-ChildItem $ex -Recurse -Include *.ttf,*.otf |
        Where-Object { $_.Name -notmatch "italic|oblique|thin|hairline|light" } |
        Sort-Object { if($_.Name -match "regular|normal"){0}elseif($_.Name -match "medium"){1}elseif($_.Name -match "semibold|demibold"){2}else{3} } |
        Select-Object -First 4
      $res=@(); foreach($p in $pick){ $x=Install-One $p.FullName $Name; if($x){$res+=$x} }
      $res
    } else {
      Say ("Unsupported URL type: {0}" -f $Url) "Yellow" "WARN"; @()
    }
  } catch { Say ("Install-FromUrl error: {0}" -f $_.Exception.Message) "Red" "ERROR"; @() }
}

function FaceMap {
  $map=@{}; $reg="HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
  try {
    (Get-ItemProperty $reg -ErrorAction SilentlyContinue).PSObject.Properties |
      Where-Object { $_.Name -and $_.Name -notmatch '^PS' -and $_.Value } |
      ForEach-Object { $map[($_.Name -replace ' \(TrueType\)$','' -replace ' \(OpenType\)$','')] = $_.Value }
  } catch { Log ("FaceMap error: {0}" -f $_.Exception.Message) "WARN" }
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
    $bases=@(
      "Segoe UI","Segoe UI Variable","Segoe UI Symbol","Segoe UI Emoji",
      "Arial","Times New Roman","Courier New","Calibri","Cambria","Consolas",
      "Microsoft Sans Serif","Tahoma","MS Shell Dlg","MS Shell Dlg 2","Cambria Math"
    )
    $rows=@()
    foreach($root in @('HKLM','HKCU')){
      $sys=("{0}:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontLink\SystemLink" -f $root)
      $sub=("{0}:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -f $root)
      foreach($b in $bases){
        $v=(Get-ItemProperty -Path $sys -Name $b -ErrorAction SilentlyContinue).$b
        if($v){$rows+=("SYS[{0}]:{1}={2}" -f $root,$b,($v -join ';'))}
      }
      foreach($n in $bases){
        $vv=(Get-ItemProperty -Path $sub -Name $n -ErrorAction SilentlyContinue).$n
        if($vv){$rows+=("SUB[{0}]:{1}={2}" -f $root,$n,$vv)}
      }
    }
    $bytes=[Text.Encoding]::UTF8.GetBytes(($rows -join "`n"))
    ([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($bytes)) -replace '-','')
  } catch { "NA" }
}

# SystemLink HKLM+HKCU
function Prepend-Link { param([string]$Base,[string[]]$Pairs)
  foreach($root in @('HKLM','HKCU')){
    $key=("{0}:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontLink\SystemLink" -f $root)
    try {
      $cur=(Get-ItemProperty -Path $key -Name $Base -ErrorAction SilentlyContinue).$Base
      if (-not $cur){$cur=@()}
      $new=($Pairs + $cur) | Select-Object -Unique
      New-ItemProperty -Path $key -Name $Base -Value $new -PropertyType MultiString -Force | Out-Null
      Log ("SystemLink [{0}] ({1}) <= {2}" -f $Base,$root,($Pairs -join ' | '))
    } catch {
      Say ("Prepend error {0}/{1}: {2}" -f $Base,$root,$_.Exception.Message) "Red" "ERROR"
    }
  }
}

# FontSubstitutes HKLM+HKCU
function Set-Sub { param([string]$From,[string]$To)
  foreach($root in @('HKLM','HKCU')){
    $key=("{0}:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -f $root)
    try {
      try { Set-ItemProperty -Path $key -Name $From -Value $To -ErrorAction Stop }
      catch { New-ItemProperty -Path $key -Name $From -Value $To -PropertyType String -Force | Out-Null }
      Say ("Substitute({0}): {1} -> {2}" -f $root,$From,$To) "Yellow"
    } catch {
      Say ("Substitute error {0}->{1}/{2}: {3}" -f $From,$To,$root,$_.Exception.Message) "Red" "ERROR"
    }
  }
}

function Refresh-Fonts {
  try { Stop-Service FontCache -Force -ErrorAction SilentlyContinue; Start-Sleep 1; Remove-Item "$env:LOCALAPPDATA\FontCache\*" -Force -ErrorAction SilentlyContinue } catch { Log ("FontCache cleanup: {0}" -f $_.Exception.Message) "WARN" }
  try { Start-Service FontCache -ErrorAction SilentlyContinue } catch {}
  try {
    Add-Type -Namespace Win32 -Name U -MemberDefinition '[DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h,uint m,IntPtr w,IntPtr l,uint f,uint t,out IntPtr r);'
    [void][Win32.U]::SendMessageTimeout([IntPtr]0xffff,0x1D,[IntPtr]0,[IntPtr]0,2,1000,[ref]([IntPtr]::Zero))
  } catch { Log ("Broadcast warn: {0}" -f $_.Exception.Message) "WARN" }
}

function PickFirst { param([string[]]$Prefer,[hashtable]$Map,[switch]$Exact)
  foreach($n in $Prefer){
    foreach($k in $Map.Keys){
      $ok = $false
      if ($Exact) { if ($k -eq $n) { $ok = $true } }
      else { if (($k -eq $n) -or ($k -like ($n + "*"))) { $ok = $true } }
      if($ok){
        $f=$Map[$k]; if($f -and (Test-Path (Join-Path $FontsDir $f))){
          return @{Face=$k;Pair=("{0},{1}" -f $f,$k)}
        }
      }
    }
  } $null
}

# ---- (NEW in 3.7) Chromium default fonts patch ----
function Is-ProcRunning { param([string]$Name) try { (Get-Process -Name $Name -ErrorAction SilentlyContinue) -ne $null } catch { $false } }
function Patch-ChromiumFonts {
  param(
    [string]$PrefsPath,[string]$Sans,[string]$Serif,[string]$Mono,
    [string]$Cursive="Comic Sans MS",[string]$Fantasy="Impact"
  )
  if(!(Test-Path $PrefsPath)){ Log ("Chromium Prefs not found: {0}" -f $PrefsPath) "WARN"; return }
  if(Is-ProcRunning "chrome" -or Is-ProcRunning "msedge"){
    Say "Chrome/Edge đang chạy — bỏ qua vá default fonts. Hãy tắt trình duyệt và chạy lại với -ChromiumFonts nếu muốn." "Yellow" "WARN"
    return
  }
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
        "standard" { $Serif }
        "serif"    { $Serif }
        "sansserif"{ $Sans }
        "fixed"    { $Mono }
        "cursive"  { $Cursive }
        "fantasy"  { $Fantasy }
      }
    }
    ($json | ConvertTo-Json -Depth 20) | Set-Content -Encoding UTF8 $PrefsPath
    Say ("Patched Chromium Prefs: {0} (sans={1}, serif={2}, mono={3})" -f $PrefsPath,$Sans,$Serif,$Mono) "Green"
  } catch {
    Say ("Chromium patch error: {0}" -f $_.Exception.Message) "Red" "ERROR"
  }
}

# ---- MAIN ----
Clear-Host
Write-Host "==============================================================" -ForegroundColor Green
Write-Host ("  ADVANCED FONT FINGERPRINT ROTATOR v{0} (EU/US ONLY)" -f $Version) -ForegroundColor Yellow
Write-Host "==============================================================" -ForegroundColor Green
Log ("OS: {0}  PS: {1}" -f [Environment]::OSVersion.VersionString, $PSVersionTable.PSVersion)

# Baseline
$beforeCount = (CurFonts).Count
$beforeInv   = InvHash
$beforeFB    = FBHash
Say ("Current fonts: {0}" -f $beforeCount) "Cyan"
Say ("Inventory Hash: {0}..." -f (Head32 $beforeInv)) "Cyan"
Say ("Fallback Hash : {0}..." -f (Head32 $beforeFB)) "Cyan"

# --- 1) INSTALL NEW FONTS until InventoryHash changes (giữ nguyên cơ chế 3.6.1) ---
function Install-Round { param([int]$Target=7)
  $cats = @($DB.Sans,$DB.Serif,$DB.Mono,$DB.SymbolsMath,$DB.Emoji)
  $pool=@()
  foreach($c in $cats){ foreach($k in $c.Keys){ $pool+=,@{Name=$k;Url=$c[$k]} } }
  $todo = $pool | Get-Random -Count ([Math]::Min($Target,$pool.Count))
  $installed=0
  foreach($i in $todo){ $list = Install-FromUrl -Name $i.Name -Url $i.Url; $installed += $list.Count }
  return $installed
}
$tries=0; $afterInv=$beforeInv
do {
  $tries++
  [void](Install-Round -Target (Get-Random -Minimum 6 -Maximum 10))
  Start-Sleep 1
  $afterInv = InvHash
} while ($afterInv -eq $beforeInv -and $tries -lt 3)

# --- 2) RANDOMIZE FALLBACKS (Unicode Glyphs) until FallbackHash changes — ENHANCED in 3.7 ---
function Apply-RandomFallback {
  $map = FaceMap

  $sansDest  = PickFirst -Prefer @("Inter","Open Sans","Roboto","IBM Plex Sans","DejaVu Sans","Lato","Raleway","Montserrat") -Map $map
  $serifDest = PickFirst -Prefer @("Merriweather","Lora","Libre Baskerville","DejaVu Serif") -Map $map
  $monoDest  = PickFirst -Prefer @("Cascadia Mono","Cascadia Code","Fira Code","JetBrains Mono","Inconsolata","DejaVu Sans Mono","IBM Plex Mono") -Map $map
  $sym1      = PickFirst -Prefer @("XITS Math","Libertinus Math","Noto Sans Math","DejaVu Sans") -Map $map
  $sym2      = PickFirst -Prefer @("DejaVu Sans","XITS Math","Libertinus Math","Noto Sans Math") -Map $map
  $emojiDest = PickFirst -Prefer @("Noto Color Emoji") -Map $map -Exact

  $base = @("Segoe UI","Segoe UI Variable","Arial","Times New Roman","Courier New","Calibri","Cambria","Consolas","Microsoft Sans Serif","Tahoma","MS Shell Dlg","MS Shell Dlg 2") | Get-Random -Count 12

  # pairs tổng hợp
  $pairs=@()
  foreach($p in @($sansDest,$serifDest,$monoDest)) { if($p){ $pairs+=$p.Pair } }
  if($sym1){ $pairs = ,$sym1.Pair + $pairs }   # ép Math/Symbols đứng đầu để đổi nguồn glyph cho các ký tự đặc biệt
  if($sym2){ $pairs += $sym2.Pair }
  foreach($b in $base){
    if($pairs.Count -gt 0){
      $take = Get-Random -Minimum 2 -Maximum ([Math]::Min(5,$pairs.Count)+1)
      Prepend-Link -Base $b -Pairs ($pairs | Get-Random -Count $take)
    }
  }
  if($sym1){ Prepend-Link -Base "Segoe UI Symbol" -Pairs @($sym1.Pair) }
  if($emojiDest){ Prepend-Link -Base "Segoe UI Emoji" -Pairs @($emojiDest.Pair) }

  # Substitutes để ảnh hưởng generic families
  if($sansDest){  Set-Sub "Segoe UI" $sansDest.Face; Set-Sub "Arial" $sansDest.Face; Set-Sub "Microsoft Sans Serif" $sansDest.Face }
  if($serifDest){ Set-Sub "Times New Roman" $serifDest.Face; Set-Sub "Cambria" $serifDest.Face }
  if($monoDest){  Set-Sub "Courier New" $monoDest.Face; Set-Sub "Consolas" $monoDest.Face }
  if($sym1){      Set-Sub "Segoe UI Symbol" $sym1.Face; Set-Sub "Cambria Math" $sym1.Face }
  if($emojiDest){ Set-Sub "Segoe UI Emoji" $emojiDest.Face }

  # (NEW 3.7) Force-prepend coverage để đổi nguồn glyph rõ rệt trên base families
  if($sym1 -and $monoDest){ Prepend-Link -Base "Arial"           -Pairs @($sym1.Pair,$monoDest.Pair) }
  if($serifDest -and $sym1){ Prepend-Link -Base "Times New Roman" -Pairs @($serifDest.Pair,$sym1.Pair) }
  if($monoDest -and $sym1){  Prepend-Link -Base "Courier New"     -Pairs @($monoDest.Pair,$sym1.Pair) }
  if($serifDest){            Prepend-Link -Base "Cambria"         -Pairs @($serifDest.Pair) }
  if($monoDest){             Prepend-Link -Base "Consolas"        -Pairs @($monoDest.Pair) }
  if($emojiDest){            Prepend-Link -Base "Segoe UI Emoji"  -Pairs @($emojiDest.Pair) }
  if($sym1){                 Prepend-Link -Base "Cambria Math"    -Pairs @($sym1.Pair) }

  Refresh-Fonts

  # Trả về faces đã chọn để (tuỳ chọn) patch Chromium
  return @{
    Sans  = $sansDest; Serif=$serifDest; Mono=$monoDest;
    Sym   = $sym1;     Emoji=$emojiDest
  }
}

$fbTries=0; $afterFB=$beforeFB; $targets=$null
do {
  $fbTries++
  $targets = Apply-RandomFallback
  $afterFB = FBHash
} while ($afterFB -eq $beforeFB -and $fbTries -lt 7)

# --- (Tuỳ chọn) Patch Chrome/Edge default fonts theo faces cuối cùng ---
if($ChromiumFonts){
  $sansFace  = if($targets.Sans){ $targets.Sans.Face } else { "Inter" }
  $serifFace = if($targets.Serif){ $targets.Serif.Face } else { "Merriweather" }
  $monoFace  = if($targets.Mono){ $targets.Mono.Face } else { "Cascadia Code" }

  $chrome = Join-Path $env:LOCALAPPDATA ("Google\Chrome\User Data\{0}\Preferences" -f $ChromeProfile)
  $edge   = Join-Path $env:LOCALAPPDATA ("Microsoft\Edge\User Data\{0}\Preferences" -f $EdgeProfile)

  Patch-ChromiumFonts -PrefsPath $chrome -Sans $sansFace -Serif $serifFace -Mono $monoFace
  Patch-ChromiumFonts -PrefsPath $edge   -Sans $sansFace -Serif $serifFace -Mono $monoFace
}

# --- RESULTS ---
$afterCount = (CurFonts).Count
Say "`n--- FONT METRICS (Registry list) ---" "Cyan"
Say ("Count: {0} -> {1}  (Δ {2})" -f $beforeCount,$afterCount,($afterCount-$beforeCount)) "Green"

Say "`n--- HASHES ---" "Cyan"
Say ("Inventory:  {0} -> {1}" -f (Head32 $beforeInv),(Head32 $afterInv)) "White"
Say ("Fallback :  {0} -> {1}" -f (Head32 $beforeFB),(Head32 $afterFB)) "White"

$invChanged = ($beforeInv -ne $afterInv)
$fbChanged  = ($beforeFB -ne $afterFB)
Say ("Font Metrics changed?   " + ($(if($invChanged){"YES"}else{"NO"}))) ($(if($invChanged){"Green"}else{"Red"}))
Say ("Unicode Glyphs changed? " + ($(if($fbChanged) {"YES"}else{"NO"}))) ($(if($fbChanged) {"Green"}else{"Red"}))

try { Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue } catch {}
Log ("Run finished. v{0}" -f $Version)
