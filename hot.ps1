<# ===================================================================
   ADVANCED FONT FINGERPRINT ROTATOR v3.5 (PowerShell 5.x SAFE)
   - Logging -> %USERPROFILE%\Downloads\log.txt (append)
   - Random cài font (nguồn uy tín), KHÔNG xoá font hệ thống
   - Override Unicode glyphs thật sự: SystemLink + FontSubstitutes
     * Ghi vào cả HKLM và HKCU
     * Thay các mặt gốc (Segoe UI, Microsoft Sans Serif, Tahoma, MS Shell Dlg…)
   - Không mở browser tự động
=================================================================== #>

# ===== Admin check =====
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "ERROR: Please run PowerShell as Administrator!" -ForegroundColor Red
    Read-Host "Press Enter to exit"; exit 1
}

# ===== Logging =====
$DownloadDir = Join-Path $env:USERPROFILE 'Downloads'
if (!(Test-Path $DownloadDir)) { New-Item -ItemType Directory -Path $DownloadDir -Force | Out-Null }
$LogFile = Join-Path $DownloadDir 'log.txt'
$RunStamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
Add-Content -Path $LogFile -Value ("`n=== RUN {0} ===" -f $RunStamp)

function Write-Log { param([string]$Message,[string]$Level="INFO")
  try { Add-Content -Path $LogFile -Value ("[{0}] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Level,$Message) } catch {}
}
function Write-Status { param([string]$m,[string]$c="Cyan",[string]$lvl="INFO")
  Write-Host "[$(Get-Date -Format HH:mm:ss)] $m" -ForegroundColor $c
  Write-Log -Message $m -Level $lvl
}
function Head32 { param($s) if($s -and $s.Length -ge 32){$s.Substring(0,32)}elseif($s){$s}else{"NA"} }

# ===== Globals =====
$TempDir  = "$env:TEMP\FontRotator"
$FontsDir = "$env:SystemRoot\Fonts"
if (!(Test-Path $TempDir)) { New-Item -ItemType Directory -Path $TempDir -Force | Out-Null }

# ===== Font sources (một số tag cũ có thể 404; script có retry và bỏ qua nếu fail) =====
$FontDB = @{
  Western = @{
    "Inter"         = "https://github.com/rsms/inter/releases/download/v3.19/Inter-3.19.zip"
    "JetBrainsMono" = "https://github.com/JetBrains/JetBrainsMono/releases/download/v2.304/JetBrainsMono-2.304.zip"
    "Roboto"        = "https://github.com/googlefonts/roboto/releases/download/v2.138/roboto-unhinted.zip"
    "Ubuntu"        = "https://github.com/googlefonts/ubuntu/releases/download/v0.83/ubuntu-font-family-0.83.zip"
    "OpenSans"      = "https://github.com/googlefonts/opensans/releases/download/v3.000/opensans.zip"
    "Merriweather"  = "https://github.com/SorkinType/Merriweather/releases/download/v1.582/Merriweather-v1.582.zip"
    "Lora"          = "https://github.com/cyrealtype/Lora-Cyrillic/releases/download/2.101/Lora_Fonts.zip"
  };
  Unicode = @{
    "NotoSans"      = "https://github.com/googlefonts/noto-fonts/releases/download/NotoSans-v2.013/NotoSans-v2.013.zip"
    # 2 link bên dưới dễ 404 theo tag; nếu fail vẫn tiếp tục
    "NotoSymbols"   = "https://raw.githubusercontent.com/googlefonts/noto-fonts/main/hinted/ttf/NotoSymbols/NotoSymbols-Regular.ttf"
    "NotoSansMath"  = "https://raw.githubusercontent.com/googlefonts/noto-fonts/main/hinted/ttf/NotoSansMath/NotoSansMath-Regular.ttf"
    "NotoColorEmoji"= "https://raw.githubusercontent.com/googlefonts/noto-emoji/main/fonts/NotoColorEmoji.ttf"
  };
  CJK = @{
    "NotoSansCJKjp-Regular" = "https://raw.githubusercontent.com/googlefonts/noto-cjk/main/Sans/OTF/Japanese/NotoSansCJKjp-Regular.otf"
    "NotoSansCJKsc-Regular" = "https://raw.githubusercontent.com/googlefonts/noto-cjk/main/Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf"
    "NotoSansCJKkr-Regular" = "https://raw.githubusercontent.com/googlefonts/noto-cjk/main/Sans/OTF/Korean/NotoSansCJKkr-Regular.otf"
  };
  Specialty = @{
    "FiraCode"      = "https://github.com/tonsky/FiraCode/releases/download/6.2/Fira_Code_v6.2.zip"
    "CascadiaCode"  = "https://github.com/microsoft/cascadia-code/releases/download/v2111.01/CascadiaCode-2111.01.zip"
    "Inconsolata"   = "https://github.com/googlefonts/Inconsolata/releases/download/v3.000/fonts_ttf.zip"
  }
}

# ===== Helpers =====
function Download-File {
  param([string]$Url,[string]$OutFile,[int]$MaxRetry=3,[int]$TimeoutSec=300)
  for ($i=1; $i -le $MaxRetry; $i++) {
    try {
      Write-Log ("Download attempt {0}: {1}" -f $i,$Url)
      if ($PSVersionTable.PSVersion.Major -ge 7) {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -TimeoutSec $TimeoutSec
      } else {
        try { Start-BitsTransfer -Source $Url -Destination $OutFile -DisplayName "FontDL" -Description "Downloading $([IO.Path]::GetFileName($OutFile))" -ErrorAction Stop }
        catch { Invoke-WebRequest -Uri $Url -OutFile $OutFile }
      }
      if ((Test-Path $OutFile) -and ((Get-Item $OutFile).Length -gt 1000)) {
        Write-Log ("Download OK: {0}" -f $OutFile); return $true
      }
    } catch { Write-Log ("Download error: {0}" -f $_.Exception.Message) "ERROR" }
    Start-Sleep -Seconds ([Math]::Min(2*$i,10))
  }
  Write-Log ("Download failed after {0} tries: {1}" -f $MaxRetry,$Url) "ERROR"
  return $false
}

function Get-CurrentFonts {
  try {
    $fonts=@(); $reg="HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
    $props=(Get-ItemProperty $reg -ErrorAction SilentlyContinue).PSObject.Properties |
      Where-Object { $_.Name -and $_.Name -notmatch '^PS' -and $_.Value }
    foreach ($p in $props) { $fonts += ($p.Name -replace ' \(TrueType\)$','' -replace ' \(OpenType\)$','') }
    $fonts | Sort-Object | Select-Object -Unique
  } catch { Write-Log ("Get-CurrentFonts error: {0}" -f $_.Exception.Message) "ERROR"; @() }
}

function Get-FontInventoryHash {
  $reg="HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
  try {
    $rows=@()
    $props=(Get-ItemProperty $reg -ErrorAction SilentlyContinue).PSObject.Properties |
      Where-Object { $_.Name -and $_.Name -notmatch '^PS' -and $_.Value }
    foreach ($p in $props) {
      $file=Join-Path $env:SystemRoot\Fonts $p.Value
      $size=0; if (Test-Path $file) { $size=(Get-Item $file).Length }
      $rows+=("$($p.Name)|$($p.Value)|$size")
    }
    $bytes=[Text.Encoding]::UTF8.GetBytes((($rows|Sort-Object) -join "`n"))
    $h=[BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($bytes)) -replace '-',''
    Write-Log ("InventoryHash computed: {0}" -f (Head32 $h)); $h
  } catch { Write-Log ("Get-FontInventoryHash error: {0}" -f $_.Exception.Message) "ERROR"; "NA" }
}

# FallbackHash = SystemLink + FontSubstitutes (HKLM + HKCU)
function Get-FallbackHash {
  try {
    $bases=@("Segoe UI","Segoe UI Variable","Segoe UI Symbol","Segoe UI Emoji","Arial","Times New Roman","Courier New","Calibri","Cambria","Consolas","Microsoft Sans Serif","Tahoma","MS Shell Dlg","MS Shell Dlg 2")
    $sysHKLM='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontLink\SystemLink'
    $sysHKCU='HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontLink\SystemLink'
    $subHKLM='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes'
    $subHKCU='HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes'
    $rows=@()
    foreach($h in @($sysHKLM,$sysHKCU)){
      foreach($b in $bases){
        $v=(Get-ItemProperty -Path $h -Name $b -ErrorAction SilentlyContinue).$b
        if ($v) { $rows+=("SYS[$h]:$b=" + ($v -join ";")) }
      }
    }
    foreach($h in @($subHKLM,$subHKCU)){
      foreach($b in @("Segoe UI","Microsoft Sans Serif","Tahoma","MS Shell Dlg","MS Shell Dlg 2","Arial","Times New Roman","Courier New","Segoe UI Symbol","Cambria Math","Segoe UI Emoji")){
        $v=(Get-ItemProperty -Path $h -Name $b -ErrorAction SilentlyContinue).$b
        if ($v) { $rows+=("SUB[$h]:$b=$v") }
      }
    }
    $bytes=[Text.Encoding]::UTF8.GetBytes(($rows -join "`n"))
    $h=[BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($bytes)) -replace '-',''
    Write-Log ("FallbackHash computed: {0}" -f (Head32 $h)); $h
  } catch { Write-Log ("Get-FallbackHash error: {0}" -f $_.Exception.Message) "ERROR"; "NA" }
}

function Get-FontFaceName { param([string]$FilePath)
  try {
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    $pfc=New-Object System.Drawing.Text.PrivateFontCollection
    $pfc.AddFontFile($FilePath)
    if ($pfc.Families.Count -gt 0) { return $pfc.Families[0].Name }
  } catch { Write-Log ("Get-FontFaceName error: {0}" -f $_.Exception.Message) "ERROR" }
  [IO.Path]::GetFileNameWithoutExtension($FilePath)
}

function Install-SingleFontFile { param([string]$FilePath,[string]$FallbackName="CustomFont")
  try {
    $fontFile=Get-Item $FilePath; $dest=Join-Path $FontsDir $fontFile.Name
    if (Test-Path $dest) { Write-Status "Exists: $($fontFile.Name)" "Gray"; return $null }
    Copy-Item -Path $FilePath -Destination $dest -Force
    $ext=$fontFile.Extension.ToLower(); $type= if ($ext -eq ".ttf" -or $ext -eq ".ttc") {"TrueType"} else {"OpenType"}
    $face= if ($ext -ne ".ttc") { Get-FontFaceName $dest } else { $FallbackName }
    $reg="HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"; $key="$face ($type)"
    try { Set-ItemProperty -Path $reg -Name $key -Value $fontFile.Name -ErrorAction Stop }
    catch { New-ItemProperty -Path $reg -Name $key -Value $fontFile.Name -PropertyType String -Force | Out-Null }
    Write-Status ("Installed: {0} -> {1}" -f $face,$fontFile.Name) "Green"
    @{ Face=$face; File=$fontFile.Name }
  } catch { Write-Status ("Install error: {0}" -f $_.Exception.Message) "Red" "ERROR"; $null }
}

function Install-FromUrl { param([string]$Name,[string]$Url)
  try {
    $lower=$Url.ToLower()
    if ($lower.EndsWith(".ttf") -or $lower.EndsWith(".otf")) {
      $out=Join-Path $TempDir ([IO.Path]::GetFileName($Url))
      if (-not (Download-File -Url $Url -OutFile $out)) { Write-Status ("Download failed: {0}" -f $Name) "Red" "ERROR"; return @() }
      $r=Install-SingleFontFile -FilePath $out -FallbackName $Name; if ($r -ne $null){@($r)}else{@()}
    } elseif ($lower.EndsWith(".zip")) {
      $zip=Join-Path $TempDir "$Name.zip"
      if (-not (Download-File -Url $Url -OutFile $zip)) { Write-Status ("Download failed: {0}" -f $Name) "Red" "ERROR"; return @() }
      $extract=Join-Path $TempDir ("ex_" + $Name); if (Test-Path $extract){ Remove-Item $extract -Recurse -Force -ErrorAction SilentlyContinue }
      try { Expand-Archive -Path $zip -DestinationPath $extract -Force } catch { Write-Status ("Unzip error {0}: {1}" -f $Name,$_.Exception.Message) "Red" "ERROR"; return @() }
      $picked = Get-ChildItem -Path $extract -Recurse -Include *.ttf,*.otf |
        Where-Object { $_.Name -notmatch "italic|oblique|thin|hairline" } |
        Sort-Object { if($_.Name -match "regular|normal"){0}elseif($_.Name -match "medium"){1}elseif($_.Name -match "bold"){2}else{3} } |
        Select-Object -First 3
      $installed=@(); foreach($f in $picked){ $x=Install-SingleFontFile -FilePath $f.FullName -FallbackName $Name; if ($x -ne $null){ $installed+=$x } }
      $installed
    } else {
      Write-Status ("Unsupported URL type: {0}" -f $Url) "Yellow" "WARN"; @()
    }
  } catch { Write-Status ("Install-FromUrl error: {0}" -f $_.Exception.Message) "Red" "ERROR"; @() }
}

function Get-FaceToFileMap {
  $map=@{}; $reg="HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
  try {
    (Get-ItemProperty $reg -ErrorAction SilentlyContinue).PSObject.Properties |
      Where-Object { $_.Name -and $_.Name -notmatch '^PS' -and $_.Value } |
      ForEach-Object { $map[($_.Name -replace ' \(TrueType\)$','' -replace ' \(OpenType\)$','')] = $_.Value }
  } catch { Write-Log ("Get-FaceToFileMap error: {0}" -f $_.Exception.Message) "ERROR" }
  $map
}

# SystemLink HKLM+HKCU
function Prepend-FontLink {
  param([string]$BaseFamily,[string[]]$Pairs)
  foreach($root in @('HKLM','HKCU')){
    $key="$root`:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontLink\SystemLink"
    try {
      $cur=(Get-ItemProperty -Path $key -Name $BaseFamily -ErrorAction SilentlyContinue).$BaseFamily
      if (-not $cur) { $cur=@() }
      $new = ($Pairs + $cur) | Select-Object -Unique
      New-ItemProperty -Path $key -Name $BaseFamily -Value $new -PropertyType MultiString -Force | Out-Null
      Write-Log ("SystemLink prepend [{0}] ({1}) <= {2}" -f $BaseFamily,$root,($Pairs -join ' | '))
    } catch { Write-Status ("Prepend-FontLink error ({0}/{1}): {2}" -f $BaseFamily,$root,$_.Exception.Message) "Red" "ERROR" }
  }
}

# FontSubstitutes HKLM+HKCU
function Set-FontSubstitute {
  param([string]$From,[string]$To)
  if ([string]::IsNullOrWhiteSpace($From) -or [string]::IsNullOrWhiteSpace($To)) { return }
  foreach($root in @('HKLM','HKCU')){
    $key="$root`:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes"
    try {
      try { Set-ItemProperty -Path $key -Name $From -Value $To -ErrorAction Stop }
      catch { New-ItemProperty -Path $key -Name $From -Value $To -PropertyType String -Force | Out-Null }
      Write-Status ("Substitute({2}): {0} -> {1}" -f $From,$To,$root) "Yellow"
    } catch { Write-Status ("Set-FontSubstitute error ({0}->{1}/{2}): {3}" -f $From,$To,$root,$_.Exception.Message) "Red" "ERROR" }
  }
}

function Refresh-Fonts {
  try { Stop-Service FontCache -Force -ErrorAction SilentlyContinue; Start-Sleep 1; Remove-Item "$env:LOCALAPPDATA\FontCache\*" -Force -ErrorAction SilentlyContinue } catch { Write-Log ("FontCache cleanup warn: {0}" -f $_.Exception.Message) "WARN" }
  try { Start-Service FontCache -ErrorAction SilentlyContinue } catch {}
  try {
    Add-Type -Namespace Win32 -Name U -MemberDefinition '[DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h,uint m,IntPtr w,IntPtr l,uint f,uint t,out IntPtr r);'
    [void][Win32.U]::SendMessageTimeout([IntPtr]0xffff,0x1D,[IntPtr]0,[IntPtr]0,2,1000,[ref]([IntPtr]::Zero))
  } catch { Write-Log ("Broadcast WM_FONTCHANGE warn: {0}" -f $_.Exception.Message) "WARN" }
}

function Pick-RandomFonts {
  param([int]$Count=6)
  $picked=@()
  $w = ($FontDB.Western.GetEnumerator() | Get-Random -Count 1); $picked += ,@{ Name=$w.Name; Url=$w.Value }
  $u = ($FontDB.Unicode.GetEnumerator() | Get-Random -Count 1); $picked += ,@{ Name=$u.Name; Url=$u.Value }
  $cjk = ( @("NotoSansCJKjp-Regular","NotoSansCJKsc-Regular","NotoSansCJKkr-Regular") | Get-Random -Count 1 )[0]
  $picked += ,@{ Name=$cjk; Url=$FontDB.CJK[$cjk] }
  $pool=@()
  foreach($k in $FontDB.Specialty.Keys){ $pool += ,@{ Name=$k; Url=$FontDB.Specialty[$k] } }
  foreach($k in $FontDB.Unicode.Keys){ if ($k -ne $u.Name) { $pool += ,@{ Name=$k; Url=$FontDB.Unicode[$k] } } }
  foreach($k in $FontDB.Western.Keys){ if ($k -ne $w.Name) { $pool += ,@{ Name=$k; Url=$FontDB.Western[$k] } } }
  $remain=[Math]::Max(0, $Count - $picked.Count)
  if ($remain -gt 0) { $picked += ($pool | Get-Random -Count ([Math]::Min($remain,$pool.Count))) }
  $picked
}

function Find-PairByFacePriority {
  param([string[]]$FacePriority,[hashtable]$FaceToFileMap)
  foreach($f in $FacePriority){ foreach($k in $FaceToFileMap.Keys){ if ($k -eq $f -or $k -like ($f + "*")) { $file=$FaceToFileMap[$k]; if ($file -and (Test-Path (Join-Path $FontsDir $file))) { return "$file,$k" } } } }
  $null
}

# ======================= MAIN =======================

Clear-Host
Write-Host "==============================================================" -ForegroundColor Green
Write-Host "   ADVANCED FONT FINGERPRINT ROTATOR v3.5 (PS 5.x SAFE)" -ForegroundColor Yellow
Write-Host "==============================================================" -ForegroundColor Green
Write-Log ("OS: {0}  PS: {1}" -f ([Environment]::OSVersion.VersionString), $PSVersionTable.PSVersion)

# Baseline
$beforeList = Get-CurrentFonts
$beforeInv  = Get-FontInventoryHash
$beforeFall = Get-FallbackHash
Write-Status ("Current fonts: {0}" -f $beforeList.Count) "Cyan"
Write-Status ("Inventory Hash: {0}..." -f (Head32 $beforeInv)) "Cyan"
Write-Status ("FallbackHash : {0}..." -f (Head32 $beforeFall)) "Cyan"

# 1) Random install
$targetCount = Get-Random -Minimum 5 -Maximum 9
Write-Host "`n[1/3] Download & install random fonts ($targetCount)..." -ForegroundColor Yellow
$wish = Pick-RandomFonts -Count $targetCount
foreach($item in $wish){ $null = Install-FromUrl -Name $item.Name -Url $item.Url }
foreach($core in @("NotoSymbols","NotoSansMath","NotoColorEmoji")){ if ($FontDB.Unicode[$core]) { $null = Install-FromUrl -Name $core -Url $FontDB.Unicode[$core] } }

# 2) Configure fallback + substitutes (HKLM+HKCU)
Write-Host "`n[2/3] Configure Unicode glyph override..." -ForegroundColor Yellow

# backup (1 lần/phiên)
$bk1="$TempDir\SystemLink_backup_HKLM.reg"; $bk2="$TempDir\FontSub_backup_HKLM.reg"
if (!(Test-Path $bk1)) { & reg export "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontLink\SystemLink" $bk1 /y | Out-Null }
if (!(Test-Path $bk2)) { & reg export "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" $bk2 /y | Out-Null }

$faceMap = Get-FaceToFileMap
$profiles=@("JP","SC","KR"); $profile = ($profiles | Get-Random -Count 1)[0]
Write-Status ("Profile chosen: {0}-first" -f $profile) "Magenta"

# Base pairs (CJK + Noto Sans)
$segBasePairs=@(); $segSymPairs=@(); $segEmojiPairs=@()
$jp=@("Noto Sans CJK JP","Noto Sans JP","Source Han Sans JP","NotoSansCJKjp")
$sc=@("Noto Sans CJK SC","Noto Sans SC","Source Han Sans SC","NotoSansCJKsc")
$kr=@("Malgun Gothic","Noto Sans CJK KR","Noto Sans KR","Source Han Sans KR","NotoSansCJKkr")
$p = if($profile -eq "JP"){$jp}elseif($profile -eq "SC"){$sc}else{$kr}
$cjkPair = Find-PairByFacePriority -FacePriority $p -FaceToFileMap $faceMap
if ($cjkPair -ne $null) { $segBasePairs += $cjkPair }
$nsPair = Find-PairByFacePriority -FacePriority @("Noto Sans","Inter") -FaceToFileMap $faceMap
if ($nsPair -ne $null) { $segBasePairs += $nsPair }

$nsym  = Find-PairByFacePriority -FacePriority @("Noto Symbols") -FaceToFileMap $faceMap
$nmath = Find-PairByFacePriority -FacePriority @("Noto Sans Math") -FaceToFileMap $faceMap
$nemoji= Find-PairByFacePriority -FacePriority @("Noto Color Emoji") -FaceToFileMap $faceMap
if ($nsym)  { $segSymPairs  += $nsym }
if ($nmath) { $segSymPairs  += $nmath }
if ($nemoji){ $segEmojiPairs+= $nemoji }

# SystemLink cho nhiều base families (HKLM+HKCU)
$baseFamilies = @("Segoe UI","Segoe UI Variable","Arial","Times New Roman","Courier New","Calibri","Cambria","Consolas","Microsoft Sans Serif","Tahoma","MS Shell Dlg","MS Shell Dlg 2")
foreach($bf in $baseFamilies){ if ($segBasePairs.Count -gt 0){ Prepend-FontLink -BaseFamily $bf -Pairs $segBasePairs } }
if ($segSymPairs.Count  -gt 0){ Prepend-FontLink -BaseFamily "Segoe UI Symbol" -Pairs $segSymPairs }
if ($segEmojiPairs.Count -gt 0){ Prepend-FontLink -BaseFamily "Segoe UI Emoji"  -Pairs $segEmojiPairs }

# Substitutes mạnh (HKLM+HKCU)
# Chọn đích
function Pick-FirstInstalled { param([string[]]$Prefer,[hashtable]$FaceMap)
  foreach($n in $Prefer){ foreach($k in $FaceMap.Keys){ if ($k -eq $n -or $k -like ($n + "*")) { return $k } } } $null
}
# Sans/CJK đích cho default UI
$cjkDest = Pick-FirstInstalled -Prefer @("Noto Sans CJK JP","Noto Sans CJK SC","Noto Sans CJK KR","Noto Sans","Inter") -FaceMap $faceMap
$sansDest= Pick-FirstInstalled -Prefer @("Noto Sans","Inter","Open Sans","Roboto","Ubuntu") -FaceMap $faceMap
$serifDest=Pick-FirstInstalled -Prefer @("Merriweather","Lora") -FaceMap $faceMap
$monoDest =Pick-FirstInstalled -Prefer @("Cascadia Mono","Cascadia Mono PL","Fira Code","Inconsolata","JetBrains Mono") -FaceMap $faceMap
$symbolDest=Pick-FirstInstalled -Prefer @("Noto Symbols","Noto Sans Math") -FaceMap $faceMap
$mathDest  =Pick-FirstInstalled -Prefer @("Noto Sans Math") -FaceMap $faceMap
$emojiDest =Pick-FirstInstalled -Prefer @("Noto Color Emoji") -FaceMap $faceMap

# Thay mặt mặc định & web generics
if ($cjkDest) {
  foreach($n in @("Segoe UI","Microsoft Sans Serif","Tahoma","MS Shell Dlg","MS Shell Dlg 2")) { Set-FontSubstitute -From $n -To $cjkDest }
}
if ($sansDest)  { Set-FontSubstitute -From "Arial"           -To $sansDest }
if ($serifDest) { Set-FontSubstitute -From "Times New Roman" -To $serifDest }
if ($monoDest)  { Set-FontSubstitute -From "Courier New"     -To $monoDest }
if ($symbolDest){ Set-FontSubstitute -From "Segoe UI Symbol" -To $symbolDest }
if ($mathDest)  { Set-FontSubstitute -From "Cambria Math"    -To $mathDest }
if ($emojiDest) { Set-FontSubstitute -From "Segoe UI Emoji"  -To $emojiDest }

# refresh caches & broadcast
Refresh-Fonts

# 3) Results
Write-Host "`n[3/3] Results & verification..." -ForegroundColor Yellow
$afterList = Get-CurrentFonts
$afterInv  = Get-FontInventoryHash
$afterFall = Get-FallbackHash

Write-Host "`n--- FONT METRICS (Registry list) ---" -ForegroundColor Cyan
Write-Host ("Count: {0} -> {1}  (Δ {2})" -f $beforeList.Count,$afterList.Count,($afterList.Count-$beforeList.Count)) -ForegroundColor Green

Write-Host "`n--- HASHES ---" -ForegroundColor Cyan
Write-Host ("Inventory:  {0} -> {1}" -f (Head32 $beforeInv),(Head32 $afterInv)) -ForegroundColor White
Write-Host ("Fallback :  {0} -> {1}" -f (Head32 $beforeFall),(Head32 $afterFall)) -ForegroundColor White

$changedInv  = ($beforeInv -ne $afterInv)
$changedFall = ($beforeFall -ne $afterFall)

Write-Status ("Font Metrics changed?   " + ($(if ($changedInv)  {"YES"} else {"NO"}))) ($(if ($changedInv)  {"Green"} else {"Red"}))
Write-Status ("Unicode Glyphs changed? " + ($(if ($changedFall) {"YES"} else {"NO"}))) ($(if ($changedFall) {"Green"} else {"Red"}))

try { Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue } catch {}
Write-Log "Run finished."
