# Data Recovery Tools Auto Installer

$LogFile = "$PSScriptRoot\log_recovery_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

function Log {
    param([string]$msg, [string]$color = "Cyan")
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $msg"
    Write-Host $line -ForegroundColor $color
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

function Section {
    param([string]$title)
    Write-Host ""
    Write-Host ("=" * 55) -ForegroundColor Yellow
    Write-Host "  $title" -ForegroundColor Yellow
    Write-Host ("=" * 55) -ForegroundColor Yellow
    Write-Host ""
}

function Download {
    param([string]$url, [string]$out, [string]$name)
    Log "  Downloading $name..." "Cyan"
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent","Mozilla/5.0")
        $wc.DownloadFile($url, $out)
        Log "  Downloaded: $name" "Green"
        return $true
    } catch {
        Log "  Failed: $name - $($_.Exception.Message)" "Red"
        return $false
    }
}

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Clear-Host
Write-Host ("=" * 55) -ForegroundColor Cyan
Write-Host "   Data Recovery Tools Installer" -ForegroundColor Cyan
Write-Host ("=" * 55) -ForegroundColor Cyan
Log "Start - PC: $env:COMPUTERNAME" "Green"

$toolsDir = "$PSScriptRoot\recovery_tools"
if (-not (Test-Path $toolsDir)) { New-Item -Path $toolsDir -ItemType Directory | Out-Null }

# Step 1: Recuva
Section "1/3  Recuva (Deleted File Recovery)"
$wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
if ($wingetCmd) {
    Log "Installing Recuva via winget..." "Cyan"
    winget install Piriform.Recuva --silent --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
    Log "Recuva installed" "Green"
} else {
    $recuvaPath = "$toolsDir\recuva_setup.exe"
    $ok = Download "https://www.ccleaner.com/recuva/download/standard" $recuvaPath "Recuva"
    if ($ok) {
        Log "  Recuva installer saved: $recuvaPath" "Green"
        Log "  Run manually to install" "Yellow"
    }
}

# Step 2: CrystalDiskInfo
Section "2/3  CrystalDiskInfo (Disk Health)"
if ($wingetCmd) {
    Log "Installing CrystalDiskInfo via winget..." "Cyan"
    winget install CrystalDewWorld.CrystalDiskInfo --silent --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
    Log "CrystalDiskInfo installed" "Green"
} else {
    Log "winget not found - visit https://crystalmark.info to install manually" "Yellow"
}

# Step 3: Usage guide
Section "3/3  Usage Guide"
Log "Recuva:" "Cyan"
Log "  1. Run Recuva" "Gray"
Log "  2. Select file type (photos/docs etc)" "Gray"
Log "  3. Select scan location (full C: drive recommended)" "Gray"
Log "  4. Scan then select files to recover" "Gray"
Log "  5. Save to a DIFFERENT drive (not same drive)" "Gray"
Write-Host ""
Log "CrystalDiskInfo:" "Cyan"
Log "  Blue=Good  Yellow=Caution  Red=Bad (replace immediately)" "Gray"

Write-Host ""
Write-Host ("=" * 55) -ForegroundColor Green
Write-Host "  Recovery tools install complete" -ForegroundColor Green
Write-Host ("=" * 55) -ForegroundColor Green
Log "Done. Log: $LogFile" "Green"
Read-Host "Press Enter to close"
