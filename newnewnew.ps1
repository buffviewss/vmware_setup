<# ===================================================================
  ADVANCED FONT FINGERPRINT ROTATOR v3.9-FULL
  Goal: MỖI LẦN CHẠY đều đổi được:
   - Font Metrics Fingerprint (Inventory hash)  => bằng cách gỡ/cài mới "font của script"
   - Unicode Glyphs Fingerprint (Fallback hash) => bằng cách random SystemLink/Substitutes + patch Chromium
  Lưu ý:
   - KHÔNG xoá font hệ thống. Chỉ gỡ các font do script đã cài (được đánh dấu).
   - Tải TTF/OTF trực tiếp (có mirror jsDelivr) để giảm 404.
   - Đóng Chrome/Edge và vá default fonts để Chromium áp dụng ngay.
   - Log: %USERPROFILE%\Downloads\log.txt
=================================================================== #>

param(
  [int]$InstallMin   = 12,
  [int]$InstallMax   = 18,
  [int]$UninstallMin = 6,
  [int]$UninstallMax = 10,
  [switch]$KeepGrowth = $false,     # true = không gỡ font cũ (inventory vẫn đổi nhưng file tăng dần)
  [switch]$NoChromiumFonts = $false,
  [switch]$NoForceClose    = $false,
  [string]$ChromeProfile = "Default",
  [string]$EdgeProfile   = "Default",
  [int]$MaxRounds = 3               # số vòng thử thêm nếu hash chưa đổi
)

# ---- Admin check ----
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
   ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
  Write-Host "ERROR: Run PowerShell as Administrator!" -ForegroundColor Red
  Read-Host "Press Enter to exit"; exit 1
}

$Version = "3.9-FULL"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

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

# ---- Paths & State ----
$TempDir  = "$env:TEMP\FontRotator"
$FontsDir = "$env:SystemRoot\Fonts"
$StateKey = "HKLM:\SOFTWARE\FontRotator"
if (!(Test-Path $TempDir)) { New-Item -ItemType Directory -Path $TempDir -Force | Out-Null }
if (!(Test-Path $StateKey)) { New-Item -Path $StateKey -Force | Out-Null }

# ---- DB: NHIỀU LINK TTF/OTF (mỗi item có >=1 mirror) ----
#  Ưu tiên: Math/Symbols/Emoji (gây khác biệt glyph), thêm Mono/Sans/Serif Âu–Mỹ
$DB = @{
  SymbolsMath = @(
    @{Name="Noto Sans Math";Urls=@(
      "https://raw.githubusercontent.com/googlefonts/noto-fonts/main/hinted/ttf/NotoSansMath/NotoSansMath-Regular.ttf",
      "https://cdn.jsdelivr.net/gh/googlefonts/noto-fonts@main/hinted/ttf/NotoSansMath/NotoSansMath-Regular.ttf"
    )}
    @{Name="Noto Sans Symbols 2";Urls=@(
      "https://raw.githubusercontent.com/googlefonts/noto-fonts/main/hinted/ttf/NotoSansSymbols2/NotoSansSymbols2-Regular.ttf",
      "https://cdn.jsdelivr.net/gh/googlefonts/noto-fonts@main/hinted/ttf/NotoSansSymbols2/NotoSansSymbols2-Regular.ttf"
    )}
    @{Name="Noto Music";Urls=@(
      "https://raw.githubusercontent.com/googlefonts/noto-fonts/main/hinted/ttf/NotoMusic/NotoMusic-Regular.ttf",
      "https://cdn.jsdelivr.net/gh/googlefonts/noto-fonts@main/hinted/ttf/NotoMusic/NotoMusic-Regular.ttf"
    )}
    @{Name="XITS Math";Urls=@(
      "https://github.com/khaledhosny/xits-fonts/releases/download/v1.301/xits-math-otf-1.301.zip"  # zip fallback—bị skip bởi installer, nhưng để tăng entropy nguồn; ta bổ sung Libertinus để chắc chắn có OTF
    )}
    @{Name="Libertinus Math";Urls=@(
      "https://github.com/alerque/libertinus/releases/download/v7.040/LibertinusMath-Regular.otf"
    )}
  )
  Emoji = @(
    @{Name="Noto Color Emoji";Urls=@(
      "https://raw.githubusercontent.com/googlefonts/noto-emoji/main/fonts/NotoColorEmoji.ttf",
      "https://cdn.jsdelivr.net/gh/googlefonts/noto-emoji@main/fonts/NotoColorEmoji.ttf"
    )}
  )
  Mono = @(
    @{Name="JetBrains Mono";Urls=@(
      "https://github.com/google/fonts/raw/main/ofl/jetbrainsmono/static/JetBrainsMono-Regular.ttf",
      "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/jetbrainsmono/static/JetBrainsMono-Regular.ttf"
    )}
    @{Name="Source Code Pro";Urls=@(
      "https://github.com/google/fonts/raw/main/ofl/sourcecodepro/static/SourceCodePro-Regular.ttf",
      "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/sourcecodepro/static/SourceCodePro-Regular.ttf"
    )}
    @{Name="Inconsolata";Urls=@(
      "https://github.com/google/fonts/raw/main/ofl/inconsolata/static/Inconsolata-Regular.ttf",
      "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/inconsolata/static/Inconsolata-Regular.ttf"
    )}
    @{Name="Cousine";Urls=@(
      "https://github.com/google/fonts/raw/main/apache/cousine/Cousine%5Bwght%5D.ttf",
      "https://cdn.jsdelivr.net/gh/google/fonts@main/apache/cousine/Cousine%5Bwght%5D.ttf"
    )}
    @{Name="Anonymous Pro";Urls=@(
      "https://github.com/google/fonts/raw/main/ofl/anonymouspro/AnonymousPro-Regular.ttf",
      "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/anonymouspro/AnonymousPro-Regular.ttf"
    )}
  )
  Sans = @(
    @{Name="Inter";Urls=@(
      "https://github.com/google/fonts/raw/main/ofl/inter/static/Inter-Regular.ttf",
      "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/inter/static/Inter-Regular.ttf"
    )}
    @{Name="Open Sans";Urls=@(
      "https://github.com/google/fonts/raw/main/ofl/opensans/static/OpenSans-Regular.ttf",
      "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/opensans/static/OpenSans-Regular.ttf"
    )}
    @{Name="Noto Sans";Urls=@(
      "https://github.com/google/fonts/raw/main/ofl/notosans/static/NotoSans-Regular.ttf",
      "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/notosans/static/NotoSans-Regular.ttf"
    )}
    @{Name="Roboto";Urls=@(
      "https://github.com/google/fonts/raw/main/apache/roboto/static/Roboto-Regular.ttf",
      "https://cdn.jsdelivr.net/gh/google/fonts@main/apache/roboto/static/Roboto-Regular.ttf"
    )}
    @{Name="Work Sans";Urls=@(
      "https://github.com/google/fonts/raw/main/ofl/worksans/static/WorkSans-Regular.ttf",
      "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/worksans/static/WorkSans-Regular.ttf"
    )}
    @{Name="DM Sans";Urls=@(
      "https://github.com/google/fonts/raw/main/ofl/dmsans/static/DMSans-Regular.ttf",
      "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/dmsans/static/DMSans-Regular.ttf"
    )}
    @{Name="Poppins";Urls=@(
      "https://github.com/google/fonts/raw/main/ofl/poppins/Poppins%5Bwght%5D.ttf",
      "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/poppins/Poppins%5Bwght%5D.ttf"
    )}
    @{Name="Karla";Urls=@(
      "https://github.com/google/fonts/raw/main/ofl/karla/static/Karla-Regular.ttf",
      "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/karla/static/Karla-Regular.ttf"
    )}
    @{Name="Manrope";Urls=@(
      "https://github.com/google/fonts/raw/main/ofl/manrope/static/Manrope-Regular.ttf",
      "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/manrope/static/Manrope-Regular.ttf"
    )}
    @{Name="Urbanist";Urls=@(
      "https://github.com/google/fonts/raw/main/ofl/urbanist/static/Urbanist-Regular.ttf",
      "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/urbanist/static/Urbanist-Regular.ttf"
    )}
    @{Name="Nunito Sans";Urls=@(
      "https://github.com/google/fonts/raw/main/ofl/nunitosans/static/NunitoSans-Regular.ttf",
      "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/nunitosans/static/NunitoSans-Regular.ttf"
    )}
    @{Name="Mulish";Urls=@(
      "https://github.com/google/fonts/raw/main/ofl/mulish/static/Mulish-Regular.ttf",
      "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/mulish/static/Mulish-Regular.ttf"
    )}
    @{Name="Rubik";Urls=@(
      "https://github.com/google/fonts/raw/main/ofl/rubik/static/Rubik-Regular.ttf",
      "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/rubik/static/Rubik-Regular.ttf"
    )}
    @{Name="Cabin";Urls=@(
      "https://github.com/google/fonts/raw/main/ofl/cabin/static/Cabin-Regular.ttf",
      "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/cabin/static/Cabin-Regular.ttf"
    )}
    @{Name="Asap";Urls=@(
      "https://github.com/google/fonts/raw/main/ofl/asap/static/Asap-Regular.ttf",
      "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/asap/static/Asap-Regular.ttf"
    )}
    @{Name="Lexend";Urls=@(
      "https://github.com/google/fonts/raw/main/ofl/lexend/static/Lexend-Regular.ttf",
      "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/lexend/static/Lexend-Regular.ttf"
    )}
    @{Name="Heebo";Urls=@(
      "https://github.com/google/fonts/raw/main/ofl/heebo/static/Heebo-Regular.ttf",
      "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/heebo/static/Heebo-Regular.ttf"
    )}
    @{Name="Outfit";Urls=@(
      "https://github.com/google/fonts/raw/main/ofl/outfit/static/Outfit-Regular.ttf",
      "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/outfit/static/Outfit-Regular.ttf"
    )}
    @{Name="Sora";Urls=@(
      "https://github.com/google/fonts/raw/main/ofl/sora/static/Sora-Regular.ttf",
      "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/sora/static/Sora-Regular.ttf"
    )}
    @{Name="Plus Jakarta Sans";Urls=@(
      "https://github.com/google/fonts/raw/main/ofl/plusjakartasans/static/PlusJakartaSans-Regular.ttf",
      "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/plusjakartasans/static/PlusJakartaSans-Regular.ttf"
    )}
  )
  Serif = @(
    @{Name="Merriweather";Urls=@(
      "https://github.com/google/fonts/raw/main/ofl/merriweather/Merriweather-Regular.ttf",
      "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/merriweather/Merriweather-Regular.ttf"
    )}
    @{Name="Lora";Urls=@(
      "https://github.com/google/fonts/raw/main/ofl/lora/static/Lora-Regular.ttf",
      "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/lora/static/Lora-Regular.ttf"
    )}
    @{Name="Libre Baskerville";Urls=@(
      "https://github.com/google/fonts/raw/main/ofl/librebaskerville/LibreBaskerville-Regular.ttf",
      "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/librebaskerville/LibreBaskerville-Regular.ttf"
    )}
    @{Name="Playfair Display";Urls=@(
      "https://github.com/google/fonts/raw/main/ofl/playfairdisplay/static/PlayfairDisplay-Regular.ttf",
      "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/playfairdisplay/static/PlayfairDisplay-Regular.ttf"
    )}
    @{Name="Source Serif 4";Urls=@(
      "https://github.com/google/fonts/raw/main/ofl/sourceserif4/static/SourceSerif4-Regular.ttf",
      "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/sourceserif4/static/SourceSerif4-Regular.ttf"
    )}
    @{Name="Cardo";Urls=@(
      "https://github.com/google/fonts/raw/main/ofl/cardo/Cardo-Regular.ttf",
      "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/cardo/Cardo-Regular.ttf"
    )}
    @{Name="Crimson Pro";Urls=@(
      "https://github.com/google/fonts/raw/main/ofl/crimsonpro/static/CrimsonPro-Regular.ttf",
      "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/crimsonpro/static/CrimsonPro-Regular.ttf"
    )}
    @{Name="Cormorant Garamond";Urls=@(
      "https://github.com/google/fonts/raw/main/ofl/cormorantgaramond/static/CormorantGaramond-Regular.ttf",
      "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/cormorantgaramond/static/CormorantGaramond-Regular.ttf"
    )}
    @{Name="Old Standard TT";Urls=@(
      "https://github.com/google/fonts/raw/main/ofl/oldstandardtt/OldStandardTT-Regular.ttf",
      "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/oldstandardtt/OldStandardTT-Regular.ttf"
    )}
    @{Name="Domine";Urls=@(
      "https://github.com/google/fonts/raw/main/ofl/domine/static/Domine-Regular.ttf",
      "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/domine/static/Domine-Regular.ttf"
    )}
    @{Name="Spectral";Urls=@(
      "https://github.com/google/fonts/raw/main/ofl/spectral/static/Spectral-Regular.ttf",
      "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/spectral/static/Spectral-Regular.ttf"
    )}
    @{Name="EB Garamond";Urls=@(
      "https://github.com/google/fonts/raw/main/ofl/ebgaramond/EBGaramond-VariableFont_wght.ttf",
      "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/ebgaramond/EBGaramond-VariableFont_wght.ttf"
    )}
    @{Name="Gentium Book Plus";Urls=@(
      "https://github.com/google/fonts/raw/main/ofl/gentiumbookplus/static/GentiumBookPlus-Regular.ttf",
      "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/gentiumbookplus/static/GentiumBookPlus-Regular.ttf"
    )}
    @{Name="Literata";Urls=@(
      "https://github.com/google/fonts/raw/main/ofl/literata/static/Literata-Regular.ttf",
      "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/literata/static/Literata-Regular.ttf"
    )}
    @{Name="Tinos";Urls=@(
      "https://github.com/google/fonts/raw/main/apache/tinos/Tinos-Regular.ttf",
      "https://cdn.jsdelivr.net/gh/google/fonts@main/apache/tinos/Tinos-Regular.ttf"
    )}
  )
}

# ---- Helpers ----
function Download-File {
  param([string[]]$Urls,[string]$OutFile,[int]$Retry=2)
  foreach($u in $Urls){
    for($i=1;$i -le $Retry;$i++){
      try {
        Log ("Download attempt {0}: {1}" -f $i,$u)
        if ($PSVersionTable.PSVersion.Major -ge 7) {
          Invoke-WebRequest -Uri $u -OutFile $OutFile -TimeoutSec 240
        } else {
          try { Start-BitsTransfer -Source $u -Destination $OutFile -ErrorAction Stop }
          catch { Invoke-WebRequest -Uri $u -OutFile $OutFile }
        }
        if ((Test-Path $OutFile) -and ((Get-Item $OutFile).Length -gt 1000)) { Log ("Download OK: {0}" -f $OutFile); return $true }
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
    # mark ownership
    $owned = (Get-ItemProperty -Path $StateKey -Name "Owned" -ErrorAction SilentlyContinue).Owned
    if(-not $owned){ $owned=@() }
    $owned = $owned + $fi.Name | Select-Object -Unique
    New-ItemProperty -Path $StateKey -Name "Owned" -Value $owned -PropertyType MultiString -Force | Out-Null
    return @{Face=$face;File=$fi.Name}
  } catch { Say ("Install error: {0}" -f $_.Exception.Message) "Red" "ERROR"; return $null }
}

function Uninstall-One { param([string]$File)
  try {
    $full = Join-Path $FontsDir $File
    # remove registry entries pointing to this file
    $reg = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
    $props = (Get-ItemProperty $reg -ErrorAction SilentlyContinue).PSObject.Properties |
      Where-Object { $_.Value -and ($_.Value -ieq $File) }
    foreach($p in $props){
      try { Remove-ItemProperty -Path $reg -Name $p.Name -ErrorAction SilentlyContinue } catch {}
    }
    if(Test-Path $full){
      try { Remove-Item $full -Force -ErrorAction SilentlyContinue } catch {}
    }
    Say ("Uninstalled file: {0}" -f $File) "Yellow"
    # update ownership list
    $owned = (Get-ItemProperty -Path $StateKey -Name "Owned" -ErrorAction SilentlyContinue).Owned
    if($owned){ $owned = $owned | Where-Object { $_ -ne $File }; New-ItemProperty -Path $StateKey -Name "Owned" -Value $owned -PropertyType MultiString -Force | Out-Null }
  } catch { Log ("Uninstall warn: {0}" -f $_.Exception.Message) "WARN" }
}

function FaceMap {
  $map=@{}; $reg="HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
  try { (Get-ItemProperty $reg -ErrorAction SilentlyContinue).PSObject.Properties |
      Where-Object { $_.Name -and $_.Name -notmatch '^PS' -and $_.Value } |
      ForEach-Object { $map[($_.Name -replace ' \(TrueType\)$','' -replace ' \(OpenType\)$','')] = $_.Value } } catch {}
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
    $bases=@("Segoe UI","Segoe UI Variable","Segoe UI Symbol","Segoe UI Emoji","Arial","Times New Roman","Courier New","Calibri","Cambria","Consolas","Microsoft Sans Serif","Tahoma","MS Shell Dlg","MS Shell Dlg 2","Cambria Math")
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
function Prepend-Link { param([string]$Base,[string[]]$Pairs)
  foreach($root in @('HKLM','HKCU')){
    $key=("{0}:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontLink\SystemLink" -f $root)
    try {
      $cur=(Get-ItemProperty -Path $key -Name $Base -ErrorAction SilentlyContinue).$Base
      if (-not $cur){$cur=@()}
      $new=($Pairs + $cur) | Select-Object -Unique
      New-ItemProperty -Path $key -Name $Base -Value $new -PropertyType MultiString -Force | Out-Null
      Log ("SystemLink [{0}] ({1}) <= {2}" -f $Base,$root,($Pairs -join ' | '))
    } catch { Say ("Prepend error {0}/{1}: {2}" -f $Base,$root,$_.Exception.Message) "Red" "ERROR" }
  }
}
function Set-Sub { param([string]$From,[string]$To)
  foreach($root in @('HKLM','HKCU')){
    $key=("{0}:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -f $root)
    try {
      try { Set-ItemProperty -Path $key -Name $From -Value $To -ErrorAction Stop }
      catch { New-ItemProperty -Path $key -Name $From -Value $To -PropertyType String -Force | Out-Null }
      Say ("Substitute({0}): {1} -> {2}" -f $root,$From,$To) "Yellow"
    } catch { Say ("Substitute error {0}->{1}/{2}: {3}" -f $From,$To,$root,$_.Exception.Message) "Red" "ERROR" }
  }
}
function Refresh-Fonts {
  try { Stop-Service FontCache -Force -ErrorAction SilentlyContinue; Start-Sleep 1; Remove-Item "$env:LOCALAPPDATA\FontCache\*" -Force -ErrorAction SilentlyContinue } catch {}
  try { Start-Service FontCache -ErrorAction SilentlyContinue } catch {}
  try {
    Add-Type -Namespace Win32 -Name U -MemberDefinition '[DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h,uint m,IntPtr w,IntPtr l,uint f,uint t,out IntPtr r);'
    [void][Win32.U]::SendMessageTimeout([IntPtr]0xffff,0x1D,[IntPtr]0,[IntPtr]0,2,1000,[ref]([IntPtr]::Zero))
  } catch {}
}
function PickFirst { param([string[]]$Prefer,[hashtable]$Map,[switch]$Exact)
  foreach($n in $Prefer){ foreach($k in $Map.Keys){
    $ok = if($Exact){ $k -eq $n } else { ($k -eq $n) -or ($k -like ($n + "*")) }
    if($ok){ $f=$Map[$k]; if($f -and (Test-Path (Join-Path $FontsDir $f))){ return @{Face=$k;Pair=("{0},{1}" -f $f,$k)} } }
  }} $null
}

# ---- Chromium helpers ----
function Is-ProcRunning { param([string]$Name) try { (Get-Process -Name $Name -ErrorAction SilentlyContinue) -ne $null } catch { $false } }
function Kill-Browsers {
  foreach($p in @("chrome","msedge")){
    try { if(Is-ProcRunning $p){ Stop-Process -Name $p -Force -ErrorAction SilentlyContinue; Start-Sleep 1; Say ("Killed: {0}" -f $p) "Yellow" } } catch {}
  }
}
function Patch-ChromiumFonts {
  param([string]$PrefsPath,[string]$Sans,[string]$Serif,[string]$Mono,[string]$Cursive="Comic Sans MS",[string]$Fantasy="Impact")
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
        "standard" { $Serif } "serif" { $Serif } "sansserif" { $Sans } "fixed" { $Mono } "cursive" { $Cursive } "fantasy" { $Fantasy } }
    }
    ($json | ConvertTo-Json -Depth 20) | Set-Content -Encoding UTF8 $PrefsPath
    Say ("Patched Chromium Prefs: {0} (sans={1}, serif={2}, mono={3})" -f $PrefsPath,$Sans,$Serif,$Mono) "Green"
  } catch { Say ("Chromium patch error: {0}" -f $_.Exception.Message) "Red" "ERROR" }
}

# -------------------- MAIN --------------------
Clear-Host
Write-Host "==============================================================" -ForegroundColor Green
Write-Host ("  ADVANCED FONT FINGERPRINT ROTATOR v{0}" -f $Version) -ForegroundColor Yellow
Write-Host "==============================================================" -ForegroundColor Green
Log ("OS: {0}  PS: {1}" -f [Environment]::OSVersion.VersionString, $PSVersionTable.PSVersion)

$beforeInv = InvHash; $beforeFB = FBHash
Say ("Inventory Hash: {0}..." -f (Head32 $beforeInv)) "Cyan"
Say ("Fallback Hash : {0}..." -f (Head32 $beforeFB)) "Cyan"

# ========== ROUND LOOP to guarantee BOTH hashes change ==========
for($round=1; $round -le $MaxRounds; $round++){
  Say ("--- ROUND {0} ---" -f $round) "White"

  # 0) optional remove old owned fonts to force inventory change
  if(-not $KeepGrowth){
    $owned = (Get-ItemProperty -Path $StateKey -Name "Owned" -ErrorAction SilentlyContinue).Owned
    if($owned -and $owned.Count -gt 0){
      $rmCount = Get-Random -Minimum $UninstallMin -Maximum ([Math]::Min($UninstallMax, $owned.Count)+1)
      $rmList = $owned | Get-Random -Count $rmCount
      Say ("Uninstalling {0} previously-installed fonts..." -f $rmList.Count) "Yellow"
      Refresh-Fonts
      foreach($f in $rmList){ Uninstall-One $f }
      Refresh-Fonts
    }
  }

  # 1) INSTALL fresh fonts — choose bias: Symbols/Emoji/Mono + mix Sans/Serif
  $bag=@()
  foreach($cat in $DB.Keys){ foreach($it in $DB[$cat]){ $bag += ,@{Cat=$cat;Item=$it} } }
  # Always include: 1 Emoji + 2 SymbolsMath (nếu có)
  $must=@()
  if(($bag | Where-Object {$_.Cat -eq 'Emoji'}).Count){ $must += ($bag | Where-Object {$_.Cat -eq 'Emoji'} | Get-Random -Count 1) }
  $symPool = $bag | Where-Object {$_.Cat -eq 'SymbolsMath'}
  if($symPool.Count -ge 2){ $must += ($symPool | Get-Random -Count 2) } elseif($symPool.Count -gt 0){ $must += ($symPool | Get-Random -Count 1) }
  $instTarget = Get-Random -Minimum $InstallMin -Maximum ($InstallMax+1)
  $extraNeed  = [Math]::Max(0, $instTarget - $must.Count)
  $extra      = ($bag | Where-Object { $must -notcontains $_ } | Get-Random -Count ([Math]::Min($extraNeed, $bag.Count)))
  $todo       = $must + $extra

  $installed=0
  foreach($t in $todo){
    $urls=$t.Item.Urls
    $first=$urls[0]
    $out = Join-Path $TempDir ([IO.Path]::GetFileName($first))
    if(Download-File -Urls $urls -OutFile $out){
      $r = Install-One -SrcPath $out -Fallback $t.Item.Name
      if($r){ $installed++ }
    } else {
      Say ("Download failed: {0}" -f ($urls -join " | ")) "Red" "ERROR"
    }
  }

  # 2) RANDOMIZE unicode glyph fallbacks
  $map = FaceMap
  $sans  = PickFirst -Prefer @("Inter","Open Sans","Noto Sans","Roboto","Segoe UI","Work Sans") -Map $map
  $serif = PickFirst -Prefer @("Merriweather","Lora","Noto Serif","Source Serif","Cambria","Times New Roman") -Map $map
  $mono  = PickFirst -Prefer @("JetBrains Mono","Source Code Pro","Inconsolata","Cousine","Anonymous Pro","Consolas","Courier New") -Map $map
  $sym1  = PickFirst -Prefer @("Noto Sans Math","Libertinus Math","Noto Sans Symbols 2") -Map $map
  $sym2  = PickFirst -Prefer @("Noto Sans Symbols 2","Noto Music","Noto Sans") -Map $map
  $emoji = PickFirst -Prefer @("Noto Color Emoji") -Map $map -Exact

  $bases = @("Segoe UI","Segoe UI Variable","Arial","Times New Roman","Courier New","Calibri","Cambria","Consolas","Microsoft Sans Serif","Tahoma","MS Shell Dlg","MS Shell Dlg 2") | Get-Random -Count 12
  $pairs=@()
  foreach($p in @($sans,$serif,$mono)){ if($p){ $pairs+=$p.Pair } }
  if($sym1){ $pairs = ,$sym1.Pair + $pairs }
  if($sym2){ $pairs += $sym2.Pair }
  foreach($b in $bases){
    if($pairs.Count -gt 0){
      $take = Get-Random -Minimum 2 -Maximum ([Math]::Min(6,$pairs.Count)+1)
      Prepend-Link -Base $b -Pairs ($pairs | Get-Random -Count $take)
    }
  }
  if($sym1){ Prepend-Link -Base "Segoe UI Symbol" -Pairs @($sym1.Pair); Set-Sub "Segoe UI Symbol" $sym1.Face; Set-Sub "Cambria Math" $sym1.Face }
  if($emoji){ Prepend-Link -Base "Segoe UI Emoji"  -Pairs @($emoji.Pair); Set-Sub "Segoe UI Emoji"  $emoji.Face }
  if($sans){  Set-Sub "Segoe UI" $sans.Face; Set-Sub "Arial" $sans.Face; Set-Sub "Microsoft Sans Serif" $sans.Face }
  if($serif){ Set-Sub "Times New Roman" $serif.Face; Set-Sub "Cambria" $serif.Face }
  if($mono){  Set-Sub "Courier New" $mono.Face; Set-Sub "Consolas" $mono.Face }
  Refresh-Fonts

  # 3) Patch Chromium & kill processes (default)
  if(-not $NoForceClose){ Kill-Browsers }
  if(-not $NoChromiumFonts){
    $sf = if($sans){$sans.Face}else{"Arial"}
    $rf = if($serif){$serif.Face}else{"Times New Roman"}
    $mf = if($mono){$mono.Face}else{"Consolas"}
    $chrome = Join-Path $env:LOCALAPPDATA ("Google\Chrome\User Data\{0}\Preferences" -f $ChromeProfile)
    $edge   = Join-Path $env:LOCALAPPDATA ("Microsoft\Edge\User Data\{0}\Preferences" -f $EdgeProfile)
    Patch-ChromiumFonts -PrefsPath $chrome -Sans $sf -Serif $rf -Mono $mf
    Patch-ChromiumFonts -PrefsPath $edge   -Sans $sf -Serif $rf -Mono $mf
  } else {
    Say "NoChromiumFonts: SKIP patch Chrome/Edge." "Yellow"
  }

  # 4) Check hashes
  $newInv = InvHash; $newFB = FBHash
  Say ("Round {0} Inventory:  {1} -> {2}" -f $round,(Head32 $beforeInv),(Head32 $newInv)) "White"
  Say ("Round {0} Fallback :  {1} -> {2}" -f $round,(Head32 $beforeFB),(Head32 $newFB)) "White"

  $invChanged = ($newInv -ne $beforeInv)
  $fbChanged  = ($newFB -ne $beforeFB)

  if($invChanged -and $fbChanged){
    Say ("SUCCESS: Both hashes changed in round {0}" -f $round) "Green"
    break
  } else {
    Say ("Hashes not both changed (Inv={0}, FB={1}) -> retry next round" -f ($invChanged), ($fbChanged)) "Yellow"
    $beforeInv = $newInv
    $beforeFB  = $newFB
  }
}

# --- Results ---
$finalInv = InvHash; $finalFB = FBHash
Say "`n--- FINAL HASHES ---" "Cyan"
Say ("Inventory:  {0}" -f $finalInv) "White"
Say ("Fallback :  {0}" -f $finalFB) "White"
Log ("Run finished. v{0}" -f $Version)
