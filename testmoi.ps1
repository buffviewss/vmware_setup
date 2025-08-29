<# ===================================================================
  ADVANCED FONT FINGERPRINT ROTATOR v3.8.0 (LEAN DB • EU/US-First)
  - Chỉ tải TTF/OTF trực tiếp (không .zip)
  - Tập trung đổi "Unicode Glyphs" fingerprint qua SystemLink + Substitutes
  - (Tuỳ chọn) Vá default fonts của Chrome/Edge
  - Mặc định cài rất ít font (2–4) để nhanh; có thể tắt hoàn toàn
  - Logging: %USERPROFILE%\Downloads\log.txt
=================================================================== #>

param(
  [switch]$ChromiumFonts = $false,
  [string]$ChromeProfile = "Default",
  [string]$EdgeProfile   = "Default",
  [int]$TargetMin = 2,     # số font tối thiểu sẽ cài (0 = không cài)
  [int]$TargetMax = 4      # số font tối đa sẽ cài (<= count DB)
)

# ------------ Admin check ------------
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
   ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
  Write-Host "ERROR: Run PowerShell as Administrator!" -ForegroundColor Red
  Read-Host "Press Enter to exit"; exit 1
}

$Version = "3.8.0"

# ------------ Logging ------------
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

# ------------ Paths ------------
$TempDir  = "$env:TEMP\FontRotator"
$FontsDir = "$env:SystemRoot\Fonts"
if (!(Test-Path $TempDir)) { New-Item -ItemType Directory -Path $TempDir -Force | Out-Null }

# ============================================================
#   LEAN DB — 100+ DIRECT TTF/OTF LINKS (Google/Noto trusted)
#   (Nếu 1–2 link lỗi 404, script tự bỏ qua và chọn link khác)
# ============================================================
$DB = @{
  Sans = @(
    "https://github.com/google/fonts/raw/main/ofl/roboto/static/Roboto-Regular.ttf",
    "https://github.com/google/fonts/raw/main/ofl/opensans/static/OpenSans-Regular.ttf",
    "https://github.com/google/fonts/raw/main/ofl/inter/static/Inter-Regular.ttf",
    "https://github.com/google/fonts/raw/main/ofl/montserrat/static/Montserrat-Regular.ttf",
    "https://github.com/google/fonts/raw/main/ofl/raleway/static/Raleway-Regular.ttf",
    "https://github.com/google/fonts/raw/main/ofl/lato/static/Lato-Regular.ttf",
    "https://github.com/google/fonts/raw/main/ofl/nunito/static/Nunito-Regular.ttf",
    "https://github.com/google/fonts/raw/main/ofl/nunitosans/static/NunitoSans-Regular.ttf",
    "https://github.com/google/fonts/raw/main/ofl/poppins/Poppins%5Bwght%5D.ttf",
    "https://github.com/google/fonts/raw/main/ofl/manrope/static/Manrope-Regular.ttf",
    "https://github.com/google/fonts/raw/main/ofl/urbanist/static/Urbanist-Regular.ttf",
    "https://github.com/google/fonts/raw/main/ofl/worksans/static/WorkSans-Regular.ttf",
    "https://github.com/google/fonts/raw/main/ofl/dmsans/static/DMSans-Regular.ttf",
    "https://github.com/google/fonts/raw/main/ofl/karla/static/Karla-Regular.ttf",
    "https://github.com/google/fonts/raw/main/ofl/mulish/static/Mulish-Regular.ttf",
    "https://github.com/google/fonts/raw/main/ofl/rubik/static/Rubik-Regular.ttf",
    "https://github.com/google/fonts/raw/main/ofl/cabin/static/Cabin-Regular.ttf",
    "https://github.com/google/fonts/raw/main/ofl/asap/static/Asap-Regular.ttf",
    "https://github.com/google/fonts/raw/main/ofl/ibmplexsans/IBMPlexSans-Regular.ttf",
    "https://github.com/google/fonts/raw/main/ofl/ptserif/PTSerif-Regular.ttf", # (Serif name in ofl, but keep diversity)
    "https://github.com/google/fonts/raw/main/ofl/ptsans/PTSans-Regular.ttf",
    "https://github.com/google/fonts/raw/main/ofl/lexend/static/Lexend-Regular.ttf",
    "https://github.com/google/fonts/raw/main/ofl/heebo/static/Heebo-Regular.ttf",
    "https://github.com/google/fonts/raw/main/ofl/outfit/static/Outfit-Regular.ttf",
    "https://github.com/google/fonts/raw/main/ofl/sora/static/Sora-Regular.ttf",
    "https://github.com/google/fonts/raw/main/ofl/plusjakartasans/static/PlusJakartaSans-Regular.ttf",
    "https://github.com/google/fonts/raw/main/ofl/ttcommonspro?dummy=skip" # placeholder safety
  )
  Serif = @(
    "https://github.com/google/fonts/raw/main/ofl/merriweather/Merriweather-Regular.ttf",
    "https://github.com/google/fonts/raw/main/ofl/lora/static/Lora-Regular.ttf",
    "https://github.com/google/fonts/raw/main/ofl/librebaskerville/LibreBaskerville-Regular.ttf",
    "https://github.com/google/fonts/raw/main/ofl/playfairdisplay/static/PlayfairDisplay-Regular.ttf",
    "https://github.com/google/fonts/raw/main/ofl/sourceserif4/static/SourceSerif4-Regular.ttf",
    "https://github.com/google/fonts/raw/main/ofl/cardos/Cardo-Regular.ttf",
    "https://github.com/google/fonts/raw/main/ofl/crimsonpro/static/CrimsonPro-Regular.ttf",
    "https://github.com/google/fonts/raw/main/ofl/cormorantgaramond/static/CormorantGaramond-Regular.ttf",
    "https://github.com/google/fonts/raw/main/ofl/oldstandardtt/OldStandardTT-Regular.ttf",
    "https://github.com/google/fonts/raw/main/ofl/abrilfatface/AbrilFatface-Regular.ttf",
    "https://github.com/google/fonts/raw/main/ofl/ibmplexserif/IBMPlexSerif-Regular.ttf",
    "https://github.com/google/fonts/raw/main/ofl/domine/static/Domine-Regular.ttf",
    "https://github.com/google/fonts/raw/main/ofl/spectral/static/Spectral-Regular.ttf",
    "https://github.com/google/fonts/raw/main/ofl/noto-serif/static/NotoSerif-Regular.ttf" # Alt path; some repos use noto-fonts (see below)
  )
  Mono = @(
    "https://github.com/google/fonts/raw/main/ofl/inconsolata/static/Inconsolata-Regular.ttf",
    "https://github.com/google/fonts/raw/main/ofl/sourcecodepro/static/SourceCodePro-Regular.ttf",
    "https://github.com/google/fonts/raw/main/ofl/jetbrainsmono/static/JetBrainsMono-Regular.ttf",
    "https://github.com/google/fonts/raw/main/ofl/spacemono/SpaceMono-Regular.ttf",
    "https://github.com/google/fonts/raw/main/ofl/ibmplexmono/IBMPlexMono-Regular.ttf",
    "https://github.com/google/fonts/raw/main/ofl/overpassmono/OverpassMono-Regular.ttf",
    "https://github.com/google/fonts/raw/main/ofl/redhatmono/static/RedHatMono-Regular.ttf",
    "https://github.com/google/fonts/raw/main/ofl/ptmono/PTMono-Regular.ttf",
    "https://github.com/google/fonts/raw/main/ofl/anonymouspro/AnonymousPro-Regular.ttf",
    "https://github.com/google/fonts/raw/main/ofl/cousine/Cousine-Regular.ttf"
  )
  SymbolsMath = @(
    # Noto (trusted raw)
    "https://raw.githubusercontent.com/googlefonts/noto-fonts/main/hinted/ttf/NotoSansMath/NotoSansMath-Regular.ttf",
    "https://raw.githubusercontent.com/googlefonts/noto-fonts/main/hinted/ttf/NotoSansSymbols2/NotoSansSymbols2-Regular.ttf",
    "https://raw.githubusercontent.com/googlefonts/noto-fonts/main/hinted/ttf/NotoMusic/NotoMusic-Regular.ttf",
    "https://raw.githubusercontent.com/googlefonts/noto-fonts/main/hinted/ttf/NotoSansDisplay/NotoSansDisplay-Regular.ttf",
    "https://raw.githubusercontent.com/googlefonts/noto-fonts/main/hinted/ttf/NotoSerifDisplay/NotoSerifDisplay-Regular.ttf",
    "https://raw.githubusercontent.com/googlefonts/noto-fonts/main/hinted/ttf/NotoSans/NotoSans-Regular.ttf",
    "https://raw.githubusercontent.com/googlefonts/noto-fonts/main/hinted/ttf/NotoSerif/NotoSerif-Regular.ttf",
    "https://raw.githubusercontent.com/googlefonts/noto-fonts/main/hinted/ttf/NotoSansMono/NotoSansMono-Regular.ttf"
  )
  Emoji = @(
    "https://raw.githubusercontent.com/googlefonts/noto-emoji/main/fonts/NotoColorEmoji.ttf"
  )
}

# ---- BỔ SUNG thêm nhiều Google Fonts trực tiếp để tổng pool ~100 ----
$More = @(
  "https://github.com/google/fonts/raw/main/ofl/assistant/static/Assistant-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/alata/Alata-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/arimo/static/Arimo-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/barlow/static/Barlow-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/barlowcondensed/static/BarlowCondensed-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/catamaran/static/Catamaran-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/chivo/static/Chivo-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/exo2/static/Exo2-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/ibmplexsanscondensed/IBMPlexSansCondensed-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/kantumruypro/static/KantumruyPro-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/kanit/static/Kanit-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/laborunion/LaborUnion-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/lalezar/Lalezar-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/mada/static/Mada-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/mavenpro/static/MavenPro-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/merriweathersans/MerriweatherSans-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/metropolis/Metropolis-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/michroma/Michroma-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/molengo/Molengo-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/monda/Monda-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/monoair/Monoair-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/notosansdisplay/static/NotoSansDisplay-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/overpass/static/Overpass-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/philosopher/Philosopher-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/poiretone/PoiretOne-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/pontanosans/PontanoSans-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/pragati/PragatiNarrow-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/prompt/static/Prompt-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/publicsans/static/PublicSans-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/quantico/Quantico-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/quicksand/static/Quicksand-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/rasa/static/Rasa-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/recursivesanscasual/static/RecursiveSansCasual-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/rokkitt/static/Rokkitt-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/rosario/Rosario%5Bwght%5D.ttf",
  "https://github.com/google/fonts/raw/main/ofl/rozhaone/RozhaOne-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/sarabun/static/Sarabun-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/shipporimincho/ShipporiMincho-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/signika/static/Signika-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/spartan/static/Spartan-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/specialelite/SpecialElite-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/taviraj/Taviraj-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/tinos/Tinos-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/titilliumweb/TitilliumWeb-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/ubuntu/Ubuntu%5Bit,wght%5D.ttf",
  "https://github.com/google/fonts/raw/main/ofl/abel/Abel-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/alegreya/static/Alegreya-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/alegreyasans/static/AlegreyaSans-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/alef/Alef-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/armata/Armata-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/arvo/Arvo-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/asapcondensed/AsapCondensed-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/assistant/static/Assistant-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/avenirnextltpro/AvenirNextLTPro-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/baskervville/Baskervville-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/bellefair/Bellefair-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/cardo/Cardo-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/cinzel/static/Cinzel-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/croissantone/CroissantOne-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/cutive/Cutive-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/ebgaramond/EBGaramond-VariableFont_wght.ttf",
  "https://github.com/google/fonts/raw/main/ofl/elsie/Elsie-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/fanwoodtext/FanwoodText-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/faustina/static/Faustina-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/gelasio/static/Gelasio-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/gentiumbookplus/static/GentiumBookPlus-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/italiana/Italiana-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/josefinslab/static/JosefinSlab-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/literata/static/Literata-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/lusitana/Lusitana-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/mate/Mate-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/meddon/Meddon.ttf",
  "https://github.com/google/fonts/raw/main/ofl/notosans/static/NotoSans-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/notoserif/static/NotoSerif-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/philosopher/Philosopher-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/play/Play-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/ptsansnarrow/PTSansNarrow-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/questrial/Questrial-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/robotoslab/static/RobotoSlab-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/rye/Rye-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/sortsMillgoudy/SortsMillGoudy-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/sourcecodepro/static/SourceCodePro-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/sourcesans3/static/SourceSans3-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/spacemono/SpaceMono-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/trirong/Trirong-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/ultra/Ultra-Regular.ttf",
  "https://github.com/google/fonts/raw/main/ofl/yrsa/Yrsa-Regular.ttf"
)
$DB.Sans += $More

# ------------ Helpers (only TTF/OTF) ------------
function Download-File {
  param([string]$Url,[string]$OutFile,[int]$Retry=2)
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
    Start-Sleep -Seconds ([Math]::Min(2*$i,6))
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

function Install-FromUrl { param([string]$Url)
  try {
    $lower = $Url.ToLower()
    if (!($lower.EndsWith(".ttf") -or $lower.EndsWith(".otf"))) {
      Say ("Skip non-ttf/otf: {0}" -f $Url) "Yellow" "WARN"; return @()
    }
    $out = Join-Path $TempDir ([IO.Path]::GetFileName($Url))
    if (!(Download-File $Url $out)) { Say ("Download failed: {0}" -f $Url) "Red" "ERROR"; return @() }
    $r = Install-One -File $out -Fallback "Custom"
    if ($r){,@($r)} else {@()}
  } catch { Say ("Install-FromUrl error: {0}" -f $_.Exception.Message) "Red" "ERROR"; @() }
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
      "Microsoft Sans Serif","Tahoma","MS Shell Dlg","MS Shell Dlg 2","Cambria Math"
    )
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

# SystemLink HKLM+HKCU
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

# FontSubstitutes HKLM+HKCU
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

# ---- Chromium default fonts patch ----
function Is-ProcRunning { param([string]$Name) try { (Get-Process -Name $Name -ErrorAction SilentlyContinue) -ne $null } catch { $false } }
function Patch-ChromiumFonts {
  param(
    [string]$PrefsPath,[string]$Sans,[string]$Serif,[string]$Mono,
    [string]$Cursive="Comic Sans MS",[string]$Fantasy="Impact"
  )
  if(!(Test-Path $PrefsPath)){ Log ("Chromium Prefs not found: {0}" -f $PrefsPath) "WARN"; return }
  if(Is-ProcRunning "chrome" -or Is-ProcRunning "msedge"){
    Say "Chrome/Edge đang chạy — bỏ qua vá default fonts. Hãy tắt trình duyệt và chạy lại với -ChromiumFonts nếu muốn." "Yellow" "WARN"
    return
  }
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
        "standard" { $Serif }
        "serif"    { $Serif }
        "sansserif"{ $Sans }
        "fixed"    { $Mono }
        "cursive"  { $Cursive }
        "fantasy"  { $Fantasy }
      }
    }
    ($json | ConvertTo-Json -Depth 20) | Set-Content -Encoding UTF8 $PrefsPath
    Say ("Patched Chromium Prefs: {0} (sans={1}, serif={2}, mono={3})" -f $PrefsPath,$Sans,$Serif,$Mono) "Green"
  } catch {
    Say ("Chromium patch error: {0}" -f $_.Exception.Message) "Red" "ERROR"
  }
}

# -------------------- MAIN --------------------
Clear-Host
Write-Host "==============================================================" -ForegroundColor Green
Write-Host ("  ADVANCED FONT FINGERPRINT ROTATOR v{0} (LEAN DB)" -f $Version) -ForegroundColor Yellow
Write-Host "==============================================================" -ForegroundColor Green
Log ("OS: {0}  PS: {1}" -f [Environment]::OSVersion.VersionString, $PSVersionTable.PSVersion)

# Baseline
$beforeCount = (CurFonts).Count
$beforeInv   = InvHash
$beforeFB    = FBHash
Say ("Current fonts: {0}" -f $beforeCount) "Cyan"
Say ("Inventory Hash: {0}..." -f (Head32 $beforeInv)) "Cyan"
Say ("Fallback Hash : {0}..." -f (Head32 $beforeFB)) "Cyan"

# --- 1) OPTIONAL: INSTALL FEW DIRECT TTF/OTF ---
function Install-Round {
  param([int]$Min=2,[int]$Max=4)
  $pool=@()
  foreach($k in $DB.Keys){ foreach($u in $DB[$k]){ if($u){ $pool += ,@{Url=$u} } } }
  if($pool.Count -eq 0 -or $Max -le 0){ return 0 }
  $count = Get-Random -Minimum $Min -Maximum ([Math]::Min($Max, [Math]::Max(1,$pool.Count))+1)
  $todo  = $pool | Get-Random -Count $count
  $ok=0
  foreach($x in $todo){
    $list = Install-FromUrl -Url $x.Url
    $ok += $list.Count
  }
  return $ok
}

$tries=0; $afterInv=$beforeInv
if($TargetMax -gt 0){
  do {
    $tries++
    [void](Install-Round -Min $TargetMin -Max $TargetMax)
    Start-Sleep 1
    $afterInv = InvHash
  } while ($afterInv -eq $beforeInv -and $tries -lt 2)  # 1-2 vòng là đủ
} else {
  $afterInv = $beforeInv
  Say "FAST MODE: Không cài thêm font." "Yellow"
}

# --- 2) RANDOMIZE FALLBACKS (Unicode Glyphs) ---
function Apply-RandomFallback {
  $map = FaceMap

  $sansDest  = PickFirst -Prefer @("Inter","Open Sans","Roboto","IBM Plex Sans","DejaVu Sans","Lato","Raleway","Montserrat","Noto Sans","Nunito Sans","Work Sans") -Map $map
  $serifDest = PickFirst -Prefer @("Merriweather","Lora","Libre Baskerville","Source Serif","Noto Serif","Playfair Display","Domine","Spectral","Cardo") -Map $map
  $monoDest  = PickFirst -Prefer @("JetBrains Mono","Source Code Pro","Inconsolata","Cousine","Anonymous Pro","IBM Plex Mono","Space Mono","PT Mono","Overpass Mono") -Map $map
  $sym1      = PickFirst -Prefer @("Noto Sans Math","Noto Sans Symbols 2","Noto Music") -Map $map
  $sym2      = PickFirst -Prefer @("Noto Sans Symbols 2","Noto Sans","Noto Serif") -Map $map
  $emojiDest = PickFirst -Prefer @("Noto Color Emoji") -Map $map -Exact

  $base = @("Segoe UI","Segoe UI Variable","Arial","Times New Roman","Courier New","Calibri","Cambria","Consolas","Microsoft Sans Serif","Tahoma","MS Shell Dlg","MS Shell Dlg 2") | Get-Random -Count 12

  $pairs=@()
  foreach($p in @($sansDest,$serifDest,$monoDest)) { if($p){ $pairs+=$p.Pair } }
  if($sym1){ $pairs = ,$sym1.Pair + $pairs }
  if($sym2){ $pairs += $sym2.Pair }

  foreach($b in $base){
    if($pairs.Count -gt 0){
      $take = Get-Random -Minimum 2 -Maximum ([Math]::Min(5,$pairs.Count)+1)
      Prepend-Link -Base $b -Pairs ($pairs | Get-Random -Count $take)
    }
  }
  if($sym1){ Prepend-Link -Base "Segoe UI Symbol" -Pairs @($sym1.Pair) }
  if($emojiDest){ Prepend-Link -Base "Segoe UI Emoji" -Pairs @($emojiDest.Pair) }

  if($sansDest){  Set-Sub "Segoe UI" $sansDest.Face; Set-Sub "Arial" $sansDest.Face; Set-Sub "Microsoft Sans Serif" $sansDest.Face }
  if($serifDest){ Set-Sub "Times New Roman" $serifDest.Face; Set-Sub "Cambria" $serifDest.Face }
  if($monoDest){  Set-Sub "Courier New" $monoDest.Face; Set-Sub "Consolas" $monoDest.Face }
  if($sym1){      Set-Sub "Segoe UI Symbol" $sym1.Face; Set-Sub "Cambria Math" $sym1.Face }
  if($emojiDest){ Set-Sub "Segoe UI Emoji" $emojiDest.Face }

  # Force-prepend để đổi nguồn glyph rõ rệt
  if($sym1 -and $monoDest){ Prepend-Link -Base "Arial"           -Pairs @($sym1.Pair,$monoDest.Pair) }
  if($serifDest -and $sym1){ Prepend-Link -Base "Times New Roman" -Pairs @($serifDest.Pair,$sym1.Pair) }
  if($monoDest -and $sym1){  Prepend-Link -Base "Courier New"     -Pairs @($monoDest.Pair,$sym1.Pair) }
  if($serifDest){            Prepend-Link -Base "Cambria"         -Pairs @($serifDest.Pair) }
  if($monoDest){             Prepend-Link -Base "Consolas"        -Pairs @($monoDest.Pair) }
  if($emojiDest){            Prepend-Link -Base "Segoe UI Emoji"  -Pairs @($emojiDest.Pair) }
  if($sym1){                 Prepend-Link -Base "Cambria Math"    -Pairs @($sym1.Pair) }

  Refresh-Fonts
  return @{Sans=$sansDest;Serif=$serifDest;Mono=$monoDest;Sym=$sym1;Emoji=$emojiDest}
}

$targets = Apply-RandomFallback
$afterFB = FBHash

# --- 3) (Optional) Patch Chrome/Edge default fonts ---
if($ChromiumFonts){
  $sansFace  = if($targets.Sans){ $targets.Sans.Face } else { "Inter" }
  $serifFace = if($targets.Serif){ $targets.Serif.Face } else { "Merriweather" }
  $monoFace  = if($targets.Mono){ $targets.Mono.Face } else { "Source Code Pro" }

  $chrome = Join-Path $env:LOCALAPPDATA ("Google\Chrome\User Data\{0}\Preferences" -f $ChromeProfile)
  $edge   = Join-Path $env:LOCALAPPDATA ("Microsoft\Edge\User Data\{0}\Preferences" -f $EdgeProfile)

  Patch-ChromiumFonts -PrefsPath $chrome -Sans $sansFace -Serif $serifFace -Mono $monoFace
  Patch-ChromiumFonts -PrefsPath $edge   -Sans $sansFace -Serif $serifFace -Mono $monoFace
}

# --- RESULTS ---
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
Log ("Run finished. v{0}" -f $Version)
