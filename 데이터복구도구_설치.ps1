# Data Recovery Tool - Install + Diagnose + Auto Recover

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

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Clear-Host
Write-Host ("=" * 55) -ForegroundColor Cyan
Write-Host "   Data Recovery Tool" -ForegroundColor Cyan
Write-Host ("=" * 55) -ForegroundColor Cyan
Log "Start - PC: $env:COMPUTERNAME" "Green"

# ─── STEP 1: Disk S.M.A.R.T Health Check ───────────────────
Section "1/5  Disk Health (S.M.A.R.T)"
Log "Checking disk health..." "Cyan"
$diskWarning = $false
try {
    $physDisks = Get-PhysicalDisk -ErrorAction Stop
    foreach ($pd in $physDisks) {
        $health = $pd.HealthStatus
        $media  = $pd.MediaType
        $size   = [math]::Round($pd.Size / 1GB, 0)
        $color  = switch ($health) {
            "Healthy"  { "Green"  }
            "Warning"  { "Yellow" }
            "Unhealthy"{ "Red"    }
            default    { "Gray"   }
        }
        Log "  Disk: $($pd.FriendlyName) | $media | $size GB | $health" $color
        if ($health -ne "Healthy") { $diskWarning = $true }
    }
} catch {
    # Fallback: WMI SMART
    try {
        $smartData = Get-WmiObject -Namespace root\wmi -Class MSStorageDriver_FailurePredictStatus -ErrorAction Stop
        foreach ($s in $smartData) {
            if ($s.PredictFailure) {
                Log "  WARNING: Disk failure predicted - backup immediately!" "Red"
                $diskWarning = $true
            } else {
                Log "  SMART: No failure predicted" "Green"
            }
        }
    } catch {
        Log "  SMART check not available on this system" "DarkGray"
    }
}

if ($diskWarning) {
    Write-Host ""
    Write-Host "  !! DISK WARNING: Back up data before recovery !!" -ForegroundColor Red
    Write-Host ""
    $cont = Read-Host "  Continue anyway? (Y/N)"
    if ($cont -ne "Y" -and $cont -ne "y") { exit }
}
Log "Disk check done" "Green"

# ─── STEP 2: Recovery Feasibility Diagnosis ─────────────────
Section "2/5  Recovery Feasibility Check"
Log "Analyzing drives for recovery potential..." "Cyan"

$drives = Get-WmiObject Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 }
foreach ($d in $drives) {
    $freePct = if ($d.Size -gt 0) { [math]::Round($d.FreeSpace / $d.Size * 100, 0) } else { 0 }
    $freeGB  = [math]::Round($d.FreeSpace / 1GB, 1)
    $totalGB = [math]::Round($d.Size / 1GB, 1)

    # More free space = less overwriting = better recovery chance
    $chance = if ($freePct -gt 50) { "Good" }
              elseif ($freePct -gt 20) { "Fair" }
              else { "Low" }
    $chColor = if ($chance -eq "Good") { "Green" } elseif ($chance -eq "Fair") { "Yellow" } else { "Red" }

    Log "  Drive $($d.DeviceID)  $freeGB GB free / $totalGB GB  ($freePct% free)  Recovery chance: $chance" $chColor
}
Log "Feasibility check done" "Green"

# ─── STEP 3: Install Recuva + CrystalDiskInfo ───────────────
Section "3/5  Install Recovery Tools"
$recuvaExe = $null

# Check if Recuva already installed
$recuvaPaths = @(
    "$env:ProgramFiles\Recuva\Recuva.exe",
    "${env:ProgramFiles(x86)}\Recuva\Recuva.exe"
)
foreach ($rp in $recuvaPaths) {
    if (Test-Path $rp) { $recuvaExe = $rp; break }
}

if ($recuvaExe) {
    Log "  Recuva already installed: $recuvaExe" "Green"
} else {
    $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($wingetCmd) {
        Log "  Installing Recuva via winget..." "Cyan"
        winget install Piriform.Recuva --silent --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
        foreach ($rp in $recuvaPaths) {
            if (Test-Path $rp) { $recuvaExe = $rp; break }
        }
        if ($recuvaExe) { Log "  Recuva installed: $recuvaExe" "Green" }
        else { Log "  Recuva install may need reboot to detect path" "Yellow" }
    } else {
        # Direct download portable
        $toolsDir = "$PSScriptRoot\recovery_tools"
        if (-not (Test-Path $toolsDir)) { New-Item -Path $toolsDir -ItemType Directory | Out-Null }
        $recuvaSetup = "$toolsDir\recuva_setup.exe"
        Log "  Downloading Recuva installer..." "Cyan"
        try {
            $wc = New-Object System.Net.WebClient
            $wc.Headers.Add("User-Agent","Mozilla/5.0")
            $wc.DownloadFile("https://www.ccleaner.com/recuva/download/standard", $recuvaSetup)
            Log "  Saved: $recuvaSetup" "Green"
            Log "  Run the installer manually, then re-run this script" "Yellow"
        } catch {
            Log "  Download failed: $($_.Exception.Message)" "Red"
        }
    }
}

# CrystalDiskInfo
$cdiPaths = @(
    "$env:ProgramFiles\CrystalDiskInfo\DiskInfo64.exe",
    "$env:ProgramFiles\CrystalDiskInfo\DiskInfo32.exe",
    "${env:ProgramFiles(x86)}\CrystalDiskInfo\DiskInfo32.exe"
)
$cdiInstalled = $cdiPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($cdiInstalled) {
    Log "  CrystalDiskInfo already installed" "Green"
} else {
    $wingetCmd2 = Get-Command winget -ErrorAction SilentlyContinue
    if ($wingetCmd2) {
        Log "  Installing CrystalDiskInfo via winget..." "Cyan"
        winget install CrystalDewWorld.CrystalDiskInfo --silent --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
        Log "  CrystalDiskInfo installed" "Green"
    } else {
        Log "  Visit https://crystalmark.info to install CrystalDiskInfo manually" "Yellow"
    }
}
Log "Tool install done" "Green"

# ─── STEP 4: Auto Scan + Recover via Recuva CLI ─────────────
Section "4/5  Auto File Recovery"

if (-not $recuvaExe) {
    Log "  Recuva not found - skipping auto recovery" "Yellow"
    Log "  Install Recuva and re-run, or use Recuva manually" "Yellow"
} else {
    # Ask which drive to scan
    Write-Host ""
    Write-Host "  Available drives:" -ForegroundColor Cyan
    $drives2 = Get-WmiObject Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 }
    $drives2 | ForEach-Object {
        $gb = [math]::Round($_.Size/1GB,0)
        Write-Host "    $($_.DeviceID)  ($gb GB)" -ForegroundColor Gray
    }
    $scanDrive = Read-Host "  Drive to scan (e.g. C)"
    $scanDrive = $scanDrive.TrimEnd(':').ToUpper()

    # Ask where to save recovered files
    Write-Host ""
    Write-Host "  Available drives for saving recovered files:" -ForegroundColor Cyan
    $drives2 | Where-Object { $_.DeviceID -notlike "$scanDrive*" } | ForEach-Object {
        Write-Host "    $($_.DeviceID)" -ForegroundColor Gray
    }
    $saveDrive = Read-Host "  Save recovered files to drive (e.g. D or E)"
    $saveDrive = $saveDrive.TrimEnd(':').ToUpper()
    $saveDir   = "${saveDrive}:\Recovered_$(Get-Date -Format 'yyyyMMdd_HHmm')"

    if (-not (Test-Path "${saveDrive}:\")) {
        Log "  Drive ${saveDrive}: not found - using Desktop instead" "Yellow"
        $saveDir = "$env:USERPROFILE\Desktop\Recovered_$(Get-Date -Format 'yyyyMMdd_HHmm')"
    }
    New-Item -Path $saveDir -ItemType Directory -Force | Out-Null

    # Recuva CLI: /scan /output saves a CSV of found files, /recover recovers them
    # Recuva CLI syntax: Recuva.exe /drive:C /output:list.csv /recover:D:\Recovered
    Log "  Scanning ${scanDrive}: for deleted files..." "Cyan"
    Log "  This may take several minutes..." "Gray"

    $csvPath = "$PSScriptRoot\recovery_scan_$(Get-Date -Format 'yyyyMMdd_HHmm').csv"

    # Run Recuva in silent mode with CSV output
    $recuvaArgs = "/drive:${scanDrive} /output:`"$csvPath`" /silent"
    try {
        $proc = Start-Process -FilePath $recuvaExe -ArgumentList $recuvaArgs -Wait -PassThru -NoNewWindow
        if (Test-Path $csvPath) {
            $found = (Import-Csv $csvPath -ErrorAction SilentlyContinue).Count
            Log "  Scan complete - $found recoverable files found" "Green"
            Log "  Scan results: $csvPath" "Gray"

            if ($found -gt 0) {
                $doRecover = Read-Host "  Recover all files to $saveDir ? (Y/N)"
                if ($doRecover -eq "Y" -or $doRecover -eq "y") {
                    $recoverArgs = "/drive:${scanDrive} /recover:`"$saveDir`" /silent"
                    Start-Process -FilePath $recuvaExe -ArgumentList $recoverArgs -Wait -NoNewWindow
                    $recoveredCount = (Get-ChildItem $saveDir -Recurse -File -ErrorAction SilentlyContinue).Count
                    Log "  Recovery complete - $recoveredCount files saved to $saveDir" "Green"
                }
            } else {
                Log "  No recoverable files found on ${scanDrive}:" "Yellow"
            }
        } else {
            Log "  Scan CSV not generated - Recuva CLI may not support this mode" "Yellow"
            Log "  Opening Recuva GUI for manual recovery..." "Cyan"
            Start-Process -FilePath $recuvaExe
        }
    } catch {
        Log "  Recuva error: $($_.Exception.Message)" "Red"
        Log "  Opening Recuva GUI for manual recovery..." "Cyan"
        Start-Process -FilePath $recuvaExe
    }
}
Log "Recovery step done" "Green"

# ─── STEP 5: Summary Report ─────────────────────────────────
Section "5/5  Summary"
Log "Disk health  : $(if($diskWarning){'WARNING - check disk'}else{'OK'})" $(if($diskWarning){"Red"}else{"Green"})
Log "Recuva       : $(if($recuvaExe){'Installed'}else{'Not found - install manually'})" $(if($recuvaExe){"Green"}else{"Yellow"})
Log "Log file     : $LogFile" "Gray"
Write-Host ""
Write-Host "  Tips:" -ForegroundColor Cyan
Write-Host "  - The sooner you recover, the better the success rate" -ForegroundColor Gray
Write-Host "  - Never save recovered files to the same drive you scanned" -ForegroundColor Gray
Write-Host "  - If disk shows WARNING, replace it after recovery" -ForegroundColor Gray
Write-Host ""
Write-Host ("=" * 55) -ForegroundColor Green
Write-Host "  Data Recovery Tool complete" -ForegroundColor Green
Write-Host ("=" * 55) -ForegroundColor Green

Read-Host "Press Enter to close"
