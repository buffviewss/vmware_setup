# =================== ADVANCED FONT FP ROTATOR v3.7 (PS 5.x, Full + Emoji) ===================
# Mục tiêu: Mỗi lần chạy đều cố gắng đổi được cả Inventory (nếu cài mới) và Fallback (Unicode Glyphs)
# - Cài tối đa 5 font EU/US + Unicode packs (Emoji/Symbols2/Math/Music)
# - Nếu font đã có: KHÔNG tải lại, NHƯNG sẽ random & set lại SystemLink EXACT (không cộng dồn)
# - Substitutes cũng random khác giá trị hiện tại khi có thể
# - Ghi Log vào Downloads, flush Font Cache, không mở browser
# ============================================================================================

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
 ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) { Write-Host "⚠️  Hãy chạy PowerShell bằng Run as Administrator." -f Yellow; return }

try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$StartTime  = Get-Date
$FontsDir   = "$env:WINDIR\Fonts"
$HKLM_FONTS = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
$HKLM_LINK  = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontLink\SystemLink"
$HKCU_LINK  = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontLink\SystemLink"
$HKLM_SUBST = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes"
$HKCU_SUBST = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes"
$LogPath    = Join-Path ([Environment]::GetFolderPath('UserProfile')) ("Downloads\FontFP_{0:yyyyMMdd_HHmmss}.log" -f $StartTime)

# ---------- Logger ----------
$sw = New-Object System.IO.StreamWriter($LogPath, $false, [Text.Encoding]::UTF8); $sw.AutoFlush=$true
function Log([string]$lvl,[string]$msg){
  $line = "[{0:yyyy-MM-dd HH:mm:ss}] [{1}] {2}" -f (Get-Date),$lvl,$msg
  $sw.WriteLine($line); Write-Host $line -ForegroundColor (if($lvl -eq 'ERROR'){'Red'} elseif($lvl -eq 'WARN'){'Yellow'} elseif($lvl -eq 'OK'){'Green'} else {'Cyan'})
}
function Close-Log { $sw.Flush(); $sw.Close() }
function Ensure-Key($p){ if(-not (Test-Path $p)){ New-Item -Path $p -Force | Out-Null } }

# ---------- Hash helpers ----------
function Sha32([string[]]$arr){
  $s=[string]::Join('|',($arr|%{ $_.ToString() }))
  $d=[System.Security.Cryptography.MD5]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($s))
  ($d|%{ $_.ToString('x2') }) -join ''
}
function Get-InventoryHash(){
  try{
    $items=(Get-ItemProperty $HKLM_FONTS).psobject.Properties|?{ $_.Name -notmatch '^PS' }|
      Sort-Object Name | % { "{0}={1}" -f $_.Name,$_.Value }
    Sha32 $items
  }catch{"NA"}
}
function Get-FallbackHash(){
  try{
    $families=@("Segoe UI","Segoe UI Variable","Arial","Times New Roman","Calibri",
                "Consolas","Courier New","Comic Sans MS","Impact","Microsoft Sans Serif",
                "Segoe UI Symbol","Segoe UI Emoji")
    $collect=@()
    foreach($root in @($HKLM_LINK,$HKCU_LINK)){
      if(Test-Path $root){
        foreach($f in $families){
          try{
            $v=(Get-ItemProperty -Path $root -Name $f -ErrorAction Stop).$f
            if($v -is [string]){ $v=@($v) }
            $collect += "{0}@{1}=[{2}]" -f $root,$f,([string]::Join(',', $v))
          }catch{}
        }
      }
    }
    Sha32 ($collect|Sort-Object)
  }catch{"NA"}
}

# ---------- Download & install ----------
function Download-IfNeeded([string]$outFile,[string[]]$urls){
  if(Test-Path $outFile){ return $true }
  $tmp = Join-Path $env:TEMP ([IO.Path]::GetFileName($outFile))
  foreach($u in $urls){
    Log "INFO" ("Download attempt: {0}" -f $u)
    try{
      Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile $tmp -TimeoutSec 180 -ErrorAction Stop
      if((Get-Item $tmp).Length -gt 8192){ Copy-Item $tmp $outFile -Force; Log "OK" ("Saved: {0}" -f $outFile); return $true }
      else { Log "WARN" "Downloaded file too small, skipping." }
    }catch{ Log "ERROR" ("Download error: {0}" -f $_.Exception.Message) }
  }
  return $false
}
function Install-TTF([string]$display,[string]$file,[string[]]$urls){
  $dst=Join-Path $FontsDir $file
  if(Test-Path $dst){ Log "INFO" ("Exists: {0}" -f $file); return $false }
  if(Download-IfNeeded $dst $urls){
    $key="{0} (TrueType)" -f $display
    New-ItemProperty -Path $HKLM_FONTS -Name $key -Value $file -PropertyType String -Force | Out-Null
    Log "OK" ("Installed: {0} -> {1}" -f $display,$file); return $true
  } else { Log "ERROR" ("Failed all URLs for: {0}" -f $display); return $false }
}

# ---------- SystemLink (EXACT set, randomized order) ----------
function Set-SystemLinkExact {
  param([string]$Root,[string]$Family,[string[]]$Entries)
  Ensure-Key $Root
  if(-not (Get-ItemProperty -Path $Root -Name $Family -ErrorAction SilentlyContinue)){
    New-ItemProperty -Path $Root -Name $Family -Value $Entries -PropertyType MultiString -Force | Out-Null
  } else {
    Set-ItemProperty -Path $Root -Name $Family -Value $Entries -Force
  }
  Log "INFO" ("SystemLink [{0}] <= {1}" -f $Family,([string]::Join(' | ',$Entries)))
}

# ---------- Substitutes: pick different if possible ----------
function Set-SubstituteRandom {
  param([string]$Root,[string]$Src,[string[]]$Candidates,[string]$Fallback)
  Ensure-Key $Root
  $cur=""; try{ $cur=(Get-ItemProperty -Path $Root -Name $Src -ErrorAction Stop).$Src }catch{}
  $pool = $Candidates | Where-Object { $_ -and $_ -ne $cur }
  $pick = if($pool){ $pool | Get-Random } else { $Fallback }
  Set-ItemProperty -Path $Root -Name $Src -Value $pick -Force
  Log "INFO" ("Substitute({0}): {1} -> {2}" -f "FontSubstitutes",$Src,$pick)
}

# ---------- Flush Font Cache ----------
function Flush-FontCache {
  Log "INFO" "Flushing Windows Font Cache..."
  $sv=@("FontCache3.0.0.0","FontCache")
  foreach($s in $sv){ Stop-Service $s -Force -ErrorAction SilentlyContinue }
  $paths=@("$env:LOCALAPPDATA\FontCache\*",
           "$env:WINDIR\ServiceProfiles\LocalService\AppData\Local\FontCache\*")
  foreach($p in $paths){ Remove-Item $p -Force -ErrorAction SilentlyContinue }
  foreach($s in $sv){ Start-Service $s -ErrorAction SilentlyContinue }
  Log "OK" "Font cache flushed."
}

# ---------- Font lists ----------
$Latin=@(
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
$Uni=@(
  @{ n="Noto Color Emoji";   f="NotoColorEmoji.ttf";               u=@("https://raw.githubusercontent.com/googlefonts/noto-emoji/main/fonts/NotoColorEmoji.ttf") },
  @{ n="Noto Sans Symbols2"; f="NotoSansSymbols2-Regular.ttf";     u=@("https://raw.githubusercontent.com/googlefonts/noto-fonts/main/hinted/ttf/NotoSansSymbols2/NotoSansSymbols2-Regular.ttf","https://notofonts.github.io/symbols/fonts/NotoSansSymbols2/hinted/ttf/NotoSansSymbols2-Regular.ttf") },
  @{ n="Noto Sans Math";     f="NotoSansMath-Regular.ttf";         u=@("https://raw.githubusercontent.com/googlefonts/noto-fonts/main/hinted/ttf/NotoSansMath/NotoSansMath-Regular.ttf") },
  @{ n="Noto Music";         f="NotoMusic-Regular.ttf";            u=@("https://raw.githubusercontent.com/googlefonts/noto-fonts/main/hinted/ttf/NotoMusic/NotoMusic-Regular.ttf") }
)

# ---------- Baseline ----------
Log "INFO" ("=== RUN {0:yyyy-MM-dd HH:mm:ss} ===" -f $StartTime)
Log "INFO" ("OS: {0}  PS: {1}" -f ([Environment]::OSVersion.VersionString),$PSVersionTable.PSVersion)
$beforeCount = (Get-ItemProperty $HKLM_FONTS).psobject.Properties | ?{ $_.Name -notmatch '^PS' } | Measure-Object | % Count
$beforeInv = Get-InventoryHash
$beforeFb  = Get-FallbackHash
Log "INFO" ("Current fonts: {0}" -f $beforeCount)
Log "INFO" ("Inventory Hash: {0}..." -f $beforeInv)
Log "INFO" ("Fallback Hash : {0}..." -f $beforeFb)

# ---------- Install up to 5 fonts ----------
$maxInstall = 5; $installedNow = 0

# Ưu tiên Unicode: luôn đảm bảo có Emoji + Symbols2 + (Math/Music random)
$wantUni = @("Noto Color Emoji","Noto Sans Symbols2") + ((@("Noto Sans Math","Noto Music") | Get-Random -Count 1))
foreach($n in $wantUni){
  $x = $Uni | Where-Object { $_.n -eq $n } | Select-Object -First 1
  if($x -and $installedNow -lt $maxInstall){
    if(Install-TTF $x.n $x.f $x.u){ $installedNow++ }
  }
}

# Bổ sung Latin nếu còn slot
if($installedNow -lt $maxInstall){
  $need = $maxInstall - $installedNow
  foreach($x in ($Latin | Get-Random -Count $need)){
    if(Install-TTF $x.n $x.f $x.u){ $installedNow++ }
    if($installedNow -ge $maxInstall){ break }
  }
}

# ---------- Build available Unicode entries (chỉ lấy những file đang có) ----------
$UHave=@()
foreach($x in $Uni){
  if(Test-Path (Join-Path $FontsDir $x.f)){ $UHave += ("{0},{1}" -f $x.f,$x.n) }
}
# Bắt buộc phải có emoji & symbols2 nếu có
$UCore = $UHave | Where-Object { $_ -like "NotoColorEmoji.ttf,*" -or $_ -like "NotoSansSymbols2-Regular.ttf,*" }
$UEtc  = $UHave | Where-Object { $_ -notin $UCore }
# Tạo danh sách cuối: Emoji + Symbols2 + (2 mục ngẫu nhiên từ phần còn lại nếu có), rồi trộn thứ tự
$pick = @()
$pick += $UCore
if($UEtc.Count -gt 0){ $pick += ($UEtc | Get-Random -Count ([Math]::Min(2,$UEtc.Count))) }
# shuffle
$pick = $pick | Sort-Object { Get-Random }

# ---------- Apply SystemLink EXACT (randomized) ----------
$Families=@("Segoe UI","Segoe UI Variable","Arial","Times New Roman","Calibri",
            "Consolas","Courier New","Comic Sans MS","Impact","Microsoft Sans Serif",
            "Segoe UI Symbol","Segoe UI Emoji")

foreach($fam in $Families){
  foreach($root in @($HKLM_LINK,$HKCU_LINK)){
    Set-SystemLinkExact -Root $root -Family $fam -Entries $pick
  }
}

# ---------- Substitutes random (khác giá trị hiện tại nếu được) ----------
# Lấy danh sách font đã cài để làm candidate
$regNames=(Get-ItemProperty $HKLM_FONTS).psobject.Properties|?{ $_.Name -notmatch '^PS' }|% Name
function HasFont([string]$fam){ ($regNames | Where-Object { $_ -like "$fam (TrueType)" }) -ne $null }

$sans  = @("Alegreya Sans","Barlow","Ubuntu","Cousine") | Where-Object { HasFont $_ }
$serif = @("Tinos","Zilla Slab","Spectral","Gentium Plus","Gentium Book Plus","Libre Baskerville","Crimson Text") | Where-Object { HasFont $_ }
$mono  = @("IBM Plex Mono","Inconsolata","Ubuntu Mono","Cousine") | Where-Object { HasFont $_ }

foreach($root in @($HKLM_SUBST,$HKCU_SUBST)){
  Set-SubstituteRandom $root "Segoe UI"            $sans  "Arial"
  Set-SubstituteRandom $root "Microsoft Sans Serif" $sans  "Arial"
  Set-SubstituteRandom $root "Arial"               $sans  "Arial"
  Set-SubstituteRandom $root "Times New Roman"     $serif "Times New Roman"
  Set-SubstituteRandom $root "Cambria"             $serif "Cambria"
  Set-SubstituteRandom $root "Consolas"            $mono  "Consolas"
  Set-SubstituteRandom $root "Courier New"         $mono  "Courier New"
  # Unicode roles
  Set-SubstituteRandom $root "Segoe UI Symbol" (@("Noto Sans Symbols2")) "Noto Sans Symbols2"
  Set-SubstituteRandom $root "Cambria Math"    (@("Noto Sans Math"))      "Noto Sans Math"
  Set-SubstituteRandom $root "Segoe UI Emoji"  (@("Noto Color Emoji"))    "Noto Color Emoji"
}

# ---------- Flush cache ----------
Flush-FontCache

# ---------- Verify, retry rotate if fallback unchanged ----------
$afterCount1 = (Get-ItemProperty $HKLM_FONTS).psobject.Properties | ?{ $_.Name -notmatch '^PS' } | Measure-Object | % Count
$afterInv1 = Get-InventoryHash
$afterFb1  = Get-FallbackHash

if($afterFb1 -eq $beforeFb){
  Log "WARN" "Fallback hash unchanged, re-randomizing order once..."
  $pick = ($pick | Sort-Object { Get-Random })
  foreach($fam in $Families){
    foreach($root in @($HKLM_LINK,$HKCU_LINK)){
      Set-SystemLinkExact -Root $root -Family $fam -Entries $pick
    }
  }
  Flush-FontCache
  $afterInv1 = Get-InventoryHash
  $afterFb1  = Get-FallbackHash
}

# ---------- Results ----------
Write-Host ""
Log "INFO" "--- RESULTS ---"
Log "INFO" ("Fonts count: {0} -> {1}  (Δ {2})" -f $beforeCount,$afterCount1,($afterCount1-$beforeCount))
Log "INFO" ("Inventory:  {0} -> {1}" -f $beforeInv,$afterInv1)
Log "INFO" ("Fallback :  {0} -> {1}" -f $beforeFb,$afterFb1)
Log "OK"   ("Font Metrics changed?   {0}" -f ($(if($beforeInv -ne $afterInv1){"YES"}else{"NO"})))
Log "OK"   ("Unicode Glyphs changed? {0}" -f ($(if($beforeFb  -ne $afterFb1) {"YES"}else{"NO"})))
Log "INFO" ("Installed this run: {0} (max {1})" -f $installedNow,$maxInstall)
Log "INFO" ("Log saved: {0}" -f $LogPath)
# ============================================================================================
