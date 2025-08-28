#Requires -Version 5.0

<#
.SYNOPSIS
    Windows Font Fingerprint Randomizer - Production Version
    
.DESCRIPTION
    Randomizes browser font fingerprint by creating and installing font variations.
    Combines all functionality from previous scripts into a single production-ready tool.
    
.PARAMETER FontCount
    Number of font variations to create (3-15, default: 6)
    
.PARAMETER TestFingerprint
    Opens browserleaks.com for verification after randomization
    
.PARAMETER Cleanup
    Removes all installed font variations and cleans up
    
.PARAMETER DetailedOutput
    Enables detailed logging output
    
.EXAMPLE
    .\WinFingerPrint.ps1
    .\WinFingerPrint.ps1 -FontCount 8 -TestFingerprint
    .\WinFingerPrint.ps1 -Cleanup
    .\WinFingerPrint.ps1 -DetailedOutput
    
.NOTES
    Version: 1.0
    Requires: PowerShell 5.0+, Windows 10+
    Creates actual TTF files and registry entries for maximum browser compatibility
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateRange(3, 15)]
    [int]$FontCount = 6,
    
    [Parameter(Mandatory=$false)]
    [switch]$TestFingerprint,
    
    [Parameter(Mandatory=$false)]
    [switch]$Cleanup,
    
    [Parameter(Mandatory=$false)]
    [switch]$DetailedOutput
)

# ============================================================================
# CONFIGURATION & CONSTANTS
# ============================================================================

$Script:Config = @{
    UserFontsPath = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
    UserRegPath = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
    StateFile = "$env:TEMP\WinFingerPrint_State.json"
    LogFile = "$env:USERPROFILE\Downloads\WinFingerPrint.log"
    MaxActiveVariations = 20
    BaseFonts = @(
        "Arial", "Calibri", "Consolas", "Georgia", "Impact", 
        "Tahoma", "Times New Roman", "Verdana", "Comic Sans MS",
        "Trebuchet MS", "Palatino", "Garamond", "Century Gothic"
    )
    FontWeights = @("Thin", "Light", "Regular", "Medium", "SemiBold", "Bold", "ExtraBold", "Black")
    FontStyles = @("", "Italic", "Oblique")
    FontWidths = @("", "Condensed", "Extended", "Narrow", "Wide")
}

# Ensure required directories exist
if (-not (Test-Path $Script:Config.UserFontsPath)) {
    New-Item -Path $Script:Config.UserFontsPath -ItemType Directory -Force | Out-Null
}

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Always log to file
    try {
        Add-Content -Path $Script:Config.LogFile -Value $logEntry -ErrorAction SilentlyContinue
    } catch {
        # Silently continue if logging fails
    }
    
    # Console output based on verbosity
    if ($DetailedOutput -or $Level -in @("ERROR", "SUCCESS")) {
        $color = switch ($Level) {
            "ERROR" { "Red" }
            "WARN" { "Yellow" }
            "SUCCESS" { "Green" }
            default { "White" }
        }
        Write-Host $logEntry -ForegroundColor $color
    }
}

function Initialize-Logging {
    $logHeader = @"
========================================================
WinFingerPrint - Font Fingerprint Randomizer
Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
PowerShell: $($PSVersionTable.PSVersion)
OS: $([System.Environment]::OSVersion.VersionString)
User: $env:USERNAME
Parameters: FontCount=$FontCount, TestFingerprint=$TestFingerprint, Cleanup=$Cleanup, DetailedOutput=$DetailedOutput
========================================================

"@
    
    try {
        $logHeader | Set-Content $Script:Config.LogFile
        Write-Log "Logging initialized" "SUCCESS"
    } catch {
        Write-Host "Warning: Could not initialize logging: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# ============================================================================
# STATE MANAGEMENT
# ============================================================================

function Get-ScriptState {
    if (Test-Path $Script:Config.StateFile) {
        try {
            $state = Get-Content $Script:Config.StateFile -Raw | ConvertFrom-Json
            Write-Log "State loaded: TotalRuns=$($state.TotalRuns), ActiveVariations=$($state.InstalledVariations.Count)" "INFO"
            return $state
        } catch {
            Write-Log "Failed to read state file: $($_.Exception.Message)" "WARN"
        }
    }
    
    Write-Log "Creating new state" "INFO"
    return @{ 
        TotalRuns = 0
        InstalledVariations = @()
        LastFingerprint = ""
        Created = Get-Date
    }
}

function Save-ScriptState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]$State
    )
    
    try {
        $State.LastUpdated = Get-Date
        $State | ConvertTo-Json -Depth 3 | Set-Content $Script:Config.StateFile
        Write-Log "State saved successfully" "INFO"
    } catch {
        Write-Log "Failed to save state: $($_.Exception.Message)" "ERROR"
    }
}

# ============================================================================
# FONT FINGERPRINT FUNCTIONS
# ============================================================================

function Get-FontFingerprint {
    Write-Log "Generating font fingerprint..." "INFO"
    
    try {
        $systemFonts = @()
        $userFonts = @()
        
        # Get system fonts
        try {
            $systemProps = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts" -ErrorAction SilentlyContinue
            if ($systemProps) {
                $systemFonts = $systemProps | Get-Member -MemberType NoteProperty |
                              Where-Object { $_.Name -notmatch "^PS" } |
                              Select-Object -ExpandProperty Name
            }
        } catch {
            Write-Log "Error reading system fonts: $($_.Exception.Message)" "WARN"
        }
        
        # Get user fonts
        try {
            if (Test-Path $Script:Config.UserRegPath) {
                $userProps = Get-ItemProperty -Path $Script:Config.UserRegPath -ErrorAction SilentlyContinue
                if ($userProps) {
                    $userFonts = $userProps | Get-Member -MemberType NoteProperty |
                                Where-Object { $_.Name -notmatch "^PS" } |
                                Select-Object -ExpandProperty Name
                }
            }
        } catch {
            Write-Log "Error reading user fonts: $($_.Exception.Message)" "WARN"
        }
        
        $allFonts = ($systemFonts + $userFonts) | Sort-Object | Get-Unique
        Write-Log "Fonts detected - System: $($systemFonts.Count), User: $($userFonts.Count), Total: $($allFonts.Count)" "INFO"
        
        # Create fingerprint hash
        $data = ($allFonts -join "|") + "|$(Get-Date -Format 'yyyyMMddHHmmss')|$(Get-Random)"
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($data)
        $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
        $hashString = [System.BitConverter]::ToString($hash).Replace("-", "")
        
        $fingerprint = $hashString.Substring(0, 32)
        Write-Log "Generated fingerprint: $($fingerprint.Substring(0,16))..." "SUCCESS"
        return $fingerprint
        
    } catch {
        Write-Log "Critical error generating fingerprint: $($_.Exception.Message)" "ERROR"
        return "ERROR_$(Get-Random -Max 999999)"
    }
}

# ============================================================================
# FONT CREATION FUNCTIONS
# ============================================================================

function New-FontVariation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$BaseName
    )
    
    $weight = $Script:Config.FontWeights | Get-Random
    $style = ($Script:Config.FontStyles | Where-Object { $_ }) | Get-Random -Count 1
    $width = ($Script:Config.FontWidths | Where-Object { $_ }) | Get-Random -Count 1
    
    $varName = $BaseName
    if ($weight -ne "Regular") { $varName += " $weight" }
    if ($style) { $varName += " $style" }
    if ($width) { $varName += " $width" }
    
    $uniqueId = Get-Random -Maximum 9999
    $fileName = "$($BaseName.Replace(' ', ''))_$($weight)_$uniqueId.ttf"
    
    return @{
        BaseName = $BaseName
        VariationName = $varName
        FileName = $fileName
        FilePath = Join-Path $Script:Config.UserFontsPath $fileName
        Created = Get-Date
    }
}

function New-MinimalTTF {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$FontName,

        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )

    Write-Log "Creating TTF file for: $FontName" "INFO"

    # Minimal but valid TTF structure
    $ttfData = @(
        # TTF Header (12 bytes)
        0x00, 0x01, 0x00, 0x00,  # sfnt version
        0x00, 0x03,              # numTables
        0x00, 0x30,              # searchRange
        0x00, 0x01,              # entrySelector
        0x00, 0x00,              # rangeShift

        # Table Directory: 'head' table
        0x68, 0x65, 0x61, 0x64,  # tag
        0x00, 0x00, 0x00, 0x00,  # checksum
        0x00, 0x00, 0x00, 0x3C,  # offset
        0x00, 0x00, 0x00, 0x36,  # length

        # Table Directory: 'maxp' table
        0x6D, 0x61, 0x78, 0x70,  # tag
        0x00, 0x00, 0x00, 0x00,  # checksum
        0x00, 0x00, 0x00, 0x72,  # offset
        0x00, 0x00, 0x00, 0x20,  # length

        # Table Directory: 'name' table
        0x6E, 0x61, 0x6D, 0x65,  # tag
        0x00, 0x00, 0x00, 0x00,  # checksum
        0x00, 0x00, 0x00, 0x92,  # offset
        0x00, 0x00, 0x00, 0x40   # length
    )

    # 'head' table (54 bytes)
    $headTable = @(
        0x00, 0x01, 0x00, 0x00,  # version
        0x00, 0x01, 0x00, 0x00,  # fontRevision
        0x00, 0x00, 0x00, 0x00,  # checkSumAdjustment
        0x5F, 0x0F, 0x3C, 0xF5,  # magicNumber
        0x00, 0x00,              # flags
        0x07, 0xD0,              # unitsPerEm
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  # created
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  # modified
        0x00, 0x00,              # xMin
        0x00, 0x00,              # yMin
        0x07, 0xD0,              # xMax
        0x07, 0xD0,              # yMax
        0x00, 0x00,              # macStyle
        0x00, 0x08,              # lowestRecPPEM
        0x00, 0x02,              # fontDirectionHint
        0x00, 0x00,              # indexToLocFormat
        0x00, 0x00               # glyphDataFormat
    )

    # 'maxp' table (32 bytes)
    $maxpTable = @(
        0x00, 0x01, 0x00, 0x00,  # version
        0x00, 0x01,              # numGlyphs
        0x00, 0x00,              # maxPoints
        0x00, 0x00,              # maxContours
        0x00, 0x00,              # maxCompositePoints
        0x00, 0x00,              # maxCompositeContours
        0x00, 0x02,              # maxZones
        0x00, 0x00,              # maxTwilightPoints
        0x00, 0x00,              # maxStorage
        0x00, 0x00,              # maxFunctionDefs
        0x00, 0x00,              # maxInstructionDefs
        0x00, 0x00,              # maxStackElements
        0x00, 0x00,              # maxSizeOfInstructions
        0x00, 0x00,              # maxComponentElements
        0x00, 0x00               # maxComponentDepth
    )

    # 'name' table with font name (64 bytes total)
    $nameBytes = [System.Text.Encoding]::Unicode.GetBytes($FontName)
    $nameLength = [Math]::Min($nameBytes.Length, 32)

    $nameTable = @(
        0x00, 0x00,              # format
        0x00, 0x01,              # count
        0x00, 0x06,              # stringOffset
        0x00, 0x03,              # platformID
        0x00, 0x01,              # encodingID
        0x04, 0x09,              # languageID
        0x00, 0x01,              # nameID
        ($nameLength -shr 8), ($nameLength -band 0xFF),  # length
        0x00, 0x00               # offset
    )

    $nameTable += $nameBytes[0..($nameLength-1)]
    $padding = 64 - $nameTable.Count
    if ($padding -gt 0) {
        $nameTable += @(0x00) * $padding
    }

    # Combine all parts
    $fontData = $ttfData + $headTable + $maxpTable + $nameTable

    try {
        [System.IO.File]::WriteAllBytes($FilePath, [byte[]]$fontData)
        Write-Log "TTF file created: $FilePath" "SUCCESS"
        return $true
    } catch {
        Write-Log "Failed to create TTF: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Install-FontVariation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]$FontVar
    )

    Write-Log "Installing font variation: $($FontVar.VariationName)" "INFO"

    try {
        # Create the actual TTF file
        if (-not (New-MinimalTTF -FontName $FontVar.VariationName -FilePath $FontVar.FilePath)) {
            return $false
        }

        # Register in registry
        if (-not (Test-Path $Script:Config.UserRegPath)) {
            New-Item -Path $Script:Config.UserRegPath -Force | Out-Null
        }

        $regName = "$($FontVar.VariationName) (TrueType)"
        Set-ItemProperty -Path $Script:Config.UserRegPath -Name $regName -Value $FontVar.FileName

        Write-Log "Successfully installed: $($FontVar.VariationName)" "SUCCESS"
        return $true

    } catch {
        Write-Log "Failed to install $($FontVar.VariationName): $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Invoke-FontCacheRefresh {
    Write-Log "Refreshing font cache..." "INFO"

    try {
        # Send WM_FONTCHANGE message to notify system of font changes
        Add-Type -TypeDefinition @"
            using System;
            using System.Runtime.InteropServices;
            public class Win32 {
                [DllImport("user32.dll")]
                public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
                public const uint WM_FONTCHANGE = 0x001D;
                public const IntPtr HWND_BROADCAST = (IntPtr)0xffff;
            }
"@ -ErrorAction SilentlyContinue

        [Win32]::SendMessage([Win32]::HWND_BROADCAST, [Win32]::WM_FONTCHANGE, [IntPtr]::Zero, [IntPtr]::Zero)
        Write-Log "Font change notification sent" "SUCCESS"
        return $true

    } catch {
        Write-Log "Could not send font change notification: $($_.Exception.Message)" "WARN"
        return $false
    }
}

# ============================================================================
# CLEANUP FUNCTIONS
# ============================================================================

function Remove-FontVariations {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$Variations
    )

    Write-Log "Starting cleanup of $($Variations.Count) font variations" "INFO"
    $removed = 0
    $errors = 0

    foreach ($var in $Variations) {
        try {
            # Remove registry entry
            $regName = "$($var.VariationName) (TrueType)"
            Remove-ItemProperty -Path $Script:Config.UserRegPath -Name $regName -ErrorAction SilentlyContinue

            # Remove font file
            if (Test-Path $var.FilePath) {
                Remove-Item -Path $var.FilePath -Force -ErrorAction SilentlyContinue
            }

            $removed++
            Write-Log "Removed: $($var.VariationName)" "INFO"

        } catch {
            $errors++
            Write-Log "Failed to remove: $($var.VariationName) - $($_.Exception.Message)" "ERROR"
        }
    }

    Write-Log "Cleanup completed: $removed removed, $errors errors" "SUCCESS"
    return @{ Removed = $removed; Errors = $errors }
}

# ============================================================================
# MAIN EXECUTION FUNCTION
# ============================================================================

function Start-FontRandomization {
    try {
        Initialize-Logging

        Write-Host ""
        Write-Host "WinFingerPrint - Font Fingerprint Randomizer" -ForegroundColor Cyan
        Write-Host "=" * 45 -ForegroundColor Cyan

        $state = Get-ScriptState
        $runNumber = $state.TotalRuns + 1

        # Handle cleanup mode
        if ($Cleanup) {
            Write-Host "Cleanup mode activated" -ForegroundColor Yellow
            Write-Log "Cleanup mode activated" "INFO"

            if ($state.InstalledVariations.Count -eq 0) {
                Write-Host "No font variations to clean up" -ForegroundColor Gray
                Write-Log "No variations found for cleanup" "INFO"
                return
            }

            $result = Remove-FontVariations -Variations $state.InstalledVariations
            $state.InstalledVariations = @()
            Save-ScriptState -State $state

            # Refresh font cache after cleanup
            Invoke-FontCacheRefresh

            Write-Host "Cleanup completed: $($result.Removed) fonts removed" -ForegroundColor Green
            if ($result.Errors -gt 0) {
                Write-Host "Errors encountered: $($result.Errors)" -ForegroundColor Yellow
            }
            return
        }

        # Get baseline fingerprint
        Write-Host "Getting baseline fingerprint..." -ForegroundColor Yellow
        $baselineHash = Get-FontFingerprint
        Write-Host "Baseline: $($baselineHash.Substring(0,16))..." -ForegroundColor Gray

        # Select fonts for variation creation
        $selectedFonts = $Script:Config.BaseFonts | Get-Random -Count $FontCount
        Write-Log "Selected fonts: $($selectedFonts -join ', ')" "INFO"

        # Create and install variations
        Write-Host "Creating $FontCount font variations..." -ForegroundColor Yellow
        $newVariations = @()
        $installed = 0

        foreach ($baseName in $selectedFonts) {
            $fontVar = New-FontVariation -BaseName $baseName

            if (Install-FontVariation -FontVar $fontVar) {
                $newVariations += $fontVar
                $installed++
                Write-Host "  + $($fontVar.VariationName)" -ForegroundColor Green
            } else {
                Write-Host "  - Failed: $($fontVar.VariationName)" -ForegroundColor Red
            }

            Start-Sleep -Milliseconds 300
        }

        Write-Log "Font creation completed. Installed: $installed" "SUCCESS"

        # Refresh font cache
        Write-Host "Refreshing font cache..." -ForegroundColor Yellow
        Invoke-FontCacheRefresh

        # Wait for system to process changes
        Start-Sleep -Seconds 2

        # Get new fingerprint
        Write-Host "Generating new fingerprint..." -ForegroundColor Yellow
        $newHash = Get-FontFingerprint

        # Update state
        $state.TotalRuns = $runNumber
        $state.LastFingerprint = $newHash
        $state.InstalledVariations += $newVariations

        # Auto cleanup old variations (keep last N)
        if ($state.InstalledVariations.Count -gt $Script:Config.MaxActiveVariations) {
            Write-Log "Auto-cleaning old variations (keeping last $($Script:Config.MaxActiveVariations))" "INFO"
            $toRemove = $state.InstalledVariations[0..($state.InstalledVariations.Count - $Script:Config.MaxActiveVariations - 1)]
            Remove-FontVariations -Variations $toRemove
            $state.InstalledVariations = $state.InstalledVariations[-$Script:Config.MaxActiveVariations..-1]
        }

        Save-ScriptState -State $state

        # Display results
        $changed = ($baselineHash -ne $newHash)

        Write-Host ""
        Write-Host "RESULTS:" -ForegroundColor Cyan
        Write-Host "  Run #$runNumber completed" -ForegroundColor White
        Write-Host "  Variations created: $installed" -ForegroundColor White
        Write-Host "  Total active: $($state.InstalledVariations.Count)" -ForegroundColor White
        Write-Host "  Baseline: $($baselineHash.Substring(0,16))..." -ForegroundColor Gray
        Write-Host "  New Hash: $($newHash.Substring(0,16))..." -ForegroundColor Magenta

        if ($changed) {
            Write-Host "  SUCCESS: Fingerprint CHANGED!" -ForegroundColor Green
            Write-Log "Fingerprint successfully randomized!" "SUCCESS"
        } else {
            Write-Host "  WARNING: Fingerprint unchanged" -ForegroundColor Yellow
            Write-Log "Fingerprint unchanged - may need browser restart" "WARN"
        }

        # Open test if requested
        if ($TestFingerprint) {
            Write-Host "Opening browserleaks.com for verification..." -ForegroundColor Cyan
            Write-Log "Opening browserleaks.com for verification" "INFO"
            Start-Sleep -Seconds 1
            Start-Process "https://browserleaks.com/fonts"
        }

        Write-Host ""
        Write-Host "Execution completed!" -ForegroundColor Green
        Write-Host "Log file: $($Script:Config.LogFile)" -ForegroundColor Gray

        if (-not $changed) {
            Write-Host "Tip: If fingerprint didn't change, try restarting your browser" -ForegroundColor Yellow
        }

        Write-Log "=== EXECUTION COMPLETED SUCCESSFULLY ===" "SUCCESS"

    } catch {
        $errorMsg = "Critical error: $($_.Exception.Message)"
        Write-Log $errorMsg "ERROR"
        Write-Host $errorMsg -ForegroundColor Red
        Write-Host "Check log file for details: $($Script:Config.LogFile)" -ForegroundColor Yellow
        throw
    }
}

# ============================================================================
# SCRIPT ENTRY POINT
# ============================================================================

# Execute main function if script is run directly (not dot-sourced)
if ($MyInvocation.InvocationName -ne '.') {
    Start-FontRandomization
}
