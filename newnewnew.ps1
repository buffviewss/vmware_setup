<# ===================================================================
  ADVANCED FONT FINGERPRINT ROTATOR v3.12-API-RAND-HOTFIX
  - Mỗi lần chạy: đổi Inventory (Font Metrics) + Unicode Glyphs
  - Nguồn tải: Fontsource (jsDelivr/unpkg) → GF CSS2 → GitHub GF (fallback)
  - Random SystemLink/Substitutes + patch Chrome/Edge default fonts
  Log: %USERPROFILE%\Downloads\log.txt
=================================================================== #>

param(
  [int]$InstallMin   = 12,
  [int]$InstallMax   = 18,
  [int]$UninstallMin = 6,
  [int]$UninstallMax = 10,
  [switch]$KeepGrowth = $false,
  [switch]$NoChromiumFonts = $false,
  [switch]$NoForceClose    = $false,
  [string]$ChromeProfile = "Default",
  [string]$EdgeProfile   = "Default",
  [int]$MaxRounds = 3
)

# ---- Admin check ----
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
   ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
  Write-Host "ERROR: Run PowerShell as Administrator!" -ForegroundColor Red
  Read-Host "Press Enter to exit"; exit 1
}

$Version = "3.12-API-RAND-HOTFIX"
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

# ---- Pools
$FAMILIES = @{
  Sans  = @("Inter","Open Sans","Roboto","Noto Sans","Work Sans","Manrope","Poppins",
            "DM Sans","Karla","Rubik","Cabin","Asap","Lexend","Heebo","Outfit",
            "Sora","Plus Jakarta Sans","Nunito Sans","Mulish","Urbanist","Montserrat",
            "Raleway","Lato","Source Sans 3","PT Sans","Fira Sans","IBM Plex Sans")
  Serif = @("Merriweather","Lora","Libre Baskerville","Playfair Display","Source Serif 4",
            "Cardo","Crimson Pro","Cormorant Garamond","Old Standard TT","Domine",
            "Spectral","EB Garamond","Gentium Book Plus","Literata","Tinos")
  Mono  = @("Source Code Pro","JetBrains Mono","Inconsolata","Cousine","Anonymous Pro",
            "Iosevka","Fira Code","IBM Plex Mono","Ubuntu Mono","Red Hat Mono")
}
$UNICODE_BOOST = @(
  @{ Name="Noto Color Emoji"; Urls=@(
     "https://raw.githubusercontent.com/googlefonts/noto-emoji/main/fonts/NotoColorEmoji.ttf",
     "https://cdn.jsdelivr.net/gh/googlefonts/noto-emoji@main/fonts/NotoColorEmoji.ttf"
  )},
  @{ Name="Noto Sans Symbols 2"; Urls=@(
     "https://raw.githubusercontent.com/googlefonts/noto-fonts/main/hinted/ttf/NotoSansSymbols2/NotoSansSymbols2-Regular.ttf",
     "https://cdn.jsdelivr.net/gh/googlefonts/noto-fonts@main/hinted/ttf/NotoSansSymbols2/NotoSansSymbols2-Regular.ttf"
  )},
  @{ Name="Noto Sans Math"; Urls=@(
     "https://raw.githubusercontent.com/googlefonts/noto-fonts/main/hinted/ttf/NotoSansMath/NotoSansMath-Regular.ttf",
     "https://cdn.jsdelivr.net/gh/googlefonts/noto-fonts@main/hinted/ttf/NotoSansMath/NotoSansMath-Regular.ttf"
  )},
  @{ Name="Noto Music"; Urls=@(
     "https://raw.githubusercontent.com/googlefonts/noto-fonts/main/hinted/ttf/NotoMusic/NotoMusic-Regular.ttf",
     "https://cdn.jsdelivr.net/gh/googlefonts/noto-fonts@main/hinted/ttf/NotoMusic/NotoMusic-Regular.ttf"
  )}
)

# ===================== API RESOLVERS =====================

# Hard map (khi mạng khó/ bị chặn API)
$HardMap = @{
  "Inter"              = @("https://cdn.jsdelivr.net/npm/@fontsource/inter/files/inter-latin-400-normal.ttf","https://unpkg.com/@fontsource/inter/files/inter-latin-400-normal.ttf")
  "Roboto"             = @("https://cdn.jsdelivr.net/npm/@fontsource/roboto/files/roboto-latin-400-normal.ttf","https://unpkg.com/@fontsource/roboto/files/roboto-latin-400-normal.ttf")
  "Open Sans"          = @("https://cdn.jsdelivr.net/npm/@fontsource/open-sans/files/open-sans-latin-400-normal.ttf","https://unpkg.com/@fontsource/open-sans/files/open-sans-latin-400-normal.ttf")
  "Montserrat"         = @("https://cdn.jsdelivr.net/npm/@fontsource/montserrat/files/montserrat-latin-400-normal.ttf","https://unpkg.com/@fontsource/montserrat/files/montserrat-latin-400-normal.ttf")
  "Manrope"            = @("https://cdn.jsdelivr.net/npm/@fontsource/manrope/files/manrope-latin-400-normal.ttf","https://unpkg.com/@fontsource/manrope/files/manrope-latin-400-normal.ttf")
  "Poppins"            = @("https://cdn.jsdelivr.net/npm/@fontsource/poppins/files/poppins-latin-400-normal.ttf","https://unpkg.com/@fontsource/poppins/files/poppins-latin-400-normal.ttf")
  "DM Sans"            = @("https://cdn.jsdelivr.net/npm/@fontsource/dm-sans/files/dm-sans-latin-400-normal.ttf","https://unpkg.com/@fontsource/dm-sans/files/dm-sans-latin-400-normal.ttf")
  "Karla"              = @("https://cdn.jsdelivr.net/npm/@fontsource/karla/files/karla-latin-400-normal.ttf","https://unpkg.com/@fontsource/karla/files/karla-latin-400-normal.ttf")
  "Rubik"              = @("https://cdn.jsdelivr.net/npm/@fontsource/rubik/files/rubik-latin-400-normal.ttf","https://unpkg.com/@fontsource/rubik/files/rubik-latin-400-normal.ttf")
  "Heebo"              = @("https://cdn.jsdelivr.net/npm/@fontsource/heebo/files/heebo-latin-400-normal.ttf","https://unpkg.com/@fontsource/heebo/files/heebo-latin-400-normal.ttf")
  "Outfit"             = @("https://cdn.jsdelivr.net/npm/@fontsource/outfit/files/outfit-latin-400-normal.ttf","https://unpkg.com/@fontsource/outfit/files/outfit-latin-400-normal.ttf")
  "Sora"               = @("https://cdn.jsdelivr.net/npm/@fontsource/sora/files/sora-latin-400-normal.ttf","https://unpkg.com/@fontsource/sora/files/sora-latin-400-normal.ttf")
  "Plus Jakarta Sans"  = @("https://cdn.jsdelivr.net/npm/@fontsource/plus-jakarta-sans/files/plus-jakarta-sans-latin-400-normal.ttf","https://unpkg.com/@fontsource/plus-jakarta-sans/files/plus-jakarta-sans-latin-400-normal.ttf")
  "Nunito Sans"        = @("https://cdn.jsdelivr.net/npm/@fontsource/nunito-sans/files/nunito-sans-latin-400-normal.ttf","https://unpkg.com/@fontsource/nunito-sans/files/nunito-sans-latin-400-normal.ttf")
  "Mulish"             = @("https://cdn.jsdelivr.net/npm/@fontsource/mulish/files/mulish-latin-400-normal.ttf","https://unpkg.com/@fontsource/mulish/files/mulish-latin-400-normal.ttf")
  "Urbanist"           = @("https://cdn.jsdelivr.net/npm/@fontsource/urbanist/files/urbanist-latin-400-normal.ttf","https://unpkg.com/@fontsource/urbanist/files/urbanist-latin-400-normal.ttf")
  "Raleway"            = @("https://cdn.jsdelivr.net/npm/@fontsource/raleway/files/raleway-latin-400-normal.ttf","https://unpkg.com/@fontsource/raleway/files/raleway-latin-400-normal.ttf")
  "Lato"               = @("https://cdn.jsdelivr.net/npm/@fontsource/lato/files/lato-latin-400-normal.ttf","https://unpkg.com/@fontsource/lato/files/lato-latin-400-normal.ttf")
  "Source Sans 3"      = @("https://cdn.jsdelivr.net/npm/@fontsource/source-sans-3/files/source-sans-3-latin-400-normal.ttf","https://unpkg.com/@fontsource/source-sans-3/files/source-sans-3-latin-400-normal.ttf")
  "PT Sans"            = @("https://cdn.jsdelivr.net/npm/@fontsource/pt-sans/files/pt-sans-latin-400-normal.ttf","https://unpkg.com/@fontsource/pt-sans/files/pt-sans-latin-400-normal.ttf")
  "Fira Sans"          = @("https://cdn.jsdelivr.net/npm/@fontsource/fira-sans/files/fira-sans-latin-400-normal.ttf","https://unpkg.com/@fontsource/fira-sans/files/fira-sans-latin-400-normal.ttf")
  "IBM Plex Sans"      = @("https://cdn.jsdelivr.net/npm/@fontsource/ibm-plex-sans/files/ibm-plex-sans-latin-400-normal.ttf","https://unpkg.com/@fontsource/ibm-plex-sans/files/ibm-plex-sans-latin-400-normal.ttf")
  "Merriweather"       = @("https://cdn.jsdelivr.net/npm/@fontsource/merriweather/files/merriweather-latin-400-normal.ttf","https://unpkg.com/@fontsource/merriweather/files/merriweather-latin-400-normal.ttf")
  "Lora"               = @("https://cdn.jsdelivr.net/npm/@fontsource/lora/files/lora-latin-400-normal.ttf","https://unpkg.com/@fontsource/lora/files/lora-latin-400-normal.ttf")
  "Libre Baskerville"  = @("https://cdn.jsdelivr.net/npm/@fontsource/libre-baskerville/files/libre-baskerville-latin-400-normal.ttf","https://unpkg.com/@fontsource/libre-baskerville/files/libre-baskerville-latin-400-normal.ttf")
  "Playfair Display"   = @("https://cdn.jsdelivr.net/npm/@fontsource/playfair-display/files/playfair-display-latin-400-normal.ttf","https://unpkg.com/@fontsource/playfair-display/files/playfair-display-latin-400-normal.ttf")
  "Source Serif 4"     = @("https://cdn.jsdelivr.net/npm/@fontsource/source-serif-4/files/source-serif-4-latin-400-normal.ttf","https://unpkg.com/@fontsource/source-serif-4/files/source-serif-4-latin-400-normal.ttf")
  "Domine"             = @("https://cdn.jsdelivr.net/npm/@fontsource/domine/files/domine-latin-400-normal.ttf","https://unpkg.com/@fontsource/domine/files/domine-latin-400-normal.ttf")
  "EB Garamond"        = @("https://cdn.jsdelivr.net/npm/@fontsource/eb-garamond/files/eb-garamond-latin-400-normal.ttf","https://unpkg.com/@fontsource/eb-garamond/files/eb-garamond-latin-400-normal.ttf")
  "Gentium Book Plus"  = @("https://cdn.jsdelivr.net/npm/@fontsource/gentium-book-plus/files/gentium-book-plus-latin-400-normal.ttf","https://unpkg.com/@fontsource/gentium-book-plus/files/gentium-book-plus-latin-400-normal.ttf")
  "Literata"           = @("https://cdn.jsdelivr.net/npm/@fontsource/literata/files/literata-latin-400-normal.ttf","https://unpkg.com/@fontsource/literata/files/literata-latin-400-normal.ttf")
  "Tinos"              = @("https://cdn.jsdelivr.net/npm/@fontsource/tinos/files/tinos-latin-400-normal.ttf","https://unpkg.com/@fontsource/tinos/files/tinos-latin-400-normal.ttf")
  "Old Standard TT"    = @("https://cdn.jsdelivr.net/npm/@fontsource/old-standard-tt/files/old-standard-tt-latin-400-normal.ttf","https://unpkg.com/@fontsource/old-standard-tt/files/old-standard-tt-latin-400-normal.ttf")
  "Cormorant Garamond" = @("https://cdn.jsdelivr.net/npm/@fontsource/cormorant-garamond/files/cormorant-garamond-latin-400-normal.ttf","https://unpkg.com/@fontsource/cormorant-garamond/files/cormorant-garamond-latin-400-normal.ttf")
  "Source Code Pro"    = @("https://cdn.jsdelivr.net/npm/@fontsource/source-code-pro/files/source-code-pro-latin-400-normal.ttf","https://unpkg.com/@fontsource/source-code-pro/files/source-code-pro-latin-400-normal.ttf")
  "JetBrains Mono"     = @("https://cdn.jsdelivr.net/npm/@fontsource/jetbrains-mono/files/jetbrains-mono-latin-400-normal.ttf","https://unpkg.com/@fontsource/jetbrains-mono/files/jetbrains-mono-latin-400-normal.ttf")
  "Inconsolata"        = @("https://cdn.jsdelivr.net/npm/@fontsource/inconsolata/files/inconsolata-latin-400-normal.ttf","https://unpkg.com/@fontsource/inconsolata/files/inconsolata-latin-400-normal.ttf")
  "Cousine"            = @("https://cdn.jsdelivr.net/npm/@fontsource/cousine/files/cousine-latin-400-normal.ttf","https://unpkg.com/@fontsource/cousine/files/cousine-latin-400-normal.ttf")
  "Anonymous Pro"      = @("https://cdn.jsdelivr.net/npm/@fontsource/anonymous-pro/files/anonymous-pro-latin-400-normal.ttf","https://unpkg.com/@fontsource/anonymous-pro/files/anonymous-pro-latin-400-normal.ttf")
  "Iosevka"            = @("https://cdn.jsdelivr.net/npm/@fontsource/iosevka/files/iosevka-latin-400-normal.ttf","https://unpkg.com/@fontsource/iosevka/files/iosevka-latin-400-normal.ttf")
  "Fira Code"          = @("https://cdn.jsdelivr.net/npm/@fontsource/fira-code/files/fira-code-latin-400-normal.ttf","https://unpkg.com/@fontsource/fira-code/files/fira-code-latin-400-normal.ttf")
  "IBM Plex Mono"      = @("https://cdn.jsdelivr.net/npm/@fontsource/ibm-plex-mono/files/ibm-plex-mono-latin-400-normal.ttf","https://unpkg.com/@fontsource/ibm-plex-mono/files/ibm-plex-mono-latin-400-normal.ttf")
  "Ubuntu Mono"        = @("https://cdn.jsdelivr.net/npm/@fontsource/ubuntu-mono/files/ubuntu-mono-latin-400-normal.ttf","https://unpkg.com/@fontsource/ubuntu-mono/files/ubuntu-mono-latin-400-normal.ttf")
  "Red Hat Mono"       = @("https://cdn.jsdelivr.net/npm/@fontsource/red-hat-mono/files/red-hat-mono-latin-400-normal.ttf","https://unpkg.com/@fontsource/red-hat-mono/files/red-hat-mono-latin-400-normal.ttf")
}

# Fontsource slug & GF ofl folder helpers
$FontsourceMap = @{
  "Plus Jakarta Sans" = "plus-jakarta-sans"; "Source Serif 4"="source-serif-4"; "Old Standard TT"="old-standard-tt"
  "EB Garamond"="eb-garamond"; "IBM Plex Sans"="ibm-plex-sans"; "IBM Plex Mono"="ibm-plex-mono"
  "PT Sans"="pt-sans"; "Fira Sans"="fira-sans"; "Source Sans 3"="source-sans-3"; "Red Hat Mono"="red-hat-mono"
  "Playfair Display"="playfair-display"; "Gentium Book Plus"="gentium-book-plus"; "JetBrains Mono"="jetbrains-mono"
}
$GFNameMap = @{
  "Plus Jakarta Sans"="plusjakartasans"; "Source Serif 4"="sourceserif4"; "Old Standard TT"="oldstandardtt"
  "EB Garamond"="ebgaramond"; "IBM Plex Sans"="ibmplexsans"; "IBM Plex Mono"="ibmplexmono"
  "Source Sans 3"="sourcesans3"; "PT Sans"="ptsans"; "Red Hat Mono"="redhatmono"
  "Playfair Display"="playfairdisplay"; "Gentium Book Plus"="gentiumbookplus"; "JetBrains Mono"="jetbrainsmono"
}
function To-PackageName { param([string]$family) if($FontsourceMap.ContainsKey($family)){ $FontsourceMap[$family] } else { ($family.ToLower() -replace '[\s_]+','-') } }
function To-GFFolder   { param([string]$family) if($GFNameMap.ContainsKey($family)){ $GFNameMap[$family] } else { ($family.ToLower() -replace '[^a-z0-9]','') } }

# 1) Fontsource direct (không HEAD – để Download-File tự thử)
function Get-FontFromFontsource {
  param([string]$Family)
  if($HardMap.ContainsKey($Family)){ return $HardMap[$Family] }
  $pkg = To-PackageName $Family
  $file = "$pkg-latin-400-normal.ttf"
  ,@("https://cdn.jsdelivr.net/npm/@fontsource/$pkg/files/$file",
     "https://unpkg.com/@fontsource/$pkg/files/$file")
}

# 2) Google Fonts CSS2 (gstatic TTF – UA Android 4.4)
function Get-FontFromGoogleCSS {
  param([string]$Family,[int[]]$Weights=@(400,500,300))
  $ua = 'Mozilla/5.0 (Linux; Android 4.4; Nexus 5 Build/KRT16M) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/30.0.0.0 Mobile Safari/537.36'
  $headers = @{ 'User-Agent'=$ua; 'Accept'='text/css,*/*;q=0.1'; 'Referer'='https://fonts.googleapis.com/' }
  foreach($w in $Weights){
    foreach($fmt in @("wght@$w","ital,wght@0,$w")){
      $famQuery = [uri]::EscapeDataString($Family) -replace '%20','+'
      $cssUrl = "https://fonts.googleapis.com/css2?family=$famQuery:$fmt&display=swap"
      try {
        $css = Invoke-WebRequest -Headers $headers -UseBasicParsing -TimeoutSec 60 $cssUrl
        $ttf = ([regex]'url\(([^)]+\.ttf)\)').Matches($css.Content) | ForEach-Object { $_.Groups[1].Value.Trim("'`"") }
        $uniq = $ttf | Select-Object -Unique
        if($uniq -and $uniq.Count){ return $uniq }
      } catch { Log ("GF CSS2 error ($Family/$fmt): $($_.Exception.Message)") "WARN" }
    }
  }
  @()
}

# 3) GitHub GF (API) – fallback
function Get-FontFromGitHubGF {
  param([string]$Family)
  $folder = To-GFFolder $Family
  $api = "https://api.github.com/repos/google/fonts/contents/ofl/$folder"
  try {
    $list = Invoke-WebRequest -UseBasicParsing -TimeoutSec 60 -Headers @{ 'User-Agent'='FontRotator/3.12' } $api | ConvertFrom-Json
    $ttf = $list | Where-Object { $_.type -eq 'file' -and $_.name -match '\.(ttf|otf)$' } | Select-Object -ExpandProperty name
    $pick = ($ttf | Where-Object { $_ -match 'wght' } | Select-Object -First 1); if(-not $pick){ $pick = $ttf | Select-Object -First 1 }
    if($pick){ ,@("https://raw.githubusercontent.com/google/fonts/main/ofl/$folder/$pick") } else { @() }
  } catch { Log ("GitHub GF API error ($Family): $($_.Exception.Message)") "WARN"; @() }
}

function Resolve-FontTTF { param([string]$Family)
  $urls=@()
  $urls += Get-FontFromFontsource $Family
  if(-not $urls -or $urls.Count -lt 2){ $urls += Get-FontFromGoogleCSS $Family }
  if(-not $urls){ $urls += Get-FontFromGitHubGF $Family }
  $urls | Select-Object -Unique
}

# ===================== Core helpers =====================
function Download-File {
  param([string[]]$Urls,[string]$OutFile,[int]$Retry=2)
  $ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36'
  foreach($u in $Urls){
    for($i=1;$i -le $Retry;$i++){
      try {
        Log ("Download attempt {0}: {1}" -f $i,$u)
        if ($PSVersionTable.PSVersion.Major -ge 7) {
          Invoke-WebRequest -Uri $u -OutFile $OutFile -TimeoutSec 240 -Headers @{ 'User-Agent'=$ua }
        } else {
          try { Start-BitsTransfer -Source $u -Destination $OutFile -ErrorAction Stop }
          catch { Invoke-WebRequest -Uri $u -OutFile $OutFile -Headers @{ 'User-Agent'=$ua } }
        }
        if ((Test-Path $OutFile) -and ((Get-Item $OutFile).Length -gt 1000)) { Log ("Download OK: {0}" -f $OutFile); return $true }
      } catch { Log ("Download error: {0}" -f $_.Exception.Message) "ERROR" }
      Start-Sleep -Seconds ([Math]::Min((Get-Random -Minimum 1 -Maximum 5)*$i,8))
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
    $reg = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
    $props = (Get-ItemProperty $reg -ErrorAction SilentlyContinue).PSObject.Properties |
      Where-Object { $_.Value -and ($_.Value -ieq $File) }
    foreach($p in $props){ try { Remove-ItemProperty -Path $reg -Name $p.Name -ErrorAction SilentlyContinue } catch {} }
    if(Test-Path $full){ try { Remove-Item $full -Force -ErrorAction SilentlyContinue } catch {} }
    Say ("Uninstalled file: {0}" -f $File) "Yellow"
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
      foreach($b in $bases){ $v=(Get-ItemProperty -Path $sys -Name $b -ErrorAction SilentlyContinue).$b; if($v){$rows+=("SYS[{0}]:{1}={2}" -f $root,$b,($v -join ';'))}}
      foreach($n in $bases){ $vv=(Get-ItemProperty -Path $sub -Name $n -ErrorAction SilentlyContinue).$n; if($vv){$rows+=("SUB[{0}]:{1}={2}" -f $root,$n,$vv)}}
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

# --- PickRandom cho generic ---
function PickRandom { param([string[]]$Prefer,[hashtable]$Map,[switch]$Exact)
  $candidates=@()
  foreach($n in $Prefer){
    foreach($k in $Map.Keys){
      $ok = if($Exact){ $k -eq $n } else { ($k -eq $n) -or ($k -like ($n + "*")) }
      if($ok){
        $f=$Map[$k]
        if($f -and (Test-Path (Join-Path $env:SystemRoot\Fonts $f))){
          $candidates += ,@{Face=$k;Pair=("{0},{1}" -f $f,$k)}
        }
      }
    }
  }
  if($candidates.Count -gt 0){ return ($candidates | Get-Random) } else { $null }
}

# ---- Chromium helpers ----
function Is-ProcRunning { param([string]$Name) try { (Get-Process -Name $Name -ErrorAction SilentlyContinue) -ne $null } catch { $false } }
function Kill-Browsers { foreach($p in @("chrome","msedge")){ try { if(Is-ProcRunning $p){ Stop-Process -Name $p -Force -ErrorAction SilentlyContinue; Start-Sleep 1; Say ("Killed: {0}" -f $p) "Yellow" } } catch {} } }
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
    Say ("Patched Chromium Prefs: {0} (sans={1}, serif={2}, mono={3}, cursive={4}, fantasy={5})" -f $PrefsPath,$Sans,$Serif,$Mono,$Cursive,$Fantasy) "Green"
  } catch { Say ("Chromium patch error: {0}" -f $_.Exception.Message) "Red" "ERROR" }
}

# ===================== MAIN =====================
Clear-Host
Write-Host "==============================================================" -ForegroundColor Green
Write-Host ("  ADVANCED FONT FINGERPRINT ROTATOR v{0}" -f $Version) -ForegroundColor Yellow
Write-Host "==============================================================" -ForegroundColor Green
Log ("OS: {0}  PS: {1}" -f [Environment]::OSVersion.VersionString, $PSVersionTable.PSVersion)

$beforeInv = InvHash; $beforeFB = FBHash
Say ("Inventory Hash: {0}..." -f (Head32 $beforeInv)) "Cyan"
Say ("Fallback Hash : {0}..." -f (Head32 $beforeFB)) "Cyan"

for($round=1; $round -le $MaxRounds; $round++){
  Say ("--- ROUND {0} ---" -f $round) "White"

  # 0) Uninstall (an toàn)
  if(-not $KeepGrowth){
    $owned = (Get-ItemProperty -Path $StateKey -Name "Owned" -ErrorAction SilentlyContinue).Owned
    $ownedCount = if($owned){ $owned.Count } else { 0 }
    if($ownedCount -gt 0){
      $rmMax = [Math]::Min($UninstallMax, $ownedCount)
      $rmMin = [Math]::Min($UninstallMin, $rmMax)
      $rmCount = Get-Random -Minimum $rmMin -Maximum ($rmMax+1)
      if($rmCount -gt 0){
        $rmList = $owned | Get-Random -Count $rmCount
        Say ("Uninstalling {0} previously-installed fonts..." -f $rmList.Count) "Yellow"
        Refresh-Fonts
        foreach($f in $rmList){ Uninstall-One $f }
        Refresh-Fonts
      } else {
        Say ("Uninstalling 0 previously-installed fonts...") "Yellow"
      }
    } else {
      Say ("Uninstalling 0 previously-installed fonts...") "Yellow"
    }
  }

  # 1) INSTALL fresh: boosters + family via API
  $target = Get-Random -Minimum $InstallMin -Maximum ($InstallMax+1)
  $familyBag=@(); foreach($cat in $FAMILIES.Keys){ foreach($fam in $FAMILIES[$cat]){ $familyBag += ,@{Cat=$cat;Fam=$fam} } }
  $familyPick = $familyBag | Get-Random -Count ([Math]::Min($target, $familyBag.Count))
  $installed=0

  foreach($b in ($UNICODE_BOOST | Get-Random -Count ([Math]::Min(3,$UNICODE_BOOST.Count)))){
    $first = $b.Urls[0]; $name = $b.Name
    $out = Join-Path $TempDir ([IO.Path]::GetFileName($first))
    if(Download-File -Urls $b.Urls -OutFile $out){ if(Install-One -SrcPath $out -Fallback $name){ $installed++ } }
  }

  foreach($t in $familyPick){
    $fam = $t.Fam
    $urls = Resolve-FontTTF $fam
    if($urls -and $urls.Count){
      $fname = [IO.Path]::GetFileName((($urls[0] -split '\?')[0]))
      if(-not $fname.EndsWith(".ttf") -and -not $fname.EndsWith(".otf")){ $fname = ($fam -replace '\s','') + ".ttf" }
      $out = Join-Path $TempDir $fname
      if(Download-File -Urls $urls -OutFile $out){ if(Install-One -SrcPath $out -Fallback $fam){ $installed++ } }
      else { Say ("Download failed via API: {0}" -f $fam) "Red" "ERROR" }
    } else { Say ("API could not resolve: {0}" -f $fam) "Red" "ERROR" }
  }

  # 1b) Fallback synth nếu mạng kém
  if($installed -lt [Math]::Max(3,[Math]::Floor($target/3))){
    $owned = (Get-ItemProperty -Path $StateKey -Name "Owned" -ErrorAction SilentlyContinue).Owned
    if($owned -and $owned.Count -gt 0){
      $dupCount = [Math]::Min(3, $owned.Count)
      foreach($f in ($owned | Get-Random -Count $dupCount)){
        $src = Join-Path $FontsDir $f
        if(Test-Path $src){
          $new = ([IO.Path]::GetFileNameWithoutExtension($f)) + ("-{0}.ttf" -f (Get-Random -Minimum 1000 -Maximum 9999))
          $dst = Join-Path $FontsDir $new
          try {
            Copy-Item $src $dst -Force
            $reg="HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
            $face = Get-FontFace $dst
            $key = ("{0} (TrueType)" -f $face)
            New-ItemProperty -Path $reg -Name $key -Value $new -PropertyType String -Force | Out-Null
            $owned2 = (Get-ItemProperty -Path $StateKey -Name "Owned" -ErrorAction SilentlyContinue).Owned
            if(-not $owned2){ $owned2=@() }; $owned2 = $owned2 + $new | Select-Object -Unique
            New-ItemProperty -Path $StateKey -Name "Owned" -Value $owned2 -PropertyType MultiString -Force | Out-Null
            Say ("Synthesized duplicate: {0}" -f $new) "Yellow"
          } catch {}
        }
      }
    }
  }

  # 2) RANDOMIZE fallbacks + substitutes (thêm cursive/fantasy)
  $map = FaceMap
  $sans  = PickRandom -Prefer @("Inter","Open Sans","Noto Sans","Work Sans","Manrope","Poppins","DM Sans","Karla","Rubik","Heebo","Outfit","Sora","Plus Jakarta Sans","Nunito Sans","Mulish","Urbanist","Lato","Raleway","Montserrat") -Map $map
  $serif = PickRandom -Prefer @("Merriweather","Lora","Libre Baskerville","Playfair Display","Source Serif","Source Serif 4","Cardo","Crimson Pro","Cormorant Garamond","Old Standard TT","Domine","Spectral","EB Garamond","Gentium Book Plus","Literata","Tinos") -Map $map
  $mono  = PickRandom -Prefer @("JetBrains Mono","Source Code Pro","Inconsolata","Cousine","Anonymous Pro","IBM Plex Mono","Ubuntu Mono","Red Hat Mono","Consolas","Courier New") -Map $map
  $cursive = PickRandom -Prefer @("Comic Sans MS","Segoe Script","Gabriola","Lucida Handwriting") -Map $map
  $fantasy = PickRandom -Prefer @("Impact","Haettenschweiler","Showcard Gothic","Papyrus","Jokerman","Arial Black") -Map $map
  $sym1  = PickRandom -Prefer @("Noto Sans Math","Noto Sans Symbols 2") -Map $map
  $sym2  = PickRandom -Prefer @("Noto Music","Noto Sans Symbols 2","Noto Sans") -Map $map
  $emoji = PickRandom -Prefer @("Noto Color Emoji") -Map $map -Exact

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
  if($sym1){ Prepend-Link -Base "Segoe UI Symbol" -Pairs @($sym1.Pair); }
  if($emoji){ Prepend-Link -Base "Segoe UI Emoji"  -Pairs @($emoji.Pair); }
  if($sans){  New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -Name "Segoe UI" -Value $sans.Face -PropertyType String -Force | Out-Null
              New-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -Name "Segoe UI" -Value $sans.Face -PropertyType String -Force | Out-Null
              New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -Name "Arial" -Value $sans.Face -PropertyType String -Force | Out-Null
              New-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -Name "Arial" -Value $sans.Face -PropertyType String -Force | Out-Null }
  if($serif){ Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -Name "Times New Roman" -Value $serif.Face -Force
              Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -Name "Times New Roman" -Value $serif.Face -Force
              New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -Name "Cambria" -Value $serif.Face -PropertyType String -Force | Out-Null
              New-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -Name "Cambria" -Value $serif.Face -PropertyType String -Force | Out-Null }
  if($mono){  Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -Name "Courier New" -Value $mono.Face -Force
              Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -Name "Courier New" -Value $mono.Face -Force
              New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -Name "Consolas" -Value $mono.Face -PropertyType String -Force | Out-Null
              New-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -Name "Consolas" -Value $mono.Face -PropertyType String -Force | Out-Null }
  if($sym1){  Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -Name "Segoe UI Symbol" -Value $sym1.Face -Force
              Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -Name "Segoe UI Symbol" -Value $sym1.Face -Force
              Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -Name "Cambria Math" -Value $sym1.Face -Force
              Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -Name "Cambria Math" -Value $sym1.Face -Force }
  if($emoji){ Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -Name "Segoe UI Emoji" -Value $emoji.Face -Force
              Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -Name "Segoe UI Emoji" -Value $emoji.Face -Force }
  if($cursive){ Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -Name "Comic Sans MS" -Value $cursive.Face -Force
                Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -Name "Comic Sans MS" -Value $cursive.Face -Force }
  if($fantasy){ Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -Name "Impact" -Value $fantasy.Face -Force
                Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" -Name "Impact" -Value $fantasy.Face -Force }
  Refresh-Fonts

  # 3) Patch Chromium
  if(-not $NoForceClose){ Kill-Browsers }
  if(-not $NoChromiumFonts){
    $sf = if($sans){$sans.Face}else{"Arial"}
    $rf = if($serif){$serif.Face}else{"Times New Roman"}
    $mf = if($mono){$mono.Face}else{"Consolas"}
    $cf = if($cursive){$cursive.Face}else{"Comic Sans MS"}
    $ff = if($fantasy){$fantasy.Face}else{"Impact"}
    $chrome = Join-Path $env:LOCALAPPDATA ("Google\Chrome\User Data\{0}\Preferences" -f $ChromeProfile)
    $edge   = Join-Path $env:LOCALAPPDATA ("Microsoft\Edge\User Data\{0}\Preferences" -f $EdgeProfile)
    Patch-ChromiumFonts -PrefsPath $chrome -Sans $sf -Serif $rf -Mono $mf -Cursive $cf -Fantasy $ff
    Patch-ChromiumFonts -PrefsPath $edge   -Sans $sf -Serif $rf -Mono $mf -Cursive $cf -Fantasy $ff
  } else { Say "NoChromiumFonts: SKIP patch Chrome/Edge." "Yellow" }

  # 4) Check hashes
  $newInv = InvHash; $newFB = FBHash
  Say ("Round {0} Inventory:  {1} -> {2}" -f $round,(Head32 $beforeInv),(Head32 $newInv)) "White"
  Say ("Round {0} Fallback :  {1} -> {2}" -f $round,(Head32 $beforeFB),(Head32 $newFB)) "White"
  $invChanged = ($newInv -ne $beforeInv)
  $fbChanged  = ($newFB -ne $beforeFB)
  if($invChanged -and $fbChanged){ Say ("SUCCESS: Both hashes changed in round {0}" -f $round) "Green"; break }
  else { Say ("Hashes not both changed (Inv={0}, FB={1}) -> retry" -f ($invChanged),($fbChanged)) "Yellow"; $beforeInv=$newInv; $beforeFB=$newFB }
}

# --- Final
$finalInv = InvHash; $finalFB = FBHash
Say "`n--- FINAL HASHES ---" "Cyan"
Say ("Inventory:  {0}" -f $finalInv) "White"
Say ("Fallback :  {0}" -f $finalFB) "White"
Log ("Run finished. v{0}" -f $Version)
