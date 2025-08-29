<# ===================================================================
  ADVANCED FONT FINGERPRINT ROTATOR v4.1
  (Lite TTF • EU/US + Unicode Glyphs • PowerShell 5.x SAFE)

  - Cài nhiều .ttf nhỏ từ nguồn uy tín: google/fonts (apache|ofl|ufl),
    googlefonts/noto-fonts, notofonts/*
  - Bổ sung Unicode glyphs: Noto Sans Symbols, Symbols2, Music, Math, Emoji
  - Random SystemLink + FontSubstitutes (HKLM + HKCU)
  - ÉP đổi cả InventoryHash & FallbackHash mỗi lần chạy
  - Log: %USERPROFILE%\Downloads\log.txt
=================================================================== #>

# --- Admin ---
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
   ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
  Write-Host "ERROR: Run PowerShell as Administrator!" -ForegroundColor Red
  Read-Host "Press Enter to exit"; exit 1
}

# --- Log ---
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

# --- Paths ---
$TempDir  = "$env:TEMP\FontRotator"
$FontsDir = "$env:SystemRoot\Fonts"
if (!(Test-Path $TempDir)) { New-Item -ItemType Directory -Path $TempDir -Force | Out-Null }

# --- Config kích thước (MB) ---
$MaxSingleTTFMB = 3.0
$BigTTFWhitelist = @(
  "NotoColorEmoji.ttf"     # cho phép lớn hơn (mặc định emoji ~8–10MB)
)
$BigTTFMaxMB = 16.0

# --- EU/US Lite pool (rất nhiều .ttf nhỏ) ---
$LiteTTF = @(
  # apache/
  @{Name="Open Sans";            Url="https://raw.githubusercontent.com/google/fonts/main/apache/opensans/OpenSans-Regular.ttf"}
  @{Name="Roboto";               Url="https://raw.githubusercontent.com/google/fonts/main/apache/roboto/Roboto-Regular.ttf"}
  @{Name="Arimo";                Url="https://raw.githubusercontent.com/google/fonts/main/apache/arimo/Arimo-Regular.ttf"}
  @{Name="Tinos";                Url="https://raw.githubusercontent.com/google/fonts/main/apache/tinos/Tinos-Regular.ttf"}
  @{Name="Cousine";              Url="https://raw.githubusercontent.com/google/fonts/main/apache/cousine/Cousine-Regular.ttf"}

  # ufl/
  @{Name="Ubuntu";               Url="https://raw.githubusercontent.com/google/fonts/main/ufl/ubuntu/Ubuntu-Regular.ttf"}
  @{Name="Ubuntu Mono";          Url="https://raw.githubusercontent.com/google/fonts/main/ufl/ubuntumono/UbuntuMono-Regular.ttf"}

  # ofl/ (Sans/Serif/Mono phổ biến EU/US)
  @{Name="Inter";                Url="https://raw.githubusercontent.com/google/fonts/main/ofl/inter/Inter-Regular.ttf"}
  @{Name="Lato";                 Url="https://raw.githubusercontent.com/google/fonts/main/ofl/lato/Lato-Regular.ttf"}
  @{Name="Raleway";              Url="https://raw.githubusercontent.com/google/fonts/main/ofl/raleway/Raleway-Regular.ttf"}
  @{Name="Montserrat";           Url="https://raw.githubusercontent.com/google/fonts/main/ofl/montserrat/Montserrat-Regular.ttf"}
  @{Name="Nunito";               Url="https://raw.githubusercontent.com/google/fonts/main/ofl/nunito/Nunito-Regular.ttf"}
  @{Name="Poppins";              Url="https://raw.githubusercontent.com/google/fonts/main/ofl/poppins/Poppins-Regular.ttf"}
  @{Name="Work Sans";            Url="https://raw.githubusercontent.com/google/fonts/main/ofl/worksans/WorkSans-Regular.ttf"}
  @{Name="Manrope";              Url="https://raw.githubusercontent.com/google/fonts/main/ofl/manrope/Manrope-Regular.ttf"}
  @{Name="Source Sans 3";        Url="https://raw.githubusercontent.com/google/fonts/main/ofl/sourcesans3/SourceSans3-Regular.ttf"}
  @{Name="Source Serif 4";       Url="https://raw.githubusercontent.com/google/fonts/main/ofl/sourceserif4/SourceSerif4-Regular.ttf"}
  @{Name="Source Code Pro";      Url="https://raw.githubusercontent.com/google/fonts/main/ofl/sourcecodepro/SourceCodePro-Regular.ttf"}
  @{Name="IBM Plex Sans";        Url="https://raw.githubusercontent.com/google/fonts/main/ofl/ibmplexsans/IBMPlexSans-Regular.ttf"}
  @{Name="IBM Plex Serif";       Url="https://raw.githubusercontent.com/google/fonts/main/ofl/ibmplexserif/IBMPlexSerif-Regular.ttf"}
  @{Name="IBM Plex Mono";        Url="https://raw.githubusercontent.com/google/fonts/main/ofl/ibmplexmono/IBMPlexMono-Regular.ttf"}
  @{Name="Merriweather";         Url="https://raw.githubusercontent.com/google/fonts/main/ofl/merriweather/Merriweather-Regular.ttf"}
  @{Name="Merriweather Sans";    Url="https://raw.githubusercontent.com/google/fonts/main/ofl/merriweathersans/MerriweatherSans-Regular.ttf"}
  @{Name="Lora";                 Url="https://raw.githubusercontent.com/google/fonts/main/ofl/lora/Lora-Regular.ttf"}
  @{Name="Libre Baskerville";    Url="https://raw.githubusercontent.com/google/fonts/main/ofl/librebaskerville/LibreBaskerville-Regular.ttf"}
  @{Name="EB Garamond";          Url="https://raw.githubusercontent.com/google/fonts/main/ofl/ebgaramond/EBGaramond-Regular.ttf"}
  @{Name="Playfair Display";     Url="https://raw.githubusercontent.com/google/fonts/main/ofl/playfairdisplay/PlayfairDisplay-Regular.ttf"}
  @{Name="Crimson Pro";          Url="https://raw.githubusercontent.com/google/fonts/main/ofl/crimsonpro/CrimsonPro-Regular.ttf"}
  @{Name="Crimson Text";         Url="https://raw.githubusercontent.com/google/fonts/main/ofl/crimsontext/CrimsonText-Regular.ttf"}
  @{Name="Cardo";                Url="https://raw.githubusercontent.com/google/fonts/main/ofl/cardo/Cardo-Regular.ttf"}
  @{Name="Cinzel";               Url="https://raw.githubusercontent.com/google/fonts/main/ofl/cinzel/Cinzel-Regular.ttf"}
  @{Name="Alegreya";             Url="https://raw.githubusercontent.com/google/fonts/main/ofl/alegreya/Alegreya-Regular.ttf"}
  @{Name="Alegreya Sans";        Url="https://raw.githubusercontent.com/google/fonts/main/ofl/alegreyasans/AlegreyaSans-Regular.ttf"}
  @{Name="Libre Franklin";       Url="https://raw.githubusercontent.com/google/fonts/main/ofl/librefranklin/LibreFranklin-Regular.ttf"}
  @{Name="Oswald";               Url="https://raw.githubusercontent.com/google/fonts/main/ofl/oswald/Oswald-Regular.ttf"}
  @{Name="PT Serif";             Url="https://raw.githubusercontent.com/google/fonts/main/ofl/ptserif/PTSerif-Regular.ttf"}
  @{Name="PT Sans";              Url="https://raw.githubusercontent.com/google/fonts/main/ofl/ptsans/PTSans-Regular.ttf"}
  @{Name="PT Mono";              Url="https://raw.githubusercontent.com/google/fonts/main/ofl/ptmono/PTMono-Regular.ttf"}
  @{Name="Cantarell";            Url="https://raw.githubusercontent.com/google/fonts/main/ofl/cantarell/Cantarell-Regular.ttf"}
  @{Name="Fira Sans";            Url="https://raw.githubusercontent.com/google/fonts/main/ofl/firasans/FiraSans-Regular.ttf"}
  @{Name="Fira Mono";            Url="https://raw.githubusercontent.com/google/fonts/main/ofl/firamono/FiraMono-Regular.ttf"}
  @{Name="Inconsolata";          Url="https://raw.githubusercontent.com/google/fonts/main/ofl/inconsolata/Inconsolata-Regular.ttf"}
  @{Name="Gentium Book Plus";    Url="https://raw.githubusercontent.com/google/fonts/main/ofl/gentiumbookplus/GentiumBookPlus-Regular.ttf"}
  @{Name="Gentium Plus";         Url="https://raw.githubusercontent.com/google/fonts/main/ofl/gentiumplus/GentiumPlus-Regular.ttf"}
  @{Name="Cormorant Garamond";   Url="https://raw.githubusercontent.com/google/fonts/main/ofl/cormorantgaramond/CormorantGaramond-Regular.ttf"}
  @{Name="Ibarra Real Nova";     Url="https://raw.githubusercontent.com/google/fonts/main/ofl/ibarrarealnova/IbarraRealNova-Regular.ttf"}
  @{Name="Spectral";             Url="https://raw.githubusercontent.com/google/fonts/main/ofl/spectral/Spectral-Regular.ttf"}
  @{Name="Vollkorn";             Url="https://raw.githubusercontent.com/google/fonts/main/ofl/vollkorn/Vollkorn-Regular.ttf"}
  @{Name="Zilla Slab";           Url="https://raw.githubusercontent.com/google/fonts/main/ofl/zillaslab/ZillaSlab-Regular.ttf"}
  @{Name="Chivo";                Url="https://raw.githubusercontent.com/google/fonts/main/ofl/chivo/Chivo-Regular.ttf"}
  @{Name="Archivo";              Url="https://raw.githubusercontent.com/google/fonts/main/ofl/archivo/Archivo-Regular.ttf"}
  @{Name="Asap";                 Url="https://raw.githubusercontent.com/google/fonts/main/ofl/asap/Asap-Regular.ttf"}
  @{Name="Barlow";               Url="https://raw.githubusercontent.com/google/fonts/main/ofl/barlow/Barlow-Regular.ttf"}
  @{Name="Barlow Condensed";     Url="https://raw.githubusercontent.com/google/fonts/main/ofl/barlowcondensed/BarlowCondensed-Regular.ttf"}
  @{Name="Space Grotesk";        Url="https://raw.githubusercontent.com/google/fonts/main/ofl/spacegrotesk/SpaceGrotesk-Regular.ttf"}
  @{Name="Space Mono";           Url="https://raw.githubusercontent.com/google/fonts/main/ofl/spacemono/SpaceMono-Regular.ttf"}
  @{Name="Quicksand";            Url="https://raw.githubusercontent.com/google/fonts/main/ofl/quicksand/Quicksand-Regular.ttf"}
  @{Name="Josefin Sans";         Url="https://raw.githubusercontent.com/google/fonts/main/ofl/josefinsans/JosefinSans-Regular.ttf"}
  @{Name="Karla";                Url="https://raw.githubusercontent.com/google/fonts/main/ofl/karla/Karla-Regular.ttf"}
  @{Name="Titillium Web";        Url="https://raw.githubusercontent.com/google/fonts/main/ofl/titilliumweb/TitilliumWeb-Regular.ttf"}
  @{Name="Rubik";                Url="https://raw.githubusercontent.com/google/fonts/main/ofl/rubik/Rubik-Regular.ttf"}
  @{Name="League Spartan";       Url="https://raw.githubusercontent.com/google/fonts/main/ofl/leaguespartan/LeagueSpartan-Regular.ttf"}
  @{Name="Bebas Neue";           Url="https://raw.githubusercontent.com/google/fonts/main/ofl/bebasneue/BebasNeue-Regular.ttf"}
  @{Name="Overpass";             Url="https://raw.githubusercontent.com/google/fonts/main/ofl/overpass/Overpass-Regular.ttf"}
  @{Name="Urbanist";             Url="https://raw.githubusercontent.com/google/fonts/main/ofl/urbanist/Urbanist-Regular.ttf"}
  @{Name="Maven Pro";            Url="https://raw.githubusercontent.com/google/fonts/main/ofl/mavenpro/MavenPro-Regular.ttf"}
  @{Name="Hepta Slab";           Url="https://raw.githubusercontent.com/google/fonts/main/ofl/heptaslab/HeptaSlab-Regular.ttf"}
  @{Name="Fraunces";             Url="https://raw.githubusercontent.com/google/fonts/main/ofl/fraunces/Fraunces_72pt-Regular.ttf"}
  @{Name="Public Sans";          Url="https://raw.githubusercontent.com/google/fonts/main/ofl/publicsans/PublicSans-Regular.ttf"}
  @{Name="Iosevka Etoile";       Url="https://raw.githubusercontent.com/google/fonts/main/ofl/iosevkaetoile/IosevkaEtoile-Regular.ttf"}
  @{Name="Iosevka Aile";         Url="https://raw.githubusercontent.com/google/fonts/main/ofl/iosevkaaile/IosevkaAile-Regular.ttf"}

  # Mono thêm
  @{Name="JetBrains Mono";       Url="https://raw.githubusercontent.com/google/fonts/main/ofl/jetbrainsmono/JetBrainsMono-Regular.ttf"}
)

# --- Unicode Glyphs pool (Symbols / Music / Math / Emoji) ---
$UnicodeTTF = @(
  # Math (nhỏ)
  @{Name="Noto Sans Math";       Url="https://raw.githubusercontent.com/googlefonts/noto-fonts/main/hinted/ttf/NotoSansMath/NotoSansMath-Regular.ttf"}

  # Symbols (thử 2 nguồn để tránh 404)
  @{Name="Noto Sans Symbols";    Url="https://raw.githubusercontent.com/googlefonts/noto-fonts/main/hinted/ttf/NotoSansSymbols/NotoSansSymbols-Regular.ttf"}
  @{Name="Noto Sans Symbols 2";  Url="https://raw.githubusercontent.com/googlefonts/noto-fonts/main/hinted/ttf/NotoSansSymbols2/NotoSansSymbols2-Regular.ttf"}
  @{Name="Noto Sans Symbols.alt";Url="https://raw.githubusercontent.com/notofonts/symbols/main/fonts/ttf/NotoSansSymbols/NotoSansSymbols-Regular.ttf"}
  @{Name="Noto Sans Symbols2.alt";Url="https://raw.githubusercontent.com/notofonts/symbols2/main/fonts/ttf/NotoSansSymbols2/NotoSansSymbols2-Regular.ttf"}

  # Music
  @{Name="Noto Music";           Url="https://raw.githubusercontent.com/googlefonts/noto-fonts/main/hinted/ttf/NotoMusic/NotoMusic-Regular.ttf"}
  @{Name="Noto Music.alt";       Url="https://raw.githubusercontent.com/notofonts/music/main/fonts/ttf/NotoMusic/NotoMusic-Regular.ttf"}

  # Emoji (màu) — lớn, nhưng whitelisted
  @{Name="Noto Color Emoji";     Url="https://raw.githubusercontent.com/googlefonts/noto-emoji/main/fonts/NotoColorEmoji.ttf"}
)

# --- Helpers ---
function Try-Head { param([string]$Url)
  try { return Invoke-WebRequest -Uri $Url -Method Head -UseBasicParsing -TimeoutSec 25 } catch { return $null }
}

function Is-WhitelistedBig { param([string]$Url)
  foreach($w in $BigTTFWhitelist){ if ($Url -like ("*"+$w)) { return $true } }
  return $false
}

function Download-File {
  param([string]$Url,[string]$OutFile,[int]$Retry=3)
  # Giới hạn kích thước cho TTF/OTF (nhẹ) – ngoại lệ whitelist
  $lower = $Url.ToLower()
  if (($lower.EndsWith(".ttf") -or $lower.EndsWith(".otf"))) {
    $head = Try-Head -Url $Url
    if ($head -and $head.Headers['Content-Length']) {
      $len = [int64]$head.Headers['Content-Length']
      $limitMB = $MaxSingleTTFMB
      if (Is-WhitelistedBig -Url $Url) { $limitMB = $BigTTFMaxMB }
      if ($len -gt ($limitMB*1MB)) {
        Log ("Skip TTF {0} MB > limit {1} MB: {2}" -f [math]::Round($len/1MB,1),$limitMB,$Url) "WARN"
        return $false
      }
    }
  }
  for($i=1;$i -le $Retry;$i++){
    try {
      Log ("Download attempt {0}: {1}" -f $i,$Url)
      if ($PSVersionTable.PSVersion.Major -ge 7) {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -TimeoutSec 180
      } else {
        try { Start-BitsTransfer -Source $Url -Destination $OutFile -ErrorAction Stop }
        catch { Invoke-WebRequest -Uri $Url -OutFile $OutFile }
      }
      if ((Test-Path $OutFile) -and ((Get-Item $OutFile).Length -gt 1000)) { Log ("Download OK: {0}" -f $OutFile); return $true }
    } catch { Log ("Download error: {0}" -f $_.Exception.Message) "ERROR" }
    Start-Sleep -Seconds ([Math]::Min(2*$i,10))
  }
  Log ("Download failed: {0}" -f $Url) "ERROR"; return $false
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
function Install-One { param([string]$File,[string]$Fallback="Custom")
  try {
    $fi = Get-Item $File
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
function Install-FromUrl { param([string]$Name,[string]$Url)
  $out = Join-Path $TempDir ([IO.Path]::GetFileName($Url))
  if (!(Download-File $Url $out)) { Say ("Download failed: {0}" -f $Name) "Red" "ERROR"; return @() }
  $r = Install-One -File $out -Fallback $Name
  if ($r){,@($r)} else {@()}
}
function Install-LiteRound { param([int]$Count=48)
  $pool = @()
  foreach($x in $LiteTTF){ $pool += ,$x }
  foreach($u in $UnicodeTTF){ $pool += ,$u }
  $pick = $pool | Get-Random -Count ([Math]::Min($Count, $pool.Count))
  $n=0
  foreach($f in $pick){ $r = Install-FromUrl -Name $f.Name -Url $f.Url; $n += $r.Count }
  return $n
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
      "Microsoft Sans Serif","Tahoma","MS Shell Dlg","MS Shell Dlg 2"
    )
    $rows=@()
    foreach($root in @('HKLM','HKCU')){
      $sys=("{0}:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontLink\SystemLink" -f $root)
      $sub=("{0}:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -f $root)
      foreach($b in $bases){
        $v=(Get-ItemProperty -Path $sys -Name $b -ErrorAction SilentlyContinue).$b
        if($v){$rows+=("SYS[{0}]:{1}={2}" -f $root,$b,($v -join ';'))}
      }
      foreach($n in @("Segoe UI","Microsoft Sans Serif","Tahoma","MS Shell Dlg","MS Shell Dlg 2","Arial","Times New Roman","Courier New","Segoe UI Symbol","Cambria Math","Segoe UI Emoji")){
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
    } catch {
      Say ("Prepend error {0}/{1}: {2}" -f $Base,$root,$_.Exception.Message) "Red" "ERROR"
    }
  }
}
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

# --- MAIN ---
Clear-Host
Write-Host "==============================================================" -ForegroundColor Green
Write-Host "  ADVANCED FONT FINGERPRINT ROTATOR v4.1 (Lite TTF • EU/US + Unicode)" -ForegroundColor Yellow
Write-Host "==============================================================" -ForegroundColor Green
Log ("OS: {0}  PS: {1}" -f [Environment]::OSVersion.VersionString, $PSVersionTable.PSVersion)

$beforeCount = (CurFonts).Count
$beforeInv   = InvHash
$beforeFB    = FBHash
Say ("Current fonts: {0}" -f $beforeCount) "Cyan"
Say ("Inventory Hash: {0}..." -f (Head32 $beforeInv)) "Cyan"
Say ("Fallback Hash : {0}..." -f (Head32 $beforeFB)) "Cyan"

# 1) Burst lớn: cài thật nhiều TTF nhỏ (bao gồm Unicode)
[void](Install-LiteRound -Count (Get-Random -Minimum 40 -Maximum 60))
$afterInv = InvHash
$invTries=0
while ($afterInv -eq $beforeInv -and $invTries -lt 2) {
  $invTries++
  [void](Install-LiteRound -Count (Get-Random -Minimum 24 -Maximum 36))
  $afterInv = InvHash
}

# 2) Randomize fallback cho tới khi FallbackHash đổi
function Apply-RandomFallback {
  $map = FaceMap
  $sans  = PickFirst -Prefer @("Inter","Open Sans","Roboto","IBM Plex Sans","Lato","Raleway","Montserrat","Source Sans 3","Nunito","Poppins","Work Sans","Public Sans","Overpass","Space Grotesk","Urbanist") -Map $map
  $serif = PickFirst -Prefer @("Merriweather","Lora","Libre Baskerville","EB Garamond","Playfair Display","Crimson Pro","Crimson Text","Cardo","Cinzel","Alegreya","Source Serif 4","Gentium Book Plus","Gentium Plus","Cormorant Garamond","Ibarra Real Nova","Spectral","Vollkorn","Zilla Slab") -Map $map
  $mono  = PickFirst -Prefer @("IBM Plex Mono","Source Code Pro","Fira Mono","Inconsolata","Ubuntu Mono","Cousine","JetBrains Mono","Space Mono","Iosevka Etoile","Iosevka Aile") -Map $map
  $sym   = PickFirst -Prefer @("Noto Sans Symbols 2","Noto Sans Symbols","Noto Sans Math","Noto Music") -Map $map
  $emoji = PickFirst -Prefer @("Noto Color Emoji") -Map $map -Exact

  $bases = @("Segoe UI","Segoe UI Variable","Arial","Times New Roman","Courier New","Calibri","Cambria","Consolas","Microsoft Sans Serif","Tahoma","MS Shell Dlg","MS Shell Dlg 2") | Get-Random -Count 12
  $pairs=@()
  foreach($p in @($sans,$serif,$mono)) { if($p){ $pairs+=$p.Pair } }
  if($sym){ $pairs = ,$sym.Pair + $pairs }
  foreach($b in $bases){
    if($pairs.Count -gt 0){
      $take = Get-Random -Minimum 3 -Maximum ([Math]::Min(6,$pairs.Count)+1)
      Prepend-Link -Base $b -Pairs ($pairs | Get-Random -Count $take)
    }
  }
  if($sym){   Prepend-Link -Base "Segoe UI Symbol" -Pairs @($sym.Pair) }
  if($emoji){ Prepend-Link -Base "Segoe UI Emoji"  -Pairs @($emoji.Pair) }

  if($sans){  Set-Sub "Segoe UI" $sans.Face; Set-Sub "Arial" $sans.Face; Set-Sub "Microsoft Sans Serif" $sans.Face }
  if($serif){ Set-Sub "Times New Roman" $serif.Face; Set-Sub "Cambria" $serif.Face }
  if($mono){  Set-Sub "Courier New" $mono.Face; Set-Sub "Consolas" $mono.Face }
  if($sym){   Set-Sub "Segoe UI Symbol" $sym.Face; Set-Sub "Cambria Math" $sym.Face }
  if($emoji){ Set-Sub "Segoe UI Emoji" $emoji.Face }

  Refresh-Fonts
}
$afterFB=$beforeFB; $fbTries=0
do { $fbTries++; Apply-RandomFallback; $afterFB = FBHash } while ($afterFB -eq $beforeFB -and $fbTries -lt 7)

# 3) Kết quả
$afterCount = (CurFonts).Count
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
Log "Run finished."
