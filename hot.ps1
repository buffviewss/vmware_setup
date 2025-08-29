# ===== Hotfix: Force Unicode fallback into generic families + flush caches (PS 5.x) =====
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
 ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) { Write-Host "Run as Administrator"; return }

try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
$FontsDir = "$env:WINDIR\Fonts"
$HKLM_FONTS = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
$HKLM_LINK  = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontLink\SystemLink"
$HKCU_LINK  = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontLink\SystemLink"
$HKLM_SUBST = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes"
$HKCU_SUBST = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes"

function Ensure-Key($p){ if(-not (Test-Path $p)){ New-Item -Path $p -Force | Out-Null } }
function Add-SystemLinkPrepend {
  param([string]$Root,[string]$Family,[string[]]$Entries)
  Ensure-Key $Root
  $cur = $null; try { $cur = (Get-ItemProperty -Path $Root -Name $Family -ErrorAction Stop).$Family } catch { $cur=@() }
  if($cur -is [string]){ $cur=@($cur) }
  # Đưa Entries lên đầu (xóa trùng)
  $seen=@{}; $out=@()
  foreach($e in ($Entries + $cur)){ if(-not $seen.ContainsKey($e)){ $seen[$e]=$true; $out+=$e } }
  if(-not (Get-ItemProperty -Path $Root -Name $Family -ErrorAction SilentlyContinue)){
    New-ItemProperty -Path $Root -Name $Family -Value $out -PropertyType MultiString -Force | Out-Null
  } else {
    Set-ItemProperty -Path $Root -Name $Family -Value $out -Force
  }
}

function Ensure-Font([string]$name,[string]$file,[string[]]$urls){
  $dst = Join-Path $FontsDir $file
  if(Test-Path $dst){ return $true }
  $tmp = Join-Path $env:TEMP $file
  foreach($u in $urls){
    try{
      Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile $tmp -TimeoutSec 120 -ErrorAction Stop
      if((Get-Item $tmp).Length -gt 10240){ Copy-Item $tmp $dst -Force; break }
    }catch{}
  }
  if(Test-Path $dst){
    $key = "$name (TrueType)"; New-ItemProperty -Path $HKLM_FONTS -Name $key -Value $file -PropertyType String -Force | Out-Null
    return $true
  }
  return $false
}

# Unicode pack (ưu tiên cao)
$U = @(
  @{ n="Noto Color Emoji"; f="NotoColorEmoji.ttf"; u=@('https://raw.githubusercontent.com/googlefonts/noto-emoji/main/fonts/NotoColorEmoji.ttf') },
  @{ n="Noto Sans Symbols2"; f="NotoSansSymbols2-Regular.ttf"; u=@('https://raw.githubusercontent.com/googlefonts/noto-fonts/main/hinted/ttf/NotoSansSymbols2/NotoSansSymbols2-Regular.ttf','https://notofonts.github.io/symbols/fonts/NotoSansSymbols2/hinted/ttf/NotoSansSymbols2-Regular.ttf') },
  @{ n="Noto Sans Math";    f="NotoSansMath-Regular.ttf";    u=@('https://raw.githubusercontent.com/googlefonts/noto-fonts/main/hinted/ttf/NotoSansMath/NotoSansMath-Regular.ttf') },
  @{ n="Noto Music";        f="NotoMusic-Regular.ttf";       u=@('https://raw.githubusercontent.com/googlefonts/noto-fonts/main/hinted/ttf/NotoMusic/NotoMusic-Regular.ttf') }
)
# Bảo đảm có mặt (nếu thiếu thì tải)
foreach($x in $U){ [void](Ensure-Font $x.n $x.f $x.u) }

# Build entry "file,name"
$UEntries = $U | ForEach-Object { "{0},{1}" -f $_.f,$_.n }

# Thêm vào mọi family generic mà fingerprint thường dùng
$Families = @(
  "Segoe UI","Segoe UI Variable","Arial","Times New Roman","Calibri",
  "Consolas","Courier New","Comic Sans MS","Impact","Microsoft Sans Serif",
  "Segoe UI Symbol","Segoe UI Emoji"
)

foreach($fam in $Families){
  Add-SystemLinkPrepend -Root $HKLM_LINK -Family $fam -Entries $UEntries
  Add-SystemLinkPrepend -Root $HKCU_LINK -Family $fam -Entries $UEntries
}

# Substitutes: chọn một sans/serif/mono đã cài để không bị rỗng
$regFonts = (Get-ItemProperty $HKLM_FONTS).psobject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object { $_.Name }
function Pick([string[]]$cands){ ($cands | Where-Object { $regFonts -match [Regex]::Escape(($_ + " (TrueType)")) } | Get-Random -Count 1) 2>$null }
$sans = (Pick @("Inter","Barlow","Alegreya Sans","Ubuntu","Cousine")) ; if(-not $sans){ $sans="Arial" }
$serf = (Pick @("Tinos","Zilla Slab","Gentium Plus","Spectral","Libre Baskerville","Crimson Text")) ; if(-not $serf){ $serf="Times New Roman" }
$mono = (Pick @("IBM Plex Mono","Inconsolata","Ubuntu Mono","Cousine")) ; if(-not $mono){ $mono="Consolas" }

$Pairs = @(
  @{ s="Segoe UI"; d=$sans }, @{ s="Arial"; d=$sans }, @{ s="Microsoft Sans Serif"; d=$sans },
  @{ s="Times New Roman"; d=$serf }, @{ s="Cambria"; d=$serf },
  @{ s="Consolas"; d=$mono }, @{ s="Courier New"; d=$mono },
  @{ s="Segoe UI Symbol"; d="Noto Sans Symbols2" },
  @{ s="Cambria Math"; d="Noto Sans Math" },
  @{ s="Segoe UI Emoji"; d="Noto Color Emoji" }
)
foreach($p in $Pairs){
  foreach($root in @($HKLM_SUBST,$HKCU_SUBST)){
    Ensure-Key $root
    Set-ItemProperty -Path $root -Name $p.s -Value $p.d -Force
  }
}

# Flush font caches để DirectWrite thấy danh sách mới
Write-Host "[*] Flushing Windows Font Cache..." -ForegroundColor Cyan
$svcs = @("FontCache3.0.0.0","FontCache")
foreach($s in $svcs){ Stop-Service $s -Force -ErrorAction SilentlyContinue }
$paths = @(
  "$env:LOCALAPPDATA\FontCache\*",
  "$env:WINDIR\ServiceProfiles\LocalService\AppData\Local\FontCache\*"
)
foreach($p in $paths){ Remove-Item $p -Force -ErrorAction SilentlyContinue }
foreach($s in $svcs){ Start-Service $s -ErrorAction SilentlyContinue }
Write-Host "[*] Done. Please close & reopen browsers." -ForegroundColor Green
