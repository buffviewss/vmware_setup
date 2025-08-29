# ===================== ADVANCED FONT FINGERPRINT ROTATOR — FULL (PS 5.x) =====================
# - EU/US Latin font list (chỉ .ttf nhẹ), + gói Unicode (Emoji/Symbols2/Math/Music)
# - Cài tối đa 5 font/lần chạy (emoji được tính, nếu đã có sẽ không tải lại)
# - Cập nhật FontLink + FontSubstitutes cho generic families
# - Tính hash trước/sau: Inventory (registry fonts) + Fallback (SystemLink)
# - Ghi log vào: $HOME\Downloads\FontFP_yyyyMMdd_HHmmss.log
# - Không mở trình duyệt; tự flush Windows Font Cache sau khi cấu hình
# =============================================================================================

# --- Guard & setup ---
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
 ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) { Write-Host "⚠️  Hãy chạy PowerShell bằng Run as Administrator." -ForegroundColor Yellow; return }

try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$StartTime = Get-Date
$FontsDir  = "$env:WINDIR\Fonts"
$HKLM_FONTS = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
$HKLM_LINK  = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontLink\SystemLink"
$HKCU_LINK  = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontLink\SystemLink"
$HKLM_SUBST = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes"
$HKCU_SUBST = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes"
$LogPath = Join-Path ([Environment]::GetFolderPath('UserProfile')) ("Downloads\FontFP_{0:yyyyMMdd_HHmmss}.log" -f $StartTime)

# --- Mini logger ---
$sw = New-Object System.IO.StreamWriter($LogPath, $false, [Text.Encoding]::UTF8)
$sw.AutoFlush = $true
function Log([string]$lvl,[string]$msg){ 
  $line = "[{0:yyyy-MM-dd HH:mm:ss}] [{1}] {2}" -f (Get-Date),$lvl,$msg
  $sw.WriteLine($line); Write-Host $line -ForegroundColor (
    if($lvl -eq 'ERROR'){'Red'} elseif($lvl -eq 'WARN'){'Yellow'} elseif($lvl -eq 'OK'){'Green'} else {'Cyan'})
}
function Close-Log { $sw.Flush(); $sw.Close() }

function Ensure-Key($p){ if(-not (Test-Path $p)){ New-Item -Path $p -Force | Out-Null } }

function Sha32([string[]]$arr){
  $s = [string]::Join('|', ($arr | ForEach-Object { $_.ToString() }))
  $md5 = [System.Security.Cryptography.MD5]::Create()
  ($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($s)) | ForEach-Object { $_.ToString("x2") }) -join '' 
}

function Get-InventoryHash(){
  try{
    $items = (Get-ItemProperty $HKLM_FONTS).psobject.Properties |
      Where-Object { $_.Name -notmatch '^PS' } |
      Sort-Object Name | ForEach-Object { "{0}={1}" -f $_.Name,$_.Value }
    return Sha32 $items
  } catch { return "NA" }
}

function Get-FallbackHash(){
  try{
    $families = @("Segoe UI","Segoe UI Variable","Arial","Times New Roman","Calibri",
                  "Consolas","Courier New","Comic Sans MS","Impact","Microsoft Sans Serif",
                  "Segoe UI Symbol","Segoe UI Emoji")
    $collect = @()
    foreach($r in @($HKLM_LINK,$HKCU_LINK)){
      if(Test-Path $r){
        foreach($f in $families){
          try{
            $v = (Get-ItemProperty -Path $r -Name $f -ErrorAction Stop).$f
            if($v -is [string]){ $v=@($v) }
            $collect += "{0}@{1}=[{2}]" -f $r,$f,([string]::Join(',', $v))
          } catch {}
        }
      }
    }
    return Sha32 ($collect | Sort-Object)
  } catch { return "NA" }
}

function Download-IfNeeded([string]$outFile,[string[]]$urls){
  if(Test-Path $outFile){ return $true }
  $tmp = Join-Path $env:TEMP ([IO.Path]::GetFileName($outFile))
  foreach($u in $urls){
    Log "INFO" ("Download attempt: {0}" -f $u)
    try{
      Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile $tmp -TimeoutSec 180 -ErrorAction Stop
      if((Get-Item $tmp).Length -gt 10240){ Copy-Item $tmp $outFile -Force; Log "OK" ("Saved: {0}" -f $outFile); return $true }
      else { Log "WARN" "Downloaded file too small, skipping." }
    }catch{ Log "ERROR" ("Download error: {0}" -f $_.Exception.Message) }
  }
  return $false
}

function Install-TTF([string]$display,[string]$file,[string[]]$urls){
  $dst = Join-Path $FontsDir $file
  if(Test-Path $dst){ Log "INFO" ("Exists: {0}" -f $file); return $false }
  if(Download-IfNeeded $dst $urls){
    $key = "{0} (TrueType)" -f $display
    New-ItemProperty -Path $HKLM_FONTS -Name $key -Value $file -PropertyType String -Force | Out-Null
    Log "OK" ("Installed: {0} -> {1}" -f $display,$file)
    return $true
  } else {
    Log "ERROR" ("Failed all URLs for: {0}" -f $display)
    return $false
  }
}

function Add-SystemLinkPrepend {
  param([string]$Root,[string]$Family,[string[]]$Entries)
  Ensure-Key $Root
  $cur = $null; try { $cur = (Get-ItemProperty -Path $Root -Name $Family -ErrorAction Stop).$Family } catch { $cur=@() }
  if($cur -is [string]){ $cur=@($cur) }
  # đưa Entries lên đầu (loại trùng)
  $seen=@{}; $out=@()
  foreach($e in ($Entries + $cur)){ if(-not $seen.ContainsKey($e)){ $seen[$e]=$true; $out+=$e } }
  if(-not (Get-ItemProperty -Path $Root -Name $Family -ErrorAction SilentlyContinue)){
    New-ItemProperty -Path $Root -Name $Family -Value $out -PropertyType MultiString -Force | Out-Null
  } else {
    Set-ItemProperty -Path $Root -Name $Family -Value $out -Force
  }
  Log "INFO" ("SystemLink [{0}] <= {1}" -f $Family, ([string]::Join(' | ',$Entries)))
}

function Set-Substitute([string]$Root,[string]$Src,[string]$Dst){
  Ensure-Key $Root
  Set-ItemProperty -Path $Root -Name $Src -Value $Dst -Force
  Log "INFO" ("Substitute({0}): {1} -> {2}" -f ($(Split-Path $Root -Leaf),$Src,$Dst))
}

function Flush-FontCache {
  Log "INFO" "Flushing Windows Font Cache..."
  $sv = @("FontCache3.0.0.0","FontCache")
  foreach($s in $sv){ Stop-Service $s -Force -ErrorAction SilentlyContinue }
  $paths = @(
    "$env:LOCALAPPDATA\FontCache\*",
    "$env:WINDIR\ServiceProfiles\LocalService\AppData\Local\FontCache\*"
  )
  foreach($p in $paths){ Remove-Item $p -Force -ErrorAction SilentlyContinue }
  foreach($s in $sv){ Start-Service $s -ErrorAction SilentlyContinue }
  Log "OK" "Font cache flushed."
}

# ---------------- Data: EU/US Latin (.ttf small) ----------------
$Latin = @(
  @{ n="Inconsolata";         f="Inconsolata-Regular.ttf";      u=@("https://raw.githubusercontent.com/google/fonts/main/ofl/inconsolata/static/Inconsolata-Regular.ttf") },
  @{ n="Zilla Slab";          f="ZillaSlab-Regular.ttf";        u=@("https://raw.githubusercontent.com/google/fonts/main/ofl/zillaslab/ZillaSlab-Regular.ttf") },
  @{ n="Tinos";               f="Tinos-Regular.ttf";            u=@("https://raw.githubusercontent.com/google/fonts/main/apache/tinos/Tinos-Regular.ttf") },
  @{ n="Spectral";            f="Spectral-Regular.ttf";         u=@("https://raw.githubusercontent.com/google/fonts/main/ofl/spectral/Spectral-Regular.ttf") },
  @{ n="Alegreya Sans";       f="AlegreyaSans-Regular.ttf";     u=@("https://raw.githubusercontent.com/google/fonts/main/ofl/alegreyasans/AlegreyaSans-Regular.ttf") },
  @{ n="Fira Sans";           f="FiraSans-Regular.ttf";         u=@("https://raw.githubusercontent.com/google/fonts/main/ofl/firasans/FiraSans-Regular.ttf") },
  @{ n="Barlow";              f="Barlow-Regular.ttf";           u=@("https://raw.githubusercontent.com/google/fonts/main/ofl/barlow/Barlow-Regular.ttf") },
  @{ n="Ubuntu";              f="Ubuntu-Regular.ttf";           u=@("https://raw.githubusercontent.com/google/fonts/main/ufl/ubuntu/Ubuntu-Regular.ttf") },
  @{ n="Ubuntu Mono";         f="UbuntuMono-Regular.ttf";       u=@("https://raw.githubusercontent.com/google/fonts/main/ufl/ubuntumono/UbuntuMono-Regular.ttf") },
  @{ n="Cousine";             f="Cousine-Regular.ttf";          u=@("https://raw.githubusercontent.com/google/fonts/main/apache/cousine/Cousine-Regular.ttf") },
  @{ n="IBM Plex Mono";       f="IBMPlexMono-Regular.ttf";      u=@("https://raw.githubusercontent.com/google/fonts/main/ofl/ibmplexmono/IBMPlexMono-Regular.ttf") },
  @{ n="Gentium Plus";        f="GentiumPlus-Regular.ttf";      u=@("https://raw.githubusercontent.com/google/fonts/main/ofl/gentiumplus/GentiumPlus-Regular.ttf") },
  @{ n="Gentium Book Plus";   f="GentiumBookPlus-Regular.ttf";  u=@("https://raw.githubusercontent.com/google/fonts/main/ofl/gentiumbookplus/GentiumBookPlus-Regular.ttf") },
  @{ n="Bebas Neue";          f="BebasNeue-Regular.ttf";        u=@("https://raw.githubusercontent.com/google/fonts/main/ofl/bebasneue/BebasNeue-Regular.ttf") },
  @{ n="Titillium Web";       f="TitilliumWeb-Regular.ttf";     u=@("https://raw.githubusercontent.com/google/fonts/main/ofl/titilliumweb/TitilliumWeb-Regular.ttf") },
  @{ n="Crimson Text";        f="CrimsonText-Regular.ttf";      u=@("https://raw.githubusercontent.com/google/fonts/main/ofl/crimsontext/CrimsonText-Regular.ttf") },
  @{ n="Libre Baskerville";   f="LibreBaskerville-Regular.ttf"; u=@("https://raw.githubusercontent.com/google/fonts/main/ofl/librebaskerville/LibreBaskerville-Regular.ttf") }
)

# ---------------- Unicode pack (Emoji/Math/Symbols/Music) ----------------
$Uni = @(
  @{ n="Noto Color Emoji";         f="NotoColorEmoji.ttf";                u=@("https://raw.githubusercontent.com/googlefonts/noto-emoji/main/fonts/NotoColorEmoji.ttf") },
  @{ n="Noto Sans Symbols2";       f="NotoSansSymbols2-Regular.ttf";      u=@("https://raw.githubusercontent.com/googlefonts/noto-fonts/main/hinted/ttf/NotoSansSymbols2/NotoSansSymbols2-Regular.ttf","https://notofonts.github.io/symbols/fonts/NotoSansSymbols2/hinted/ttf/NotoSansSymbols2-Regular.ttf") },
  @{ n="Noto Sans Math";           f="NotoSansMath-Regular.ttf";          u=@("https://raw.githubusercontent.com/googlefonts/noto-fonts/main/hinted/ttf/NotoSansMath/NotoSansMath-Regular.ttf") },
  @{ n="Noto Music";               f="NotoMusic-Regular.ttf";             u=@("https://raw.githubusercontent.com/googlefonts/noto-fonts/main/hinted/ttf/NotoMusic/NotoMusic-Regular.ttf") }
)

# ---------------- Baseline info ----------------
Log "INFO" ("=== RUN {0:yyyy-MM-dd HH:mm:ss} ===" -f $StartTime)
Log "INFO" ("OS: {0}  PS: {1}" -f ([Environment]::OSVersion.VersionString), $PSVersionTable.PSVersion)
$beforeCount = (Get-ItemProperty $HKLM_FONTS).psobject.Properties | Where-Object { $_.Name -notmatch '^PS' } | Measure-Object | Select-Object -ExpandProperty Count
$beforeInv = Get-InventoryHash
$beforeFb  = Get-FallbackHash
Log "INFO" ("Current fonts: {0}" -f $beforeCount)
Log "INFO" ("Inventory Hash: {0}..." -f $beforeInv)
Log "INFO" ("Fallback Hash : {0}..." -f $beforeFb)

# ---------------- Install up to 5 fonts ----------------
$maxInstall = 5
$installedNow = 0

# Always prioritize Unicode variation: Emoji + Symbols2 + (Math or Music randomly)
$pickUni = @()
# Emoji always included
$pickUni += ($Uni | Where-Object { $_.n -eq 'Noto Color Emoji' })
# Symbols2 always included
$pickUni += ($Uni | Where-Object { $_.n -eq 'Noto Sans Symbols2' })
# Random choose one more from {Math, Music}
$pickUni += ($Uni | Where-Object { $_.n -ne 'Noto Color Emoji' -and $_.n -ne 'Noto Sans Symbols2' } | Get-Random -Count 1)

foreach($x in $pickUni){
  if($installedNow -ge $maxInstall){ break }
  if(Install-TTF $x.n $x.f $x.u){ $installedNow++ }
}

# Fill remaining slots with Latin (EU/US) randomly
if($installedNow -lt $maxInstall){
  $need = $maxInstall - $installedNow
  $latinPick = $Latin | Get-Random -Count $need
  foreach($x in $latinPick){
    if(Install-TTF $x.n $x.f $x.u){ $installedNow++ }
    if($installedNow -ge $maxInstall){ break }
  }
}

# ---------------- Configure FontLink (prepend Unicode fallbacks) ----------------
# Build "file,name" entries from Unicode set (dùng luôn dù đã tồn tại để đảm bảo trỏ đúng)
$UEntries = @()
foreach($x in $Uni){ $UEntries += ("{0},{1}" -f $x.f,$x.n) }

$Families = @(
  "Segoe UI","Segoe UI Variable","Arial","Times New Roman","Calibri",
  "Consolas","Courier New","Comic Sans MS","Impact","Microsoft Sans Serif",
  "Segoe UI Symbol","Segoe UI Emoji"
)
foreach($fam in $Families){
  Add-SystemLinkPrepend -Root $HKLM_LINK -Family $fam -Entries $UEntries
  Add-SystemLinkPrepend -Root $HKCU_LINK -Family $fam -Entries $UEntries
}

# ---------------- Substitutes (để generic đổi thật) ----------------
# Chọn một sans/serif/mono sẵn có; nếu thiếu dùng mặc định hệ thống
$regFonts = (Get-ItemProperty $HKLM_FONTS).psobject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object { $_.Name }
function HasFont([string]$fam){ ($regFonts | Where-Object { $_ -like "$fam (TrueType)" }) -ne $null }

$sans  = @("Alegreya Sans","Barlow","Ubuntu","Cousine") | Where-Object { HasFont $_ } | Get-Random -Count 1 -ErrorAction SilentlyContinue
if(-not $sans){ $sans = "Arial" }

$serif = @("Tinos","Zilla Slab","Spectral","Gentium Plus","Gentium Book Plus","Libre Baskerville","Crimson Text") | Where-Object { HasFont $_ } | Get-Random -Count 1 -ErrorAction SilentlyContinue
if(-not $serif){ $serif = "Times New Roman" }

$mono  = @("IBM Plex Mono","Inconsolata","Ubuntu Mono","Cousine") | Where-Object { HasFont $_ } | Get-Random -Count 1 -ErrorAction SilentlyContinue
if(-not $mono){ $mono = "Consolas" }

foreach($root in @($HKLM_SUBST,$HKCU_SUBST)){
  Set-Substitute $root "Segoe UI"            $sans
  Set-Substitute $root "Microsoft Sans Serif" $sans
  Set-Substitute $root "Arial"               $sans
  Set-Substitute $root "Times New Roman"     $serif
  Set-Substitute $root "Cambria"             $serif
  Set-Substitute $root "Consolas"            $mono
  Set-Substitute $root "Courier New"         $mono
  Set-Substitute $root "Segoe UI Symbol"     "Noto Sans Symbols2"
  Set-Substitute $root "Cambria Math"        "Noto Sans Math"
  Set-Substitute $root "Segoe UI Emoji"      "Noto Color Emoji"
}

# ---------------- Flush Font Cache ----------------
Flush-FontCache

# ---------------- Results ----------------
$afterCount = (Get-ItemProperty $HKLM_FONTS).psobject.Properties | Where-Object { $_.Name -notmatch '^PS' } | Measure-Object | Select-Object -ExpandProperty Count
$afterInv = Get-InventoryHash
$afterFb  = Get-FallbackHash

Write-Host ""
Log "INFO" "--- RESULTS ---"
Log "INFO" ("Fonts count: {0} -> {1}  (Δ {2})" -f $beforeCount,$afterCount,($afterCount-$beforeCount))
Log "INFO" ("Inventory:  {0} -> {1}" -f $beforeInv,$afterInv)
Log "INFO" ("Fallback :  {0} -> {1}" -f $beforeFb,$afterFb)
Log "OK"   ("Font Metrics changed?   {0}" -f ($(if($beforeInv -ne $afterInv){"YES"}else{"NO"})))
Log "OK"   ("Unicode Glyphs changed? {0}" -f ($(if($beforeFb  -ne $afterFb) {"YES"}else{"NO"})))
Log "INFO" ("Installed this run: {0} (max {1})" -f $installedNow,$maxInstall)
Log "INFO" ("Log saved: {0}" -f $LogPath)
# ---------------------------------------------------------------------------------------------
