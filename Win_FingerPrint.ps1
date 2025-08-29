<# ===================================================================
   ADVANCED FONT FINGERPRINT ROTATOR v3.1 (PowerShell 5.x SAFE)
   - Random cài thêm font (Google/Adobe/Microsoft/JetBrains…)
   - Ghi Registry theo Face Name (TTF/OTF; TTC fallback)
   - Đổi FontLink/SystemLink theo profile (JP/SC/KR) => đổi Unicode glyphs
   - 3 hashes để kiểm: InventoryHash, FallbackChainHash + (đếm FaceNames)
   - Tuyệt đối KHÔNG xoá font hệ thống; chỉ thêm font mới.
=================================================================== #>

# ============ Admin check ============
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "ERROR: Please run PowerShell as Administrator!" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# ============ Globals ============
$TempDir  = "$env:TEMP\FontRotator"
$FontsDir = "$env:SystemRoot\Fonts"
if (!(Test-Path $TempDir)) { New-Item -ItemType Directory -Path $TempDir -Force | Out-Null }

function Write-Status { param([string]$m,[string]$c="Cyan"); $ts=Get-Date -Format "HH:mm:ss"; Write-Host "[$ts] $m" -ForegroundColor $c }
function Head32 { param($s); if ($s -and $s.Length -ge 32) { return $s.Substring(0,32) } elseif ($s) { return $s } else { return "NA" } }

# ============ Trusted Font Sources ============
$FontDB = @{
  Western = @{
    "Inter"         = "https://github.com/rsms/inter/releases/download/v3.19/Inter-3.19.zip"
    "JetBrainsMono" = "https://github.com/JetBrains/JetBrainsMono/releases/download/v2.304/JetBrainsMono-2.304.zip"
    "Roboto"        = "https://github.com/googlefonts/roboto/releases/download/v2.138/roboto-unhinted.zip"
    "IBM-Plex-Sans" = "https://github.com/IBM/plex/releases/download/%40ibm%2Fplex-sans%401.0.0/TrueType.zip"
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
  Scripts = @{
    "NotoSansArabic" = "https://github.com/googlefonts/noto-fonts/raw/main/hinted/ttf/NotoSansArabic/NotoSansArabic-Regular.ttf"
    "NotoSansHebrew" = "https://github.com/googlefonts/noto-fonts/raw/main/hinted/ttf/NotoSansHebrew/NotoSansHebrew-Regular.ttf"
    "NotoSansThai"   = "https://github.com/googlefonts/noto-fonts/raw/main/hinted/ttf/NotoSansThai/NotoSansThai-Regular.ttf"
    "NotoSansKR"     = "https://github.com/googlefonts/noto-fonts/raw/main/hinted/ttf/NotoSansKR/NotoSansKR-Regular.ttf"
  };
  Specialty = @{
    "FiraCode"      = "https://github.com/tonsky/FiraCode/releases/download/6.2/Fira_Code_v6.2.zip"
    "CascadiaCode"  = "https://github.com/microsoft/cascadia-code/releases/download/v2111.01/CascadiaCode-2111.01.zip"
    "VictorMono"    = "https://github.com/rubjo/victor-mono/releases/download/v1.5.4/VictorMonoAll.zip"
    "Inconsolata"   = "https://github.com/googlefonts/Inconsolata/releases/download/v3.000/fonts_ttf.zip"
    "DejaVu"        = "https://github.com/dejavu-fonts/dejavu-fonts/releases/download/version_2_37/dejavu-fonts-ttf-2.37.zip"
    "Liberation"    = "https://github.com/liberationfonts/liberation-fonts/releases/download/2.1.5/liberation-fonts-ttf-2.1.5.tar.gz"
  }
}

# ============ Helpers ============
function Download-File {
  param([string]$Url,[string]$OutFile,[int]$MaxRetry=3,[int]$TimeoutSec=300)
  for ($i=1; $i -le $MaxRetry; $i++) {
    try {
      if ($PSVersionTable.PSVersion.Major -ge 7) {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -TimeoutSec $TimeoutSec
      } else {
        try {
          Start-BitsTransfer -Source $Url -Destination $OutFile -DisplayName "FontDL" -Description "Downloading $([IO.Path]::GetFileName($OutFile))" -ErrorAction Stop
        } catch {
          Invoke-WebRequest -Uri $Url -OutFile $OutFile
        }
      }
      if ((Test-Path $OutFile) -and ((Get-Item $OutFile).Length -gt 1000)) { return $true }
    } catch {}
    Start-Sleep -Seconds ([Math]::Min(2*$i,10))
  }
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
  } catch { return @() }
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
    return ([BitConverter]::ToString($hash) -replace '-','')
  } catch { return "NA" }
}

function Get-FallbackChainHash {
  $key='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontLink\SystemLink'
  $bases=@("Segoe UI","Segoe UI Symbol","Segoe UI Emoji")
  $rows=@()
  foreach($b in $bases){
    $v=(Get-ItemProperty -Path $key -Name $b -ErrorAction SilentlyContinue).$b
    if ($v) { $rows+=("$b=" + ($v -join ";")) } else { $rows+=("$b=") }
  }
  $bytes=[Text.Encoding]::UTF8.GetBytes(($rows -join "`n"))
  $hash=[Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
  return ([BitConverter]::ToString($hash) -replace '-','')
}

function Get-FontFaceName { param([string]$FilePath)
  try {
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    $pfc=New-Object System.Drawing.Text.PrivateFontCollection
    $pfc.AddFontFile($FilePath)
    if ($pfc.Families.Count -gt 0) { return $pfc.Families[0].Name }
  } catch {}
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

    Write-Status "Installed: $face -> $($fontFile.Name)" "Green"
    return @{ Face=$face; File=$fontFile.Name }
  } catch {
    Write-Status "Install error: $($_.Exception.Message)" "Red"
    return $null
  }
}

function Install-FromUrl { param([string]$Name,[string]$Url)
  try {
    $lower=$Url.ToLower()
    if ($lower.EndsWith(".ttf") -or $lower.EndsWith(".otf") -or $lower.EndsWith(".ttc")) {
      $out=Join-Path $TempDir ([IO.Path]::GetFileName($Url))
      if (-not (Download-File -Url $Url -OutFile $out)) { Write-Status "Download failed: $Name" "Red"; return @() }
      $r = Install-SingleFontFile -FilePath $out -FallbackName $Name
      if ($r -ne $null) { return @($r) } else { return @() }
    }
    if ($lower.EndsWith(".zip")) {
      $zip=Join-Path $TempDir "$Name.zip"
      if (-not (Download-File -Url $Url -OutFile $zip)) { Write-Status "Download failed: $Name" "Red"; return @() }
      $extract=Join-Path $TempDir ("ex_" + $Name)
      if (Test-Path $extract){ Remove-Item $extract -Recurse -Force -ErrorAction SilentlyContinue }
      Expand-Archive -Path $zip -DestinationPath $extract -Force
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
    if ($lower.EndsWith(".tar.gz")) {
      $tgz=Join-Path $TempDir "$Name.tgz"
      if (-not (Download-File -Url $Url -OutFile $tgz)) { Write-Status "Download failed: $Name" "Red"; return @() }
      try { tar -xzf $tgz -C $TempDir | Out-Null } catch {}
      $installed=@()
      $ttfs = Get-ChildItem -Path $TempDir -Recurse -Include *.ttf,*.otf |
        Where-Object { $_.Name -match "Regular|Bold|Medium" } | Select-Object -First 4
      foreach($f in $ttfs){ $x=Install-SingleFontFile -FilePath $f.FullName -FallbackName $Name; if ($x -ne $null){ $installed+=$x } }
      return $installed
    }
    Write-Status "Unsupported URL type: $Url" "Yellow"
    return @()
  } catch {
    Write-Status "Install-FromUrl error: $($_.Exception.Message)" "Red"
    return @()
  }
}

function Get-FaceToFileMap {
  $map=@{}
  $reg="HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
  $props=(Get-ItemProperty $reg -ErrorAction SilentlyContinue).PSObject.Properties |
    Where-Object { $_.Name -and $_.Name -notmatch '^PS' -and $_.Value }
  foreach($p in $props){
    $face=($p.Name -replace ' \(TrueType\)$','' -replace ' \(OpenType\)$','')
    $map[$face] = $p.Value
  }
  return $map
}

function Prepend-FontLink {
  param([string]$BaseFamily,[string[]]$Pairs)
  $key='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontLink\SystemLink'
  $cur=(Get-ItemProperty -Path $key -Name $BaseFamily -ErrorAction SilentlyContinue).$BaseFamily
  if (-not $cur) { $cur=@() }
  $new = ($Pairs + $cur) | Select-Object -Unique
  New-ItemProperty -Path $key -Name $BaseFamily -Value $new -PropertyType MultiString -Force | Out-Null
}

function Refresh-Fonts {
  try {
    Stop-Service FontCache -Force -ErrorAction SilentlyContinue
    Start-Sleep 1
    Remove-Item "$env:LOCALAPPDATA\FontCache\*" -Force -ErrorAction SilentlyContinue
  } catch {}
  Start-Service FontCache -ErrorAction SilentlyContinue
  Add-Type -Namespace Win32 -Name U -MemberDefinition '[DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h,uint m,IntPtr w,IntPtr l,uint f,uint t,out IntPtr r);'
  [void][Win32.U]::SendMessageTimeout([IntPtr]0xffff,0x1D,[IntPtr]0,[IntPtr]0,2,1000,[ref]([IntPtr]::Zero))
}

function Pick-RandomFonts {
  param([int]$Count=6)
  $picked=@()
  $w = ($FontDB.Western.GetEnumerator() | Get-Random -Count 1)
  $picked += ,@{ Name=$w.Name; Url=$w.Value }
  $u = ($FontDB.Unicode.GetEnumerator() | Get-Random -Count 1)
  $picked += ,@{ Name=$u.Name; Url=$u.Value }
  $cjkKeys = @("NotoSansCJKjp-Regular","NotoSansCJKsc-Regular","NotoSansCJKkr-Regular","NotoSansCJK-OTC")
  $c = ($cjkKeys | Get-Random -Count 1)[0]
  $picked += ,@{ Name=$c; Url=$FontDB.CJK[$c] }
  $pool=@()
  foreach($k in $FontDB.Scripts.Keys){ $pool += ,@{ Name=$k; Url=$FontDB.Scripts[$k] } }
  foreach($k in $FontDB.Specialty.Keys){ $pool += ,@{ Name=$k; Url=$FontDB.Specialty[$k] } }
  foreach($k in $FontDB.Unicode.Keys){ if ($k -ne $u.Name) { $pool += ,@{ Name=$k; Url=$FontDB.Unicode[$k] } } }
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
Write-Host "   ADVANCED FONT FINGERPRINT ROTATOR v3.1 (PS 5.x SAFE)" -ForegroundColor Yellow
Write-Host "==============================================================" -ForegroundColor Green

# Baseline
$beforeList   = Get-CurrentFonts
$beforeInv    = Get-FontInventoryHash
$beforeFall   = Get-FallbackChainHash

Write-Status ("Current fonts: {0}" -f $beforeList.Count) "Cyan"
Write-Status ("Inventory Hash: {0}..." -f (Head32 $beforeInv)) "Cyan"
Write-Status ("FallbackChain:  {0}..." -f (Head32 $beforeFall)) "Cyan"

# 1) Download & install random fonts (5..8)
$targetCount = Get-Random -Minimum 5 -Maximum 9
Write-Host "`n[1/3] Download & install random fonts ($targetCount)..." -ForegroundColor Yellow
$wish = Pick-RandomFonts -Count $targetCount
$installedMeta=@()
foreach($item in $wish){ $r = Install-FromUrl -Name $item.Name -Url $item.Url; if ($r.Count -gt 0) { $installedMeta += $r } }

# Ensure core unicode packs present
foreach($core in @("NotoSymbols","NotoSansMath","NotoColorEmoji")){
  $url=$FontDB.Unicode[$core]
  if ($url) { $null = Install-FromUrl -Name $core -Url $url }
}

# 2) Random Unicode fallback profile (JP/SC/KR)
Write-Host "`n[2/3] Configure Unicode glyph fallback (SystemLink)..." -ForegroundColor Yellow

$bk1="$TempDir\SystemLink_backup.reg"
$bk2="$TempDir\FontSub_backup.reg"
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

if ($segBasePairs.Count -gt 0) { Prepend-FontLink -BaseFamily "Segoe UI"        -Pairs $segBasePairs }
if ($segSymPairs.Count  -gt 0) { Prepend-FontLink -BaseFamily "Segoe UI Symbol" -Pairs $segSymPairs }
if ($segEmojiPairs.Count -gt 0) { Prepend-FontLink -BaseFamily "Segoe UI Emoji"  -Pairs $segEmojiPairs }

Refresh-Fonts

# 3) Results
Write-Host "`n[3/3] Results & verification..." -ForegroundColor Yellow
$afterList  = Get-CurrentFonts
$afterInv   = Get-FontInventoryHash
$afterFall  = Get-FallbackChainHash

Write-Host "`n--- FONT METRICS (Registry list) ---" -ForegroundColor Cyan
Write-Host ("Count: {0} -> {1}  (Δ {2})" -f $beforeList.Count,$afterList.Count,($afterList.Count-$beforeList.Count)) -ForegroundColor Green

Write-Host "`n--- HASHES ---" -ForegroundColor Cyan
Write-Host ("Inventory: {0} -> {1}" -f (Head32 $beforeInv), (Head32 $afterInv)) -ForegroundColor White
Write-Host ("Fallback : {0} -> {1}" -f (Head32 $beforeFall), (Head32 $afterFall)) -ForegroundColor White

$changedInv  = ($beforeInv -ne $afterInv)
$changedFall = ($beforeFall -ne $afterFall)

Write-Host ("Font Metrics changed?   {0}" -f ($(if ($changedInv) {"YES"} else {"NO"}))) -ForegroundColor ($(if ($changedInv) {"Green"} else {"Red"}))
Write-Host ("Unicode Glyphs changed? {0}" -f ($(if ($changedFall) {"YES"} else {"NO"}))) -ForegroundColor ($(if ($changedFall) {"Green"} else {"Red"}))

Start-Process "https://browserleaks.com/fonts"
Start-Process "https://fingerprintjs.com/demo"

Write-Host "`nDone. If browsers are open, restart them to clear font caches." -ForegroundColor Yellow
try { Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue } catch {}
