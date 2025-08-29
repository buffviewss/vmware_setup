<# ===================================================================
  ADVANCED FONT FINGERPRINT ROTATOR v3.9.0
  mục tiêu: CÀI FONT THẬT + ĐỔI "UNICODE GLYPHS" fingerprint
  - Cài 3–6 font (mặc định) từ các link TTF/OTF *ổn định* (Noto/Libertinus/Google)
  - Ưu tiên các bộ: Math, Symbols, Emoji, Mono, Sans/Serif
  - Random hóa SystemLink + FontSubstitutes (HKLM/HKCU)
  - (Mặc định) Đóng Chrome/Edge và vá default fonts -> hiệu lực ngay trong Chromium
  - Log: %USERPROFILE%\Downloads\log.txt
=================================================================== #>

param(
  [int]$TargetMin = 3,
  [int]$TargetMax = 6,
  [switch]$NoChromiumFonts = $false,
  [switch]$NoForceClose    = $false,
  [string]$ChromeProfile = "Default",
  [string]$EdgeProfile   = "Default"
)

# ---- Admin check ----
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
   ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
  Write-Host "ERROR: Run PowerShell as Administrator!" -ForegroundColor Red
  Read-Host "Press Enter to exit"; exit 1
}

$Version = "3.9.0"

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

# ---- Reliable DIRECT font sources (TTF/OTF). Mỗi item có nhiều mirror thử lần lượt. ----
#  Tập trung coverage: Math/Symbols/Emoji + vài Sans/Serif/Mono phổ biến
$DB = @{
  SymbolsMath = @(
    @{ Name="Noto Sans Math";    Urls=@(
        "https://raw.githubusercontent.com/googlefonts/noto-fonts/main/hinted/ttf/NotoSansMath/NotoSansMath-Regular.ttf",
        "https://cdn.jsdelivr.net/gh/googlefonts/noto-fonts@main/hinted/ttf/NotoSansMath/NotoSansMath-Regular.ttf"
      )},
    @{ Name="Noto Sans Symbols 2"; Urls=@(
        "https://raw.githubusercontent.com/googlefonts/noto-fonts/main/hinted/ttf/NotoSansSymbols2/NotoSansSymbols2-Regular.ttf",
        "https://cdn.jsdelivr.net/gh/googlefonts/noto-fonts@main/hinted/ttf/NotoSansSymbols2/NotoSansSymbols2-Regular.ttf"
      )},
    @{ Name="Noto Music";        Urls=@(
        "https://raw.githubusercontent.com/googlefonts/noto-fonts/main/hinted/ttf/NotoMusic/NotoMusic-Regular.ttf",
        "https://cdn.jsdelivr.net/gh/googlefonts/noto-fonts@main/hinted/ttf/NotoMusic/NotoMusic-Regular.ttf"
      )},
    @{ Name="Libertinus Math";   Urls=@(
        "https://github.com/alerque/libertinus/releases/download/v7.040/LibertinusMath-Regular.otf"
      )}
  )
  Emoji = @(
    @{ Name="Noto Color Emoji";  Urls=@(
        "https://raw.githubusercontent.com/googlefonts/noto-emoji/main/fonts/NotoColorEmoji.ttf",
        "https://cdn.jsdelivr.net/gh/googlefonts/noto-emoji@main/fonts/NotoColorEmoji.ttf"
      )}
  )
  Mono = @(
    @{ Name="JetBrains Mono";    Urls=@(
        "https://github.com/google/fonts/raw/main/ofl/jetbrainsmono/static/JetBrainsMono-Regular.ttf",
        "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/jetbrainsmono/static/JetBrainsMono-Regular.ttf"
      )},
    @{ Name="Inconsolata";       Urls=@(
        "https://github.com/google/fonts/raw/main/ofl/inconsolata/static/Inconsolata-Regular.ttf",
        "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/inconsolata/static/Inconsolata-Regular.ttf"
      )},
    @{ Name="Source Code Pro";   Urls=@(
        "https://github.com/google/fonts/raw/main/ofl/sourcecodepro/static/SourceCodePro-Regular.ttf",
        "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/sourcecodepro/static/SourceCodePro-Regular.ttf"
      )}
  )
  Sans = @(
    @{ Name="Inter";             Urls=@(
        "https://github.com/google/fonts/raw/main/ofl/inter/static/Inter-Regular.ttf",
        "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/inter/static/Inter-Regular.ttf"
      )},
    @{ Name="Open Sans";         Urls=@(
        "https://github.com/google/fonts/raw/main/ofl/opensans/static/OpenSans-Regular.ttf",
        "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/opensans/static/OpenSans-Regular.ttf"
      )},
    @{ Name="Noto Sans";         Urls=@(
        "https://github.com/google/fonts/raw/main/ofl/notosans/static/NotoSans-Regular.ttf",
        "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/notosans/static/NotoSans-Regular.ttf"
      )}
  )
  Serif = @(
    @{ Name="Merriweather";      Urls=@(
        "https://github.com/google/fonts/raw/main/ofl/merriweather/Merriweather-Regular.ttf",
        "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/merriweather/Merriweather-Regular.ttf"
      )},
    @{ Name="Lora";              Urls=@(
        "https://github.com/google/fonts/raw/main/ofl/lora/static/Lora-Regular.ttf",
        "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/lora/static/Lora-Regular.ttf"
      )},
    @{ Name="Noto Serif";        Urls=@(
        "https://github.com/google/fonts/raw/main/ofl/notoserif/static/NotoSerif-Regular.ttf",
        "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/notoserif/static/NotoSerif-Regular.ttf"
      )}
  )
}

# ---- Helpers ----
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Download-File {
  param([string[]]$Urls,[string]$OutFile,[int]$RetryEach=2)
  foreach($u in $Urls){
    for($i=1;$i -le $RetryEach;$i++){
      try {
        Log ("Download attempt {0}: {1}" -f $i,$u)
        if ($PSVersionTable.PSVersion.Major -ge 7) {
          Invoke-WebRequest -Uri $u -OutFile $OutFile -TimeoutSec 240
        } else {
          try { Start-BitsTransfer -Source $u -Destination $OutFile -ErrorAction Stop }
          catch { Invoke-WebRequest -Uri $u -OutFile $OutFile }
        }
        if ((Test-Path $OutFile) -and ((Get-Item $OutFile).Length -gt 1000)) {
          Log ("Download OK: {0}" -f $OutFile); return $true
        }
      } catch { Log ("Download error: {0}" -f $_.Exception.Message) "ERROR" }
      Start-Sleep -Seconds ([Math]::Min(2*$i,8))
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
    return @{Face=$face;File=$fi.Name}
  } catch { Say ("Install error: {0}" -f $_.Exception.Message) "Red" "ERROR"; return $null }
}

function Install-Item {
  param($Item)
  $lowerNames = @(".ttf",".otf")
  $ok=@()
  foreach($url in $Item.Urls){
    $ext = [IO.Path]::GetExtension($url).ToLower()
    if ($lowerNames -notcontains $ext) { continue }
    $out = Join-Path $TempDir ([IO.Path]::GetFileName($url))
    if (Download-File -Urls @($url) -OutFile $out) {
      $r = Install-One -SrcPath $out -Fallback $Item.Name
      if ($r){ $ok += $r; break }
    }
  }
  return $ok
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

# ---- Chromium helpers ----
function Is-ProcRunning { param([string]$Name) try { (Get-Process -Name $Name -ErrorAction SilentlyContinue) -ne $null } catch { $false } }
function Kill-Browsers {
  foreach($p in @("chrome","msedge")){
    try { if(Is-ProcRunning $p){ Stop-Process -Name $p -Force -ErrorAction SilentlyContinue; Start-Sleep 1; Say ("Killed: {0}" -f $p) "Yellow" } } catch {}
  }
}
function Patch-ChromiumFonts {
  param(
    [string]$PrefsPath,[string]$Sans,[string]$Serif,[string]$Mono,
    [string]$Cursive="Comic Sans MS",[string]$Fantasy="Impact"
  )
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

# -------------------- MAIN --------------------
Clear-Host
Write-Host "==============================================================" -ForegroundColor Green
Write-Host ("  ADVANCED FONT FINGERPRINT ROTATOR v{0} (INSTALL + UNICODE GLYPHS)" -f $Version) -ForegroundColor Yellow
Write-Host "==============================================================" -ForegroundColor Green
Log ("OS: {0}  PS: {1}" -f [Environment]::OSVersion.VersionString, $PSVersionTable.PSVersion)

# Baseline hashes
$beforeCount = (CurFonts).Count
$beforeInv   = InvHash
$beforeFB    = FBHash
Say ("Current fonts: {0}" -f $beforeCount) "Cyan"
Say ("Inventory Hash: {0}..." -f (Head32 $beforeInv)) "Cyan"
Say ("Fallback Hash : {0}..." -f (Head32 $beforeFB)) "Cyan"

# 1) INSTALL a few fonts (emphasis: Math/Symbols/Emoji + some Mono/Sans/Serif)
$pool=@()
foreach($cat in $DB.Keys){
  foreach($it in $DB[$cat]){
    $pool += ,@{ Cat=$cat; Item=$it }
  }
}
# Bắt buộc chọn 1 Emoji + 1 Math/Symbols trước, sau đó bổ sung ngẫu nhiên
$must=@()
$must += ($pool | Where-Object { $_.Cat -eq 'Emoji' } | Get-Random -Count 1)
$must += ($pool | Where-Object { $_.Cat -eq 'SymbolsMath' } | Get-Random -Count 2) # ít nhất 2 bộ ký tự đặc biệt
$extraNeed = [Math]::Max($TargetMin,3)
$maxTake   = [Math]::Max($TargetMax,3)
$leftCount = [Math]::Max(0, $maxTake - $must.Count)
$extra = ($pool | Where-Object { $must -notcontains $_ } | Get-Random -Count ([Math]::Min($leftCount, $pool.Count)))
$todo = $must + $extra

$installed=0
foreach($t in $todo){
  $name = $t.Item.Name
  $urls = $t.Item.Urls
  $out  = Join-Path $TempDir ([IO.Path]::GetFileName($urls[0]))
  if (Download-File -Urls $urls -OutFile $out) {
    $res = Install-One -SrcPath $out -Fallback $name
    if($res){ $installed += 1 }
  } else {
    Say ("Download failed: {0}" -f ($urls -join " | ")) "Red" "ERROR"
  }
}
# 2) RANDOMIZE FALLBACKS to change Unicode glyph suppliers
$map = FaceMap
$sansDest  = PickFirst -Prefer @("Inter","Open Sans","Noto Sans","Segoe UI","Roboto") -Map $map
$serifDest = PickFirst -Prefer @("Merriweather","Lora","Noto Serif","Cambria","Times New Roman") -Map $map
$monoDest  = PickFirst -Prefer @("JetBrains Mono","Source Code Pro","Inconsolata","Consolas","Courier New") -Map $map
$sym1      = PickFirst -Prefer @("Noto Sans Math","Libertinus Math","Noto Sans Symbols 2") -Map $map
$sym2      = PickFirst -Prefer @("Noto Sans Symbols 2","Noto Music","Noto Sans") -Map $map
$emojiDest = PickFirst -Prefer @("Noto Color Emoji") -Map $map -Exact

$base = @("Segoe UI","Segoe UI Variable","Arial","Times New Roman","Courier New","Calibri","Cambria","Consolas","Microsoft Sans Serif","Tahoma","MS Shell Dlg","MS Shell Dlg 2") | Get-Random -Count 12
$pairs=@()
foreach($p in @($sansDest,$serifDest,$monoDest)) { if($p){ $pairs+=$p.Pair } }
if($sym1){ $pairs = ,$sym1.Pair + $pairs }
if($sym2){ $pairs += $sym2.Pair }

foreach($b in $base){
  if($pairs.Count -gt 0){
    $take = Get-Random -Minimum 2 -Maximum ([Math]::Min(5,$pairs.Count)+1)
    Prepend-Link -Base $b -Pairs ($pairs | Get-Random -Count $take)
  }
}
if($sym1){ Prepend-Link -Base "Segoe UI Symbol" -Pairs @($sym1.Pair) }
if($emojiDest){ Prepend-Link -Base "Segoe UI Emoji" -Pairs @($emojiDest.Pair) }

if($sansDest){  Set-Sub "Segoe UI" $sansDest.Face; Set-Sub "Arial" $sansDest.Face; Set-Sub "Microsoft Sans Serif" $sansDest.Face }
if($serifDest){ Set-Sub "Times New Roman" $serifDest.Face; Set-Sub "Cambria" $serifDest.Face }
if($monoDest){  Set-Sub "Courier New" $monoDest.Face; Set-Sub "Consolas" $monoDest.Face }
if($sym1){      Set-Sub "Segoe UI Symbol" $sym1.Face; Set-Sub "Cambria Math" $sym1.Face }
if($emojiDest){ Set-Sub "Segoe UI Emoji" $emojiDest.Face }

# một ít force-prepend để đổi nguồn glyph rõ rệt
if($sym1 -and $monoDest){ Prepend-Link -Base "Arial"           -Pairs @($sym1.Pair,$monoDest.Pair) }
if($serifDest -and $sym1){ Prepend-Link -Base "Times New Roman" -Pairs @($serifDest.Pair,$sym1.Pair) }
if($monoDest -and $sym1){  Prepend-Link -Base "Courier New"     -Pairs @($monoDest.Pair,$sym1.Pair) }

Refresh-Fonts

# 3) Patch Chrome/Edge defaults & đóng tiến trình (bật mặc định)
if(-not $NoForceClose){ Kill-Browsers }
if(-not $NoChromiumFonts){
  $sansFace  = if($sansDest){ $sansDest.Face } else { "Arial" }
  $serifFace = if($serifDest){ $serifDest.Face } else { "Times New Roman" }
  $monoFace  = if($monoDest){ $monoDest.Face } else { "Consolas" }
  $chrome = Join-Path $env:LOCALAPPDATA ("Google\Chrome\User Data\{0}\Preferences" -f $ChromeProfile)
  $edge   = Join-Path $env:LOCALAPPDATA ("Microsoft\Edge\User Data\{0}\Preferences" -f $EdgeProfile)
  Patch-ChromiumFonts -PrefsPath $chrome -Sans $sansFace -Serif $serifFace -Mono $monoFace
  Patch-ChromiumFonts -PrefsPath $edge   -Sans $sansFace -Serif $serifFace -Mono $monoFace
} else {
  Say "NoChromiumFonts: Bỏ qua vá default fonts Chrome/Edge." "Yellow"
}

# --- RESULTS ---
$afterCount = (CurFonts).Count
$afterInv   = InvHash
$afterFB    = FBHash
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
