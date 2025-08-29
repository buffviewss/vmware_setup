# Font Fingerprint Rotator - Lite EU/US + Unicode (max 5 fonts / run)
# Focus: đổi cả Inventory (Font Metrics) + Fallback (Unicode Glyphs)
# - Chỉ cài tối đa 5 font/lần (2 EU/US + 3 Unicode), ưu tiên Unicode
# - Link TTF nhỏ, đã lọc 404; có fallback URL cho Unicode khi khả dụng
# - Không xóa font hệ thống; chỉ thêm mới + chỉnh FontLink/Substitute an toàn
# - Không mở trình duyệt; có log tại ~/Downloads/FontRotator/log.txt

# --- Admin guard ---
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
  Write-Host "[ERROR] Hãy chạy PowerShell 'Run as Administrator'." -ForegroundColor Red
  return
}

# --- TLS + Vars ---
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
$UserDownloads = [Environment]::GetFolderPath('UserProfile') + "\Downloads"
$BaseDir       = Join-Path $UserDownloads "FontRotator"
$LogPath       = Join-Path $BaseDir "log.txt"
$TempDir       = Join-Path $env:TEMP "FontRotator"
$FontsDir      = "$env:WINDIR\Fonts"
$HKLM_FONTS    = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
$HKLM_LINK     = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontLink\SystemLink"
$HKCU_LINK     = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontLink\SystemLink"
$HKLM_SUBST    = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes"
$HKCU_SUBST    = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes"
$MaxFontsPerRun = 5

# --- FS prep ---
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

function Get-InventoryHash {
  $list = Get-FontRegistryList
  return Hash-String ($list -join "|")
}

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
  return Hash-String (($parts | Sort-Object) -join "|")
}

function Test-UrlOk([string]$url){
  try{
    $resp = Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
    return ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 400)
  }catch{ return $false }
}

function Download-SmallTTF {
  param([string[]]$Urls,[string]$OutFile,[int]$MaxTries=3)
  foreach($u in $Urls){
    for($i=1;$i -le $MaxTries;$i++){
      Log "INFO" "Download attempt $i: $u"
      try{
        # HEAD chặn 404 sớm
        if(-not (Test-UrlOk $u)){ throw "HEAD not OK" }
        Invoke-WebRequest -Uri $u -OutFile $OutFile -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
        $fi = Get-Item -LiteralPath $OutFile -ErrorAction Stop
        if($fi.Length -lt 10240){ throw "File too small: $($fi.Length) bytes" }
        Log "INFO" "Download OK: $OutFile"
        return $true
      }catch{
        Log "ERROR" "Download error: $($_.Exception.Message)"
        Start-Sleep -Milliseconds (400 + (Get-Random -Minimum 0 -Maximum 400))
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
      New-ItemProperty -Path $HKLM_FONTS -Name $keyName -Value $destName -PropertyType String -Force | Out-Null
    } catch {
      Set-ItemProperty -Path $HKLM_FONTS -Name $keyName -Value $destName -ErrorAction SilentlyContinue
    }
    return $true
  }catch{
    Log "ERROR" "Install error: $($_.Exception.Message)"
    return $false
  }
}

function Ensure-Key($path){
  if(-not (Test-Path $path)){ New-Item -Path $path -Force | Out-Null }
}

# --- Curated pools (EU/US metrics: nhỏ, đã test OK; Unicode: coverage) ---
$Pool_Latin = @(
  @{ Name="Titillium Web";     File="TitilliumWeb-Regular.ttf"; Urls=@("https://raw.githubusercontent.com/google/fonts/main/ofl/titilliumweb/TitilliumWeb-Regular.ttf") },
  @{ Name="Spectral";          File="Spectral-Regular.ttf";     Urls=@("https://raw.githubusercontent.com/google/fonts/main/ofl/spectral/Spectral-Regular.ttf") },
  @{ Name="Barlow";            File="Barlow-Regular.ttf";       Urls=@("https://raw.githubusercontent.com/google/fonts/main/ofl/barlow/Barlow-Regular.ttf") },
  @{ Name="Barlow Condensed";  File="BarlowCondensed-Regular.ttf"; Urls=@("https://raw.githubusercontent.com/google/fonts/main/ofl/barlowcondensed/BarlowCondensed-Regular.ttf") },
  @{ Name="Alegreya Sans";     File="AlegreyaSans-Regular.ttf"; Urls=@("https://raw.githubusercontent.com/google/fonts/main/ofl/alegreyasans/AlegreyaSans-Regular.ttf") },
  @{ Name="Zilla Slab";        File="ZillaSlab-Regular.ttf";    Urls=@("https://raw.githubusercontent.com/google/fonts/main/ofl/zillaslab/ZillaSlab-Regular.ttf") },
  @{ Name="Ubuntu";            File="Ubuntu-Regular.ttf";       Urls=@("https://raw.githubusercontent.com/google/fonts/main/ufl/ubuntu/Ubuntu-Regular.ttf") },
  @{ Name="Ubuntu Mono";       File="UbuntuMono-Regular.ttf";   Urls=@("https://raw.githubusercontent.com/google/fonts/main/ufl/ubuntumono/UbuntuMono-Regular.ttf") },
  @{ Name="Cousine";           File="Cousine-Regular.ttf";      Urls=@("https://raw.githubusercontent.com/google/fonts/main/apache/cousine/Cousine-Regular.ttf") },
  @{ Name="Tinos";             File="Tinos-Regular.ttf";        Urls=@("https://raw.githubusercontent.com/google/fonts/main/apache/tinos/Tinos-Regular.ttf") },
  @{ Name="IBM Plex Mono";     File="IBMPlexMono-Regular.ttf";  Urls=@("https://raw.githubusercontent.com/google/fonts/main/ofl/ibmplexmono/IBMPlexMono-Regular.ttf") },
  @{ Name="Gentium Plus";      File="GentiumPlus-Regular.ttf";  Urls=@("https://raw.githubusercontent.com/google/fonts/main/ofl/gentiumplus/GentiumPlus-Regular.ttf") },
  @{ Name="Gentium Book Plus"; File="GentiumBookPlus-Regular.ttf"; Urls=@("https://raw.githubusercontent.com/google/fonts/main/ofl/gentiumbookplus/GentiumBookPlus-Regular.ttf") },
  @{ Name="Crimson Text";      File="CrimsonText-Regular.ttf";  Urls=@("https://raw.githubusercontent.com/google/fonts/main/ofl/crimsontext/CrimsonText-Regular.ttf") },
  @{ Name="Bebas Neue";        File="BebasNeue-Regular.ttf";    Urls=@("https://raw.githubusercontent.com/google/fonts/main/ofl/bebasneue/BebasNeue-Regular.ttf") }
)

$Pool_Unicode = @(
  @{ Name="Noto Sans Symbols2"; File="NotoSansSymbols2-Regular.ttf"; Urls=@(
      "https://raw.githubusercontent.com/googlefonts/noto-fonts/main/hinted/ttf/NotoSansSymbols2/NotoSansSymbols2-Regular.ttf",
      "https://notofonts.github.io/symbols/fonts/NotoSansSymbols2/hinted/ttf/NotoSansSymbols2-Regular.ttf"
    )},
  @{ Name="Noto Sans Symbols"; File="NotoSansSymbols-Regular.ttf"; Urls=@(
      "https://notofonts.github.io/symbols/fonts/NotoSansSymbols/hinted/ttf/NotoSansSymbols-Regular.ttf"
    )},
  @{ Name="Noto Sans Math";    File="NotoSansMath-Regular.ttf"; Urls=@(
      "https://raw.githubusercontent.com/googlefonts/noto-fonts/main/hinted/ttf/NotoSansMath/NotoSansMath-Regular.ttf"
    )},
  @{ Name="Noto Music";        File="NotoMusic-Regular.ttf";    Urls=@(
      "https://raw.githubusercontent.com/googlefonts/noto-fonts/main/hinted/ttf/NotoMusic/NotoMusic-Regular.ttf"
    )},
  # Emoji nặng (~10–12MB) — để tắt mặc định cho tốc độ; bật random thấp
  @{ Name="Noto Color Emoji";  File="NotoColorEmoji.ttf";       Urls=@(
      "https://raw.githubusercontent.com/googlefonts/noto-emoji/main/fonts/NotoColorEmoji.ttf"
    ), Heavy=$true }
)

# --- Pre-run hashes ---
$invBefore = Get-InventoryHash
$fallbackBefore = Get-FallbackHash
$cntBefore = (Get-FontRegistryList).Count
Log "INFO" "Current fonts: $cntBefore"
Log "INFO" "Inventory Hash: $($invBefore.Substring(0,32))..."
Log "INFO" "Fallback Hash : $($fallbackBefore.Substring(0,32))..."

# --- Pick up to 5 fonts (2 Latin + 3 Unicode with bias to small files) ---
$latinPick   = ($Pool_Latin | Get-Random -Count 2)
# Unicode: luôn lấy 3; Emoji (heavy) chỉ 1/5 xác suất nếu chưa có emoji trong hệ thống link
$ucPoolSmall = $Pool_Unicode | Where-Object { -not $_.ContainsKey('Heavy') }
$uniPick     = $ucPoolSmall | Get-Random -Count 3
$includeEmoji = (Get-Random -Minimum 0 -Maximum 5) -eq 0
if($includeEmoji -and ($latinPick.Count + $uniPick.Count) -lt $MaxFontsPerRun){
  $uniPick += ($Pool_Unicode | Where-Object { $_.ContainsKey('Heavy') } | Get-Random -Count 1)
}
$selection = @()
$selection += $latinPick
$selection += $uniPick
# Giới hạn cứng
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

# --- FontLink / Substitutes to maximize glyph fallback impact ---
Ensure-Key $HKLM_LINK; Ensure-Key $HKCU_LINK
Ensure-Key $HKLM_SUBST; Ensure-Key $HKCU_SUBST

# Xây list các entry cần chèn vào FontLink (prepend: ưu tiên font mới)
# Tên hiển thị cần khớp family phổ biến của Windows
$targets = @(
  @{ Fam="Segoe UI";           Picks=($latinPick | ForEach-Object { "$($_.File),$($_.Name)" }) },
  @{ Fam="Segoe UI Variable";  Picks=($latinPick | ForEach-Object { "$($_.File),$($_.Name)" }) },
  @{ Fam="Arial";              Picks=($latinPick | ForEach-Object { "$($_.File),$($_.Name)" }) },
  @{ Fam="Times New Roman";    Picks=($latinPick | ForEach-Object { "$($_.File),$($_.Name)" }) },
  @{ Fam="Calibri";            Picks=($latinPick | ForEach-Object { "$($_.File),$($_.Name)" }) },
  @{ Fam="Consolas";           Picks=($latinPick | ForEach-Object { "$($_.File),$($_.Name)" }) },
  @{ Fam="Courier New";        Picks=($latinPick | ForEach-Object { "$($_.File),$($_.Name)" }) },
  # Unicode focal: Symbols, Math, Emoji -> đẩy lên đầu danh sách
  @{ Fam="Segoe UI Symbol";    Picks=($uniPick   | ForEach-Object { "$($_.File),$($_.Name)" }) }
)

foreach($t in $targets){
  foreach($root in @($HKLM_LINK,$HKCU_LINK)){
    try{
      $cur = (Get-ItemProperty -Path $root -Name $t.Fam -ErrorAction SilentlyContinue).$($t.Fam)
      if($null -eq $cur){ $cur = @() }
      # Prepend ngẫu nhiên (đổi thứ tự mỗi lần => đổi Fallback)
      $newOrder = @()
      $newOrder += ($t.Picks | Sort-Object { Get-Random })
      $newOrder += $cur
      # loại trùng (giữ thứ tự lần xuất hiện đầu)
      $seen = @{}
      $final = @()
      foreach($e in $newOrder){
        if(-not $seen.ContainsKey($e)){ $seen[$e]=$true; $final += $e }
      }
      Set-ItemProperty -Path $root -Name $t.Fam -Value $final -Force
      Log "INFO" ("SystemLink [{0}] ({1}) <= {2}" -f $t.Fam, ($root -like "HKLM:*" ? "HKLM" : "HKCU"), ($t.Picks -join " | "))
    }catch{
      Log "ERROR" ("SystemLink update failed [{0}]: {1}" -f $t.Fam, $_.Exception.Message)
    }
  }
}

# Substitutes: thay nhanh 1-1 để đảm bảo tác động rõ rệt
$substPairs = @(
  @{ Src="Segoe UI";            Dst=($latinPick | Select-Object -First 1).Name },
  @{ Src="Arial";               Dst=($latinPick | Select-Object -First 1).Name },
  @{ Src="Microsoft Sans Serif";Dst=($latinPick | Select-Object -First 1).Name },
  @{ Src="Times New Roman";     Dst=($latinPick | Where-Object { $_.Name -match "Serif|Merri|Gentium|Tinos|Crimson|Zilla|Spectral" } | Select-Object -First 1 -ExpandProperty Name) },
  @{ Src="Consolas";            Dst=($latinPick | Where-Object { $_.Name -match "Mono|Plex|Ubuntu Mono|Cousine" } | Select-Object -First 1 -ExpandProperty Name) },
  @{ Src="Courier New";         Dst=($latinPick | Where-Object { $_.Name -match "Mono|Plex|Ubuntu Mono|Cousine" } | Select-Object -First 1 -ExpandProperty Name) },
  @{ Src="Segoe UI Symbol";     Dst=($uniPick   | Where-Object { $_.Name -match "Symbols|Math|Music|Emoji" } | Select-Object -First 1 -ExpandProperty Name) },
  @{ Src="Cambria Math";        Dst=($uniPick   | Where-Object { $_.Name -match "Math|Symbols" } | Select-Object -First 1 -ExpandProperty Name) },
  @{ Src="Segoe UI Emoji";      Dst=(($uniPick   | Where-Object { $_.Name -match "Emoji" } | Select-Object -First 1).Name) }
) | Where-Object { $_.Dst -and $_.Dst.Trim() -ne "" }

foreach($p in $substPairs){
  foreach($root in @($HKLM_SUBST,$HKCU_SUBST)){
    try{
      Set-ItemProperty -Path $root -Name $p.Src -Value $p.Dst -Force
      Log "INFO" ("Substitute({0}): {1} -> {2}" -f ($root -like "HKLM:*" ? "HKLM" : "HKCU"), $p.Src, $p.Dst)
    }catch{
      Log "ERROR" ("Substitute failed {0}: {1}" -f $p.Src, $_.Exception.Message)
    }
  }
}

# --- Post-run hashes ---
$invAfter = Get-InventoryHash
$fallbackAfter = Get-FallbackHash
$cntAfter = (Get-FontRegistryList).Count

Log "INFO" ""
Log "INFO" "--- FONT METRICS (Registry list) ---"
Log "INFO" ("Count: {0} -> {1}  (? {2})" -f $cntBefore,$cntAfter,($cntAfter-$cntBefore))
Log "INFO" ""
Log "INFO" "--- HASHES ---"
Log "INFO" ("Inventory:  {0} -> {1}" -f $invBefore.Substring(0,32), $invAfter.Substring(0,32))
Log "INFO" ("Fallback :  {0} -> {1}" -f $fallbackBefore.Substring(0,32), $fallbackAfter.Substring(0,32))
Log "INFO" ("Font Metrics changed?   {0}" -f ($(if($invBefore -ne $invAfter){"YES"}else{"NO"})))
Log "INFO" ("Unicode Glyphs changed? {0}" -f ($(if($fallbackBefore -ne $fallbackAfter){"YES"}else{"NO"})))
Log "INFO" "Run finished."

# --- Cleanup nhẹ (giữ log & temp cho lần sau) ---
# Remove-Item -LiteralPath $TempDir -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
