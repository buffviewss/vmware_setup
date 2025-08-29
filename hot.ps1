<# ===================================================================
   ADVANCED FONT FINGERPRINT ROTATOR v3.4 (PowerShell 5.x SAFE)
   - Random cài thêm font (Google/Adobe/Microsoft/JetBrains…)
   - Ghi Registry đúng Face Name (TTF/OTF; TTC fallback)
   - Override Unicode glyphs thật (SystemLink + FontSubstitutes)
   - KHÔNG xoá font hệ thống. KHÔNG mở trình duyệt.
   - NEW: Logging -> %USERPROFILE%\Downloads\log.txt (append)
=================================================================== #>

# ===== Admin check =====
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "ERROR: Please run PowerShell as Administrator!" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# ===== Logging =====
$DownloadDir = Join-Path $env:USERPROFILE 'Downloads'
if (!(Test-Path $DownloadDir)) { New-Item -ItemType Directory -Path $DownloadDir -Force | Out-Null }
$LogFile = Join-Path $DownloadDir 'log.txt'
$RunStamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
Add-Content -Path $LogFile -Value ("`n=== RUN {0} ===" -f $RunStamp)

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    try {
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $line = "[{0}] [{1}] {2}" -f $ts, $Level, $Message
        Add-Content -Path $LogFile -Value $line
    } catch { }  # logging should never throw
}

function Write-Status {
    param([string]$m,[string]$c="Cyan",[string]$lvl="INFO")
    $ts=Get-Date -Format "HH:mm:ss"
    Write-Host "[$ts] $m" -ForegroundColor $c
    Write-Log -Message $m -Level $lvl
}

# ===== Globals =====
$TempDir  = "$env:TEMP\FontRotator"
$FontsDir = "$env:SystemRoot\Fonts"
if (!(Test-Path $TempDir)) { New-Item -ItemType Directory -Path $TempDir -Force | Out-Null }

function Head32 {
    param($s)
    if ($s -and $s.Length -ge 32) { return $s.Substring(0,32) }
    elseif ($s) { return $s } else { return "NA" }
}

# ===== Trusted sources =====
$FontDB = @{
  Western = @{
    "Inter"         = "https://github.com/rsms/inter/releases/download/v3.19/Inter-3.19.zip"
    "JetBrainsMono" = "https://github.com/JetBrains/JetBrainsMono/releases/download/v2.304/JetBrainsMono-2.304.zip"
    "Roboto"        = "https://github.com/googlefonts/roboto/releases/download/v2.138/roboto-unhinted.zip"
    "Ubuntu"        = "https://github.com/googlefonts/ubuntu/releases/download/v0.83/ubuntu-font-family-0.83.zip"
    "OpenSans"      = "https://github.com/googlefonts/opensans/releases/download/v3.000/opensans.zip"
    "PT-Sans"       = "https://github.com/googlefonts/pt-sans/releases/download/v1.005/PT_Sans.zip"
    "Merriweather"  = "https://github.com/SorkinType/Merriweather/releases/download/v1.582/Merriweather-v1.582.zip"
    "Lora"          = "https://github.com/cyrealtype/Lora-Cyrillic/releases/download/2.101/Lora_Fonts.zip"
  };
  Unicode = @{
    "NotoSans"      = "https://github.com/googlefonts/noto-fonts/releases/download/NotoSans-v2.013/NotoSans-v2.013.zip"
    "NotoSymbols"   = "https://github.com/googlefonts/noto-fonts/raw/main/hinted/ttf/NotoSymbols/NotoSymbols-Regular.ttf"
    "NotoSansMath"  = "https://github.com/googlefonts/noto-fonts/raw/main/hinted/ttf/NotoSansMath/NotoSansMath-Regular.ttf"
    "NotoColorEmoji"= "https://github.com/googlefonts/noto-emoji/releases/download/v2.042/NotoColorEmoji.ttf"
  };
  CJK = @{
    "NotoSansCJKjp-Regular" = "https://github.com/googlefonts/noto-cjk/raw/main/Sans/OTF/Japanese/NotoSansCJKjp-Regular.otf"
    "NotoSansCJKsc-Regular" = "https://github.com/googlefonts/noto-cjk/raw/main/Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf"
    "NotoSansCJKkr-Regular" = "https://github.com/googlefonts/noto-cjk/raw/main/Sans/OTF/Korean/NotoSansCJKkr-Regular.otf"
    "NotoSansCJK-OTC"       = "https://github.com/googlefonts/noto-cjk/releases/download/Sans2.004/04_NotoSansCJK-OTC.zip"
    "SourceHanSans-OTC"     = "https://github.com/adobe-fonts/source-han-sans/releases/download/2.004R/SourceHanSans.ttc"
  };
  Specialty = @{
    "FiraCode"      = "https://github.com/tonsky/FiraCode/releases/download/6.2/Fira_Code_v6.2.zip"
    "CascadiaCode"  = "https://github.com/microsoft/cascadia-code/releases/download/v2111.01/CascadiaCode-2111.01.zip"
    "VictorMono"    = "https://github.com/rubjo/victor-mono/releases/download/v1.5.4/VictorMonoAll.zip"
    "Inconsolata"   = "https://github.com/googlefonts/Inconsolata/releases/download/v3.000/fonts_ttf.zip"
    "DejaVu"        = "https://github.com/dejavu-fonts/dejavu-fonts/releases/download/version_2_37/dejavu-fonts-ttf-2.37.zip"
  }
}

# ===== Helpers =====
function Download-File {
  param([string]$Url,[string]$OutFile,[int]$MaxRetry=3,[int]$TimeoutSec=300)
  for ($i=1; $i -le $MaxRetry; $i++) {
    try {
      Write-Log -Message ("Download attempt {0}: {1}" -f $i,$Url)
      if ($PSVersionTable.PSVersion.Major -ge 7) {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -TimeoutSec $TimeoutSec
      } else {
        try { Start-BitsTransfer -Source $Url -Destination $OutFile -DisplayName "FontDL" -Description "Downloading $([IO.Path]::GetFileName($OutFile))" -ErrorAction Stop }
        catch { Invoke-WebRequest -Uri $Url -OutFile $OutFile }
      }
      if ((Test-Path $OutFile) -and ((Get-Item $OutFile).Length -gt 1000)) {
        Write-Log -Message ("Download OK: {0}" -f $OutFile)
        return $true
      }
    } catch {
      Write-Log -Message ("Download error: {0}" -f $_.Exception.Message) -Level "ERROR"
    }
    Start-Sleep -Seconds ([Math]::Min(2*$i,10))
  }
  Write-Log -Message ("Download failed after {0} tries: {1}" -f $MaxRetry,$Url) -Level "ERROR"
  return $false
}

function Get-CurrentFonts {
  try {
    $fonts=@(); $reg="HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
    $props=(Get-ItemProperty $reg -ErrorAction SilentlyContinue).PSObject.Properties |
      Where-Object { $_.Name -and $_.Name -notmatch '^PS' -and $_.Value }
    foreach ($p in $props) {
      $name=$p.Name -replace ' \(TrueType\)$','' -replace ' \(OpenType\)$',''
      $fonts+=$name
    }
    return $fonts | Sort-Object | Select-Object -Unique
  } catch {
    Write-Log -Message ("Get-CurrentFonts error: {0}" -f $_.Exception.Message) -Level "ERROR"
    return @()
  }
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
    $rows=$rows | Sort-Object
    $bytes=[Text.Encoding]::UTF8.GetBytes(($rows -join "`n"))
    $hash=[Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
    $h = ([BitConverter]::ToString($hash) -replace '-','')
    Write-Log -Message ("InventoryHash computed: {0}" -f (Head32 $h))
    return $h
  } catch {
    Write-Log -Message ("Get-FontInventoryHash error: {0}" -f $_.Exception.Message) -Level "ERROR"
    return "NA"
  }
}

# Fallback hash = SystemLink (nhiều base families) + FontSubstitutes (mục ta đụng vào)
function Get-FallbackHash {
  try {
    $sysKey='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontLink\SystemLink'
    $subKey='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes'
    $bases=@("Segoe UI","Segoe UI Symbol","Segoe UI Emoji","Arial","Times New Roman","Courier New","Calibri","Cambria","Consolas")
    $rows=@()
    foreach($b in $bases){
      $v=(Get-ItemProperty -Path $sysKey -Name $b -ErrorAction SilentlyContinue).$b
      if ($v) { $rows+=("SYS:$b=" + ($v -join ";")) } else { $rows+=("SYS:$b=") }
    }
    foreach($name in @("Arial","Times New Roman","Courier New","Segoe UI Symbol","Cambria Math","Segoe UI Emoji")){
      $vv=(Get-ItemProperty -Path $subKey -Name $name -ErrorAction SilentlyContinue).$name
      if ($vv) { $rows+=("SUB:$name=$vv") } else { $rows+=("SUB:$name=") }
    }
    $bytes=[Text.Encoding]::UTF8.GetBytes(($rows -join "`n"))
    $hash=[Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
    $h = ([BitConverter]::ToString($hash) -replace '-','')
    Write-Log -Message ("FallbackHash computed: {0}" -f (Head32 $h))
    return $h
  } catch {
    Write-Log -Message ("Get-FallbackHash error: {0}" -f $_.Exception.Message) -Level "ERROR"
    return "NA"
  }
}

function Get-FontFaceName { param([string]$FilePath)
  try {
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    $pfc=New-Object System.Drawing.Text.PrivateFontCollection
    $pfc.AddFontFile($FilePath)
    if ($pfc.Families.Count -gt 0) { return $pfc.Families[0].Name }
  } catch {
    Write-Log -Message ("Get-FontFaceName error: {0}" -f $_.Exception.Message) -Level "ERROR"
  }
  return [IO.Path]::GetFileNameWithoutExtension($FilePath)
}

function Install-SingleFontFile { param([string]$FilePath,[string]$FallbackName="CustomFont")
  try {
    $fontFile=Get-Item $FilePath
    $dest=Join-Path $FontsDir $fontFile.Name
    if (Test-Path $dest) { Write-Status "Exists: $($fontFile.Name)" "Gray"; return $null }
    Copy-Item -Path $FilePath -Destination $dest -Force

    $ext=$fontFile.Extension.ToLower()
    $type= if ($ext -eq ".ttf" -or $ext -eq ".ttc") { "TrueType" } else { "OpenType" }
    $face= if ($ext -ne ".ttc") { Get-FontFaceName $dest } else { $FallbackName }

    $reg="HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
    $key="$face ($type)"
    try { Set-ItemProperty -Path $reg -Name $key -Value $fontFile.Name -ErrorAction Stop }
    catch { New-ItemProperty -Path $reg -Name $key -Value $fontFile.Name -PropertyType String -Force | Out-Null }

    Write-Status ("Installed: {0} -> {1}" -f $face,$fontFile.Name) "Green"
    return @{ Face=$face; File=$fontFile.Name }
  } catch {
    Write-Status ("Install error: {0}" -f $_.Exception.Message) "Red" "ERROR"
    return $null
  }
}

function Install-FromUrl { param([string]$Name,[string]$Url)
  try {
    $lower=$Url.ToLower()
    if ($lower.EndsWith(".ttf") -or $lower.EndsWith(".otf") -or $lower.EndsWith(".ttc")) {
      $out=Join-Path $TempDir ([IO.Path]::GetFileName($Url))
      if (-not (Download-File -Url $Url -OutFile $out)) { Write-Status ("Download failed: {0}" -f $Name) "Red" "ERROR"; return @() }
      $r = Install-SingleFontFile -FilePath $out -FallbackName $Name
      if ($r -ne $null) { return @($r) } else { return @() }
    }
    if ($lower.EndsWith(".zip")) {
      $zip=Join-Path $TempDir "$Name.zip"
      if (-not (Download-File -Url $Url -OutFile $zip)) { Write-Status ("Download failed: {0}" -f $Name) "Red" "ERROR"; return @() }
      $extract=Join-Path $TempDir ("ex_" + $Name)
      if (Test-Path $extract){ Remove-Item $extract -Recurse -Force -ErrorAction SilentlyContinue }
      try { Expand-Archive -Path $zip -DestinationPath $extract -Force } catch { Write-Status ("Unzip error {0}: {1}" -f $Name,$_.Exception.Message) "Red" "ERROR"; return @() }
      $picked = Get-ChildItem -Path $extract -Recurse -Include *.ttf,*.otf,*.ttc |
        Where-Object { $_.Name -notmatch "italic|oblique|thin|hairline" } |
        Sort-Object {
          if ($_.Name -match "regular|normal") { 0 }
          elseif ($_.Name -match "medium") { 1 }
          elseif ($_.Name -match "bold") { 2 }
          else { 3 }
        } | Select-Object -First 3
      $installed=@()
      foreach($f in $picked){ $x=Install-SingleFontFile -FilePath $f.FullName -FallbackName $Name; if ($x -ne $null){ $installed+=$x } }
      return $installed
    }
    Write-Status ("Unsupported URL type: {0}" -f $Url) "Yellow" "WARN"
    return @()
  } catch {
    Write-Status ("Install-FromUrl error: {0}" -f $_.Exception.Message) "Red" "ERROR"
    return @()
  }
}

function Get-FaceToFileMap {
  $map=@{}
  $reg="HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
  try {
    $props=(Get-ItemProperty $reg -ErrorAction SilentlyContinue).PSObject.Properties |
      Where-Object { $_.Name -and $_.Name -notmatch '^PS' -and $_.Value }
    foreach($p in $props){
      $face=($p.Name -replace ' \(TrueType\)$','' -replace ' \(OpenType\)$','')
      $map[$face] = $p.Value
    }
  } catch {
    Write-Log -Message ("Get-FaceToFileMap error: {0}" -f $_.Exception.Message) -Level "ERROR"
  }
  return $map
}

function Prepend-FontLink {
  param([string]$BaseFamily,[string[]]$Pairs)
  $key='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontLink\SystemLink'
  try {
    $cur=(Get-ItemProperty -Path $key -Name $BaseFamily -ErrorAction SilentlyContinue).$BaseFamily
    if (-not $cur) { $cur=@() }
    $new = ($Pairs + $cur) | Select-Object -Unique
    New-ItemProperty -Path $key -Name $BaseFamily -Value $new -PropertyType MultiString -Force | Out-Null
    Write-Log -Message ("SystemLink prepend [{0}] <= {1}" -f $BaseFamily,($Pairs -join ' | '))
  } catch {
    Write-Status ("Prepend-FontLink error ({0}): {1}" -f $BaseFamily,$_.Exception.Message) "Red" "ERROR"
  }
}

function Set-FontSubstitute {
  param([string]$From,[string]$To)
  $key='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes'
  if ([string]::IsNullOrWhiteSpace($From) -or [string]::IsNullOrWhiteSpace($To)) { return }
  try {
    try { Set-ItemProperty -Path $key -Name $From -Value $To -ErrorAction Stop }
    catch { New-ItemProperty -Path $key -Name $From -Value $To -PropertyType String -Force | Out-Null }
    Write-Status ("Substitute: {0} -> {1}" -f $From,$To) "Yellow"
  } catch {
    Write-Status ("Set-FontSubstitute error ({0}->{1}): {2}" -f $From,$To,$_.Exception.Message) "Red" "ERROR"
  }
}

function Refresh-Fonts {
  try {
    Stop-Service FontCache -Force -ErrorAction SilentlyContinue
    Start-Sleep 1
    Remove-Item "$env:LOCALAPPDATA\FontCache\*" -Force -ErrorAction SilentlyContinue
  } catch { Write-Log -Message ("FontCache cleanup warn: {0}" -f $_.Exception.Message) -Level "WARN" }
  try { Start-Service FontCache -ErrorAction SilentlyContinue } catch {}
  try {
    Add-Type -Namespace Win32 -Name U -MemberDefinition '[DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h,uint m,IntPtr w,IntPtr l,uint f,uint t,out IntPtr r);'
    [void][Win32.U]::SendMessageTimeout([IntPtr]0xffff,0x1D,[IntPtr]0,[IntPtr]0,2,1000,[ref]([IntPtr]::Zero))
  } catch { Write-Log -Message ("Broadcast WM_FONTCHANGE warn: {0}" -f $_.Exception.Message) -Level "WARN" }
}

function Pick-RandomFonts {
  param([int]$Count=6)
  $picked=@()
  $w = ($FontDB.Western.GetEnumerator() | Get-Random -Count 1)
  $picked += ,@{ Name=$w.Name; Url=$w.Value }
  $u = ($FontDB.Unicode.GetEnumerator() | Get-Random -Count 1)
  $picked += ,@{ Name=$u.Name; Url=$u.Value }
  $cjkKeys = @("NotoSansCJKjp-Regular","NotoSansCJKsc-Regular","NotoSansCJKkr-Regular")
  $c = ($cjkKeys | Get-Random -Count 1)[0]
  $picked += ,@{ Name=$c; Url=$FontDB.CJK[$c] }
  $pool=@()
  foreach($k in $FontDB.Specialty.Keys){ $pool += ,@{ Name=$k; Url=$FontDB.Specialty[$k] } }
  foreach($k in $FontDB.Unicode.Keys){ if ($k -ne $u.Name) { $pool += ,@{ Name=$k; Url=$FontDB.Unicode[$k] } } }
  foreach($k in $FontDB.Western.Keys){ if ($k -ne $w.Name) { $pool += ,@{ Name=$k; Url=$FontDB.Western[$k] } } }
  $remain=[Math]::Max(0, $Count - $picked.Count)
  if ($remain -gt 0) {
    $extra = $pool | Get-Random -Count ([Math]::Min($remain, $pool.Count))
    $picked += $extra
  }
  return $picked
}

function Find-PairByFacePriority {
  param([string[]]$FacePriority,[hashtable]$FaceToFileMap)
  foreach($f in $FacePriority){
    foreach($k in $FaceToFileMap.Keys){
      if ($k -eq $f -or $k -like ($f + "*")) {
        $file=$FaceToFileMap[$k]
        if ($file -and (Test-Path (Join-Path $FontsDir $file))) { return "$file,$k" }
      }
    }
  }
  return $null
}

# ======================= MAIN =======================

Clear-Host
Write-Host "==============================================================" -ForegroundColor Green
Write-Host "   ADVANCED FONT FINGERPRINT ROTATOR v3.4 (PS 5.x SAFE)" -ForegroundColor Yellow
Write-Host "==============================================================" -ForegroundColor Green

Write-Log -Message ("OS: {0}  PS: {1}" -f ([Environment]::OSVersion.VersionString), $PSVersionTable.PSVersion)

# Baseline
$beforeList   = Get-CurrentFonts
$beforeInv    = Get-FontInventoryHash
$beforeFall   = Get-FallbackHash

Write-Status ("Current fonts: {0}" -f $beforeList.Count) "Cyan"
Write-Status ("Inventory Hash: {0}..." -f (Head32 $beforeInv)) "Cyan"
Write-Status ("FallbackHash : {0}..." -f (Head32 $beforeFall)) "Cyan"

# 1) Random install 5..8 fonts
$targetCount = Get-Random -Minimum 5 -Maximum 9
Write-Host "`n[1/3] Download & install random fonts ($targetCount)..." -ForegroundColor Yellow
$wish = Pick-RandomFonts -Count $targetCount
foreach($item in $wish){ $null = Install-FromUrl -Name $item.Name -Url $item.Url }
foreach($core in @("NotoSymbols","NotoSansMath","NotoColorEmoji")){ if ($FontDB.Unicode[$core]) { $null = Install-FromUrl -Name $core -Url $FontDB.Unicode[$core] } }

# 2) Configure fallback + substitutes
Write-Host "`n[2/3] Configure Unicode glyph override (SystemLink + Substitutes)..." -ForegroundColor Yellow

# backup once
$bk1="$TempDir\SystemLink_backup.reg"; $bk2="$TempDir\FontSub_backup.reg"
if (!(Test-Path $bk1)) { & reg export "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontLink\SystemLink" $bk1 /y | Out-Null }
if (!(Test-Path $bk2)) { & reg export "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" $bk2 /y | Out-Null }

$faceMap = Get-FaceToFileMap
$profiles=@("JP","SC","KR")
$profile = ($profiles | Get-Random -Count 1)[0]
Write-Status ("Profile chosen: {0}-first" -f $profile) "Magenta"

$segBasePairs=@(); $segSymPairs=@(); $segEmojiPairs=@()
$jpCandidates = @("Yu Gothic UI","Meiryo UI","MS Gothic","Noto Sans CJK JP","Noto Sans JP","Source Han Sans JP","NotoSansCJKjp")
$scCandidates = @("Microsoft YaHei UI","SimSun","NSimSun","Noto Sans CJK SC","Noto Sans SC","Source Han Sans SC","NotoSansCJKsc")
$krCandidates = @("Malgun Gothic","MalgunGothic","Noto Sans CJK KR","Noto Sans KR","Source Han Sans KR","NotoSansCJKkr")
if ($profile -eq "JP") { $p=$jpCandidates } elseif ($profile -eq "SC") { $p=$scCandidates } else { $p=$krCandidates }

$cjkPair = Find-PairByFacePriority -FacePriority $p -FaceToFileMap $faceMap
if ($cjkPair -eq $null) {
  if ($profile -eq "JP") { $null = Install-FromUrl -Name "NotoSansCJKjp-Regular" -Url $FontDB.CJK["NotoSansCJKjp-Regular"] }
  elseif ($profile -eq "SC") { $null = Install-FromUrl -Name "NotoSansCJKsc-Regular" -Url $FontDB.CJK["NotoSansCJKsc-Regular"] }
  else { $null = Install-FromUrl -Name "NotoSansCJKkr-Regular" -Url $FontDB.CJK["NotoSansCJKkr-Regular"] }
  $faceMap = Get-FaceToFileMap
  $cjkPair = Find-PairByFacePriority -FacePriority $p -FaceToFileMap $faceMap
}
if ($cjkPair -ne $null) { $segBasePairs += $cjkPair }

$nsPair = Find-PairByFacePriority -FacePriority @("Noto Sans") -FaceToFileMap $faceMap
if ($nsPair -ne $null) { $segBasePairs += $nsPair }

$nsym  = Find-PairByFacePriority -FacePriority @("Noto Symbols") -FaceToFileMap $faceMap
$nmath = Find-PairByFacePriority -FacePriority @("Noto Sans Math") -FaceToFileMap $faceMap
if ($nsym  -ne $null) { $segSymPairs  += $nsym  }
if ($nmath -ne $null) { $segSymPairs  += $nmath }
$nemoji = Find-PairByFacePriority -FacePriority @("Noto Color Emoji") -FaceToFileMap $faceMap
if ($nemoji -ne $null) { $segEmojiPairs += $nemoji }

# Prepend SystemLink cho nhiều base families
$baseFamilies = @("Segoe UI","Arial","Times New Roman","Courier New","Calibri","Cambria","Consolas")
foreach($bf in $baseFamilies){ if ($segBasePairs.Count -gt 0){ Prepend-FontLink -BaseFamily $bf -Pairs $segBasePairs } }
if ($segSymPairs.Count  -gt 0){ Prepend-FontLink -BaseFamily "Segoe UI Symbol" -Pairs $segSymPairs }
if ($segEmojiPairs.Count -gt 0){ Prepend-FontLink -BaseFamily "Segoe UI Emoji"  -Pairs $segEmojiPairs }

# Aggressive substitutes
function Pick-FirstInstalled { param([string[]]$Prefer,[hashtable]$FaceMap)
  foreach($n in $Prefer){ foreach($k in $FaceMap.Keys){ if ($k -eq $n -or $k -like ($n + "*")) { return $k } } }
  return $null
}
$toSans   = Pick-FirstInstalled -Prefer @("Noto Sans","Inter","Open Sans","Roboto","Ubuntu","PT Sans") -FaceMap $faceMap
$toSerif  = Pick-FirstInstalled -Prefer @("Merriweather","Lora") -FaceMap $faceMap
$toMono   = Pick-FirstInstalled -Prefer @("Cascadia Mono","Cascadia Mono PL","Fira Code","Inconsolata","Victor Mono","JetBrains Mono") -FaceMap $faceMap
$toSymbol = Pick-FirstInstalled -Prefer @("Noto Symbols") -FaceMap $faceMap
$toMath   = Pick-FirstInstalled -Prefer @("Noto Sans Math") -FaceMap $faceMap
$toEmoji  = Pick-FirstInstalled -Prefer @("Noto Color Emoji") -FaceMap $faceMap

if ($toSans)   { Set-FontSubstitute -From "Arial"           -To $toSans }
if ($toSerif)  { Set-FontSubstitute -From "Times New Roman" -To $toSerif }
if ($toMono)   { Set-FontSubstitute -From "Courier New"     -To $toMono }
if ($toSymbol) { Set-FontSubstitute -From "Segoe UI Symbol" -To $toSymbol }
if ($toMath)   { Set-FontSubstitute -From "Cambria Math"    -To $toMath }
if ($toEmoji)  { Set-FontSubstitute -From "Segoe UI Emoji"  -To $toEmoji }

# refresh caches & broadcast
Refresh-Fonts

# 3) Results
Write-Host "`n[3/3] Results & verification..." -ForegroundColor Yellow
$afterList  = Get-CurrentFonts
$afterInv   = Get-FontInventoryHash
$afterFall  = Get-FallbackHash

Write-Host "`n--- FONT METRICS (Registry list) ---" -ForegroundColor Cyan
Write-Host ("Count: {0} -> {1}  (Δ {2})" -f $beforeList.Count,$afterList.Count,($afterList.Count-$beforeList.Count)) -ForegroundColor Green

Write-Host "`n--- HASHES ---" -ForegroundColor Cyan
Write-Host ("Inventory:  {0} -> {1}" -f (Head32 $beforeInv), (Head32 $afterInv)) -ForegroundColor White
Write-Host ("Fallback :  {0} -> {1}" -f (Head32 $beforeFall), (Head32 $afterFall)) -ForegroundColor White

$changedInv  = ($beforeInv -ne $afterInv)
$changedFall = ($beforeFall -ne $afterFall)

Write-Status ("Font Metrics changed?   " + ($(if ($changedInv) {"YES"} else {"NO"}))) ($(if ($changedInv) {"Green"} else {"Red"}))
Write-Status ("Unicode Glyphs changed? " + ($(if ($changedFall) {"YES"} else {"NO"}))) ($(if ($changedFall) {"Green"} else {"Red"}))

try { Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue } catch {}

Write-Log -Message "Run finished."
