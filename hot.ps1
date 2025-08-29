# ================================
# Font Fingerprint Rotator (FULL, Emoji ON) - PS 5.x SAFE
# EU/US Latin + Unicode (Symbols/Math/Music/Emoji)
# Max 5 fonts/run, focus on changing both Inventory & Fallback hashes
# Log:  %USERPROFILE%\Downloads\FontRotator\log.txt
# ================================

# --- Admin guard ---
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
  ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
  Write-Host "[ERROR] Run PowerShell as Administrator." -ForegroundColor Red
  return
}

# --- TLS & paths ---
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
$UserDownloads = [Environment]::GetFolderPath('UserProfile') + "\Downloads"
$BaseDir = Join-Path $UserDownloads "FontRotator"
$LogPath = Join-Path $BaseDir "log.txt"
$TempDir = Join-Path $env:TEMP "FontRotator"
$FontsDir = "$env:WINDIR\Fonts"

$HKLM_FONTS = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
$HKLM_LINK  = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontLink\SystemLink"
$HKCU_LINK  = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontLink\SystemLink"
$HKLM_SUBST = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes"
$HKCU_SUBST = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes"

New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

function Log([string]$level,[string]$msg){
  $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  $line = "[$ts] [$level] $msg"
  Write-Host $line
  Add-Content -Path $LogPath -Value $line
}
Log "INFO" "=== RUN $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="
Log "INFO" ("OS: {0}  PS: {1}" -f [System.Environment]::OSVersion.VersionString, $PSVersionTable.PSVersion)

# --- Helpers ---
function Get-FontRegistryList {
  try {
    (Get-ItemProperty $HKLM_FONTS).psobject.Properties |
      Where-Object { $_.Name -notmatch '^PS' } |
      ForEach-Object { $_.Name } |
      Sort-Object -Unique
  } catch { @() }
}
function Hash-String([string]$s){
  $sha = [System.Security.Cryptography.SHA256]::Create()
  ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($s)) | ForEach-Object { $_.ToString("x2") }) -join "" | ForEach-Object { $_.ToUpper() }
}
function Get-InventoryHash { Hash-String ((Get-FontRegistryList) -join "|") }
function Get-FallbackHash {
  $parts = @()
  foreach($root in @($HKLM_LINK,$HKCU_LINK)){
    try{
      $p = Get-ItemProperty $root -ErrorAction Stop
      $p.psobject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object {
        $parts += ("{0}={1}" -f $_.Name, ($_.Value -join ",")) }
    }catch{}
  }
  foreach($root in @($HKLM_SUBST,$HKCU_SUBST)){
    try{
      $p = Get-ItemProperty $root -ErrorAction Stop
      $p.psobject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object {
        $parts += ("{0}->{1}" -f $_.Name, $_.Value) }
    }catch{}
  }
  Hash-String (($parts | Sort-Object) -join "|")
}
function Ensure-Key($path){ if(-not (Test-Path $path)){ New-Item -Path $path -Force | Out-Null } }

function Download-SmallTTF {
  param([string[]]$Urls,[string]$OutFile,[int]$MaxTries=3)
  foreach($u in $Urls){
    for($i=1;$i -le $MaxTries;$i++){
      Log "INFO" ("Download attempt {0}: {1}" -f $i,$u)
      try{
        try{ $null = Invoke-WebRequest -Uri $u -Method Head -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop }catch{}
        Invoke-WebRequest -Uri $u -OutFile $OutFile -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
        $fi = Get-Item -LiteralPath $OutFile -ErrorAction Stop
        if($fi.Length -lt 10240){ throw "File too small ($($fi.Length) bytes)" }
        Log "INFO" "Download OK: $OutFile"
        return $true
      }catch{
        Log "ERROR" "Download error: $($_.Exception.Message)"
        Start-Sleep -Milliseconds (350 + (Get-Random -Minimum 0 -Maximum 300))
      }
    }
  }
  Log "ERROR" "Download failed for all URLs."
  return $false
}
function Install-Ttf {
  param([string]$FilePath,[string]$DisplayName)
  try{
    $src = Get-Item -LiteralPath $FilePath -ErrorAction Stop
    $destName = $src.Name
    $dest = Join-Path $FontsDir $destName
    if(Test-Path $dest){
      Log "INFO" "Exists: $destName"
    } else {
      Copy-Item -LiteralPath $FilePath -Destination $dest -Force
      Log "INFO" ("Installed: {0} -> {1}" -f $DisplayName, $src.Name)
    }
    $keyName = "$DisplayName (TrueType)"
    try {
      if(-not (Get-ItemProperty -Path $HKLM_FONTS -Name $keyName -ErrorAction SilentlyContinue)){
        New-ItemProperty -Path $HKLM_FONTS -Name $keyName -Value $destName -PropertyType String -Force | Out-Null
      } else {
        Set-ItemProperty -Path $HKLM_FONTS -Name $keyName -Value $destName -ErrorAction SilentlyContinue
      }
    } catch { }
    return $true
  }catch{
    Log "ERROR" "Install error: $($_.Exception.Message)"
    return $false
  }
}
function Update-SystemLink {
  param([string]$Root,[string]$Family,[string[]]$PrependEntries)
  try{
    Ensure-Key $Root
    $cur = $null
    try { $cur = (Get-ItemProperty -Path $Root -Name $Family -ErrorAction Stop).$Family } catch { $cur = @() }
    if($cur -is [string]){ $cur = @($cur) }
    $newOrder = @()
    # Trộn ngẫu nhiên để đổi thứ tự fallback mỗi lần
    $rand = $PrependEntries | Sort-Object { Get-Random }
    $newOrder += $rand
    $newOrder += $cur
    # bỏ trùng
    $seen = @{}
    $final = @()
    foreach($e in $newOrder){
      if(-not $seen.ContainsKey($e)){ $seen[$e]=$true; $final += $e }
    }
    if(-not (Get-ItemProperty -Path $Root -Name $Family -ErrorAction SilentlyContinue)){
      New-ItemProperty -Path $Root -Name $Family -Value $final -PropertyType MultiString -Force | Out-Null
    } else {
      Set-ItemProperty -Path $Root -Name $Family -Value $final -ErrorAction SilentlyContinue
    }
    $scope = if($Root -like "HKLM:*"){"HKLM"}else{"HKCU"}
    Log "INFO" ("SystemLink [{0}] ({1}) <= {2}" -f $Family,$scope,($PrependEntries -join " | "))
  }catch{
    Log "ERROR" ("SystemLink update failed [{0}]: {1}" -f $Family, $_.Exception.Message)
  }
}

# --- Curated pools (TTF, small, live links) ---
$Pool_Latin = @(
  @{ Name="Titillium Web";     File="TitilliumWeb-Regular.ttf";       Urls=@('https://raw.githubusercontent.com/google/fonts/main/ofl/titilliumweb/TitilliumWeb-Regular.ttf') };
  @{ Name="Spectral";          File="Spectral-Regular.ttf";           Urls=@('https://raw.githubusercontent.com/google/fonts/main/ofl/spectral/Spectral-Regular.ttf') };
  @{ Name="Barlow";            File="Barlow-Regular.ttf";             Urls=@('https://raw.githubusercontent.com/google/fonts/main/ofl/barlow/Barlow-Regular.ttf') };
  @{ Name="Barlow Condensed";  File="BarlowCondensed-Regular.ttf";    Urls=@('https://raw.githubusercontent.com/google/fonts/main/ofl/barlowcondensed/BarlowCondensed-Regular.ttf') };
  @{ Name="Alegreya Sans";     File="AlegreyaSans-Regular.ttf";       Urls=@('https://raw.githubusercontent.com/google/fonts/main/ofl/alegreyasans/AlegreyaSans-Regular.ttf') };
  @{ Name="Zilla Slab";        File="ZillaSlab-Regular.ttf";          Urls=@('https://raw.githubusercontent.com/google/fonts/main/ofl/zillaslab/ZillaSlab-Regular.ttf') };
  @{ Name="Ubuntu";            File="Ubuntu-Regular.ttf";             Urls=@('https://raw.githubusercontent.com/google/fonts/main/ufl/ubuntu/Ubuntu-Regular.ttf') };
  @{ Name="Ubuntu Mono";       File="UbuntuMono-Regular.ttf";         Urls=@('https://raw.githubusercontent.com/google/fonts/main/ufl/ubuntumono/UbuntuMono-Regular.ttf') };
  @{ Name="Cousine";           File="Cousine-Regular.ttf";            Urls=@('https://raw.githubusercontent.com/google/fonts/main/apache/cousine/Cousine-Regular.ttf') };
  @{ Name="Tinos";             File="Tinos-Regular.ttf";              Urls=@('https://raw.githubusercontent.com/google/fonts/main/apache/tinos/Tinos-Regular.ttf') };
  @{ Name="IBM Plex Mono";     File="IBMPlexMono-Regular.ttf";        Urls=@('https://raw.githubusercontent.com/google/fonts/main/ofl/ibmplexmono/IBMPlexMono-Regular.ttf') };
  @{ Name="Gentium Plus";      File="GentiumPlus-Regular.ttf";        Urls=@('https://raw.githubusercontent.com/google/fonts/main/ofl/gentiumplus/GentiumPlus-Regular.ttf') };
  @{ Name="Gentium Book Plus"; File="GentiumBookPlus-Regular.ttf";    Urls=@('https://raw.githubusercontent.com/google/fonts/main/ofl/gentiumbookplus/GentiumBookPlus-Regular.ttf') };
  @{ Name="Crimson Text";      File="CrimsonText-Regular.ttf";        Urls=@('https://raw.githubusercontent.com/google/fonts/main/ofl/crimsontext/CrimsonText-Regular.ttf') };
  @{ Name="Bebas Neue";        File="BebasNeue-Regular.ttf";          Urls=@('https://raw.githubusercontent.com/google/fonts/main/ofl/bebasneue/BebasNeue-Regular.ttf') };
  @{ Name="Libre Baskerville"; File="LibreBaskerville-Regular.ttf";   Urls=@('https://raw.githubusercontent.com/google/fonts/main/ofl/librebaskerville/LibreBaskerville-Regular.ttf') };
  # Một số family có 'static' làm fallback:
  @{ Name="Roboto";            File="Roboto-Regular.ttf";             Urls=@('https://raw.githubusercontent.com/google/fonts/main/apache/roboto/static/Roboto-Regular.ttf','https://raw.githubusercontent.com/google/fonts/main/apache/roboto/Roboto-Regular.ttf') };
  @{ Name="Inter";             File="Inter-Regular.ttf";              Urls=@('https://raw.githubusercontent.com/google/fonts/main/ofl/inter/static/Inter-Regular.ttf') };
  @{ Name="JetBrains Mono";    File="JetBrainsMono-Regular.ttf";      Urls=@('https://raw.githubusercontent.com/google/fonts/main/ofl/jetbrainsmono/static/JetBrainsMono-Regular.ttf') };
  @{ Name="Inconsolata";       File="Inconsolata-Regular.ttf";        Urls=@('https://raw.githubusercontent.com/google/fonts/main/ofl/inconsolata/static/Inconsolata-Regular.ttf') };
  @{ Name="Josefin Sans";      File="JosefinSans-Regular.ttf";        Urls=@('https://raw.githubusercontent.com/google/fonts/main/ofl/josefinsans/static/JosefinSans-Regular.ttf') };
  @{ Name="Raleway";           File="Raleway-Regular.ttf";            Urls=@('https://raw.githubusercontent.com/google/fonts/main/ofl/raleway/static/Raleway-Regular.ttf') };
  @{ Name="Work Sans";         File="WorkSans-Regular.ttf";           Urls=@('https://raw.githubusercontent.com/google/fonts/main/ofl/worksans/static/WorkSans-Regular.ttf') };
  @{ Name="Public Sans";       File="PublicSans-Regular.ttf";         Urls=@('https://raw.githubusercontent.com/google/fonts/main/ofl/publicsans/static/PublicSans-Regular.ttf') };
  @{ Name="Space Grotesk";     File="SpaceGrotesk-Regular.ttf";       Urls=@('https://raw.githubusercontent.com/google/fonts/main/ofl/spacegrotesk/static/SpaceGrotesk-Regular.ttf') };
  @{ Name="PT Serif";          File="PTSerif-Regular.ttf";            Urls=@('https://raw.githubusercontent.com/google/fonts/main/ofl/ptserif/static/PTSerif-Regular.ttf','https://raw.githubusercontent.com/google/fonts/main/ofl/ptserif/PTSerif-Regular.ttf') };
  @{ Name="PT Mono";           File="PTMono-Regular.ttf";             Urls=@('https://raw.githubusercontent.com/google/fonts/main/ofl/ptmono/static/PTMono-Regular.ttf','https://raw.githubusercontent.com/google/fonts/main/ofl/ptmono/PTMono-Regular.ttf') }
)

$Pool_Unicode = @(
  @{ Name="Noto Sans Symbols2"; File="NotoSansSymbols2-Regular.ttf"; Urls=@(
      'https://raw.githubusercontent.com/googlefonts/noto-fonts/main/hinted/ttf/NotoSansSymbols2/NotoSansSymbols2-Regular.ttf',
      'https://notofonts.github.io/symbols/fonts/NotoSansSymbols2/hinted/ttf/NotoSansSymbols2-Regular.ttf'
    ) };
  @{ Name="Noto Sans Symbols";  File="NotoSansSymbols-Regular.ttf";  Urls=@(
      'https://notofonts.github.io/symbols/fonts/NotoSansSymbols/hinted/ttf/NotoSansSymbols-Regular.ttf'
    ) };
  @{ Name="Noto Sans Math";     File="NotoSansMath-Regular.ttf";     Urls=@(
      'https://raw.githubusercontent.com/googlefonts/noto-fonts/main/hinted/ttf/NotoSansMath/NotoSansMath-Regular.ttf'
    ) };
  @{ Name="Noto Music";         File="NotoMusic-Regular.ttf";        Urls=@(
      'https://raw.githubusercontent.com/googlefonts/noto-fonts/main/hinted/ttf/NotoMusic/NotoMusic-Regular.ttf'
    ) };
  @{ Name="Noto Color Emoji";   File="NotoColorEmoji.ttf";           Urls=@(
      'https://raw.githubusercontent.com/googlefonts/noto-emoji/main/fonts/NotoColorEmoji.ttf'
    ); Heavy=$true }
)

# --- Before hashes ---
$invBefore = Get-InventoryHash
$fallbackBefore = Get-FallbackHash
$cntBefore = (Get-FontRegistryList).Count
function Short([string]$h){ if($h.Length -gt 32){ $h.Substring(0,32) } else { $h } }
Log "INFO" ("Current fonts: {0}" -f $cntBefore)
Log "INFO" ("Inventory Hash: {0}..." -f (Short $invBefore))
Log "INFO" ("Fallback Hash : {0}..." -f (Short $fallbackBefore))

# --- Pick up to 5 fonts: 2 Latin + 3 Unicode (emoji included) ---
$MaxFontsPerRun = 5
$latinPick = $Pool_Latin | Get-Random -Count 2
# Emoji bắt buộc + 2 Unicode nhẹ
$emojiItem = $Pool_Unicode | Where-Object { $_.Name -eq 'Noto Color Emoji' } | Select-Object -First 1
$ucSmall   = $Pool_Unicode | Where-Object { $_.Name -ne 'Noto Color Emoji' }
$uniPick   = @($emojiItem) + ($ucSmall | Get-Random -Count 2)

$selection = @()
$selection += $latinPick
$selection += $uniPick
if($selection.Count -gt $MaxFontsPerRun){
  $selection = $selection | Select-Object -First $MaxFontsPerRun
}

# --- Download + Install ---
$installed = @()
foreach($item in $selection){
  $outFile = Join-Path $TempDir $item.File
  if(Download-SmallTTF -Urls $item.Urls -OutFile $outFile){
    if(Install-Ttf -FilePath $outFile -DisplayName $item.Name){
      $installed += $item
    }
  } else {
    Log "ERROR" ("Download failed: {0}" -f $item.Name)
  }
}

# --- FontLink / Substitutes (prepend new fonts to change fallback paths) ---
Ensure-Key $HKLM_LINK; Ensure-Key $HKCU_LINK
Ensure-Key $HKLM_SUBST; Ensure-Key $HKCU_SUBST

# Build entries "filename,friendly"
$latinEntries = @()
foreach($l in $latinPick){ $latinEntries += ("{0},{1}" -f $l.File,$l.Name) }
$uniEntries = @()
foreach($u in $uniPick){ $uniEntries += ("{0},{1}" -f $u.File,$u.Name) }

# SystemLink targets
$targets = @(
  @{ Fam="Segoe UI";            Picks=$latinEntries },
  @{ Fam="Segoe UI Variable";   Picks=$latinEntries },
  @{ Fam="Arial";               Picks=$latinEntries },
  @{ Fam="Times New Roman";     Picks=$latinEntries },
  @{ Fam="Calibri";             Picks=$latinEntries },
  @{ Fam="Consolas";            Picks=$latinEntries },
  @{ Fam="Courier New";         Picks=$latinEntries },
  @{ Fam="Segoe UI Symbol";     Picks=$uniEntries },
  @{ Fam="Segoe UI Emoji";      Picks=@("NotoColorEmoji.ttf,Noto Color Emoji") }
)

foreach($t in $targets){
  Update-SystemLink -Root $HKLM_LINK -Family $t.Fam -PrependEntries $t.Picks
  Update-SystemLink -Root $HKCU_LINK -Family $t.Fam -PrependEntries $t.Picks
}

# Substitutes (1-1)
function FirstOr($arr,$fallback){ if($arr -and $arr.Count -gt 0){ $arr[0] } else { $fallback } }
$latinName1 = FirstOr (($latinPick | Select-Object -ExpandProperty Name), "Barlow")
$latinMono  = FirstOr (($latinPick | Where-Object { $_.Name -match 'Mono|Cousine|Ubuntu Mono|IBM Plex Mono' } | Select-Object -ExpandProperty Name), "IBM Plex Mono")
$latinSerif = FirstOr (($latinPick | Where-Object { $_.Name -match 'Serif|Gentium|Crimson|Zilla|Spectral|Tinos|Baskerville' } | Select-Object -ExpandProperty Name), "Tinos")
$unicodeOne = FirstOr (($uniPick   | Where-Object { $_.Name -match 'Symbols|Math|Music' } | Select-Object -ExpandProperty Name), "Noto Sans Symbols2")

$substPairs = @(
  @{ Src="Segoe UI";            Dst=$latinName1 },
  @{ Src="Arial";               Dst=$latinName1 },
  @{ Src="Microsoft Sans Serif";Dst=$latinName1 },
  @{ Src="Times New Roman";     Dst=$latinSerif },
  @{ Src="Consolas";            Dst=$latinMono },
  @{ Src="Courier New";         Dst=$latinMono },
  @{ Src="Segoe UI Symbol";     Dst=$unicodeOne },
  @{ Src="Cambria Math";        Dst="Noto Sans Math" },
  @{ Src="Segoe UI Emoji";      Dst="Noto Color Emoji" }
)

foreach($p in $substPairs){
  foreach($root in @($HKLM_SUBST,$HKCU_SUBST)){
    try{
      Ensure-Key $root
      Set-ItemProperty -Path $root -Name $p.Src -Value $p.Dst -Force
      $scope = if($root -like "HKLM:*"){"HKLM"}else{"HKCU"}
      Log "INFO" ("Substitute({0}): {1} -> {2}" -f $scope,$p.Src,$p.Dst)
    }catch{
      Log "ERROR" ("Substitute failed {0}: {1}" -f $p.Src, $_.Exception.Message)
    }
  }
}

# --- After hashes ---
$invAfter = Get-InventoryHash
$fallbackAfter = Get-FallbackHash
$cntAfter = (Get-FontRegistryList).Count

Log "INFO" ""
Log "INFO" "--- FONT METRICS (Registry list) ---"
Log "INFO" ("Count: {0} -> {1}  (Δ {2})" -f $cntBefore,$cntAfter,($cntAfter-$cntBefore))
Log "INFO" ""
Log "INFO" "--- HASHES ---"
Log "INFO" ("Inventory:  {0} -> {1}" -f (Short $invBefore), (Short $invAfter))
Log "INFO" ("Fallback :  {0} -> {1}" -f (Short $fallbackBefore), (Short $fallbackAfter))
Log "INFO" ("Font Metrics changed?   {0}" -f ($(if($invBefore -ne $invAfter){"YES"}else{"NO"})))
Log "INFO" ("Unicode Glyphs changed? {0}" -f ($(if($fallbackBefore -ne $fallbackAfter){"YES"}else{"NO"})))
Log "INFO" "Run finished."
