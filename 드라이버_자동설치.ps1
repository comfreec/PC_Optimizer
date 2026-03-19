# Driver Auto Installer (Post Windows Reinstall)

$LogFile = "$PSScriptRoot\log_driver_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

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
Write-Host "   Driver Auto Installer" -ForegroundColor Cyan
Write-Host ("=" * 55) -ForegroundColor Cyan
Log "Start - PC: $env:COMPUTERNAME" "Green"

# Step 1: Check missing drivers
Section "1/4  Missing Driver Check"
Log "Scanning for missing drivers..." "Cyan"
$missingDrivers = Get-WmiObject Win32_PnPEntity |
    Where-Object { $_.ConfigManagerErrorCode -ne 0 } |
    Select-Object Name, ConfigManagerErrorCode, DeviceID
if ($missingDrivers) {
    Log "  Devices with missing drivers:" "Yellow"
    $missingDrivers | ForEach-Object {
        Log "    - $($_.Name) (code: $($_.ConfigManagerErrorCode))" "Yellow"
    }
} else {
    Log "  All drivers OK" "Green"
}

# Step 2: Windows Update drivers
Section "2/4  Windows Update Driver Install"
Log "Triggering Windows Update for drivers..." "Cyan"
try {
    if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers | Out-Null
        Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers -AllowClobber | Out-Null
    }
    Import-Module PSWindowsUpdate -ErrorAction Stop
    $driverUpdates = Get-WindowsUpdate -Category "Drivers" -AcceptAll -IgnoreReboot -ErrorAction Stop
    if ($driverUpdates.Count -gt 0) {
        Log "  Installing $($driverUpdates.Count) driver updates..." "Yellow"
        Install-WindowsUpdate -Category "Drivers" -AcceptAll -IgnoreReboot -AutoReboot:$false | ForEach-Object {
            Log "    OK: $($_.Title)" "Gray"
        }
        Log "  Driver updates complete" "Green"
    } else {
        Log "  No additional driver updates" "Green"
    }
} catch {
    Log "  PSWindowsUpdate failed - using UsoClient..." "Yellow"
    Start-Process "UsoClient.exe" -ArgumentList "StartScan" -Wait -NoNewWindow
    Start-Process "UsoClient.exe" -ArgumentList "StartDownload" -Wait -NoNewWindow
    Start-Process "UsoClient.exe" -ArgumentList "StartInstall" -Wait -NoNewWindow
    Log "  Driver update triggered via UsoClient" "Green"
}

# Step 3: Manufacturer info
Section "3/4  PC Manufacturer Info"
Log "Checking manufacturer info..." "Cyan"
try {
    $cs = Get-WmiObject Win32_ComputerSystem
    $mb = Get-WmiObject Win32_BaseBoard
    Log "  Manufacturer: $($cs.Manufacturer)" "Gray"
    Log "  Model: $($cs.Model)" "Gray"
    Log "  Motherboard: $($mb.Manufacturer) $($mb.Product)" "Gray"
    Write-Host ""
    Log "  Manual driver download sites:" "Cyan"
    $mfr = $cs.Manufacturer.ToLower()
    if ($mfr -like "*samsung*")     { Log "  https://www.samsung.com/sec/support/download" "Gray" }
    elseif ($mfr -like "*lg*")      { Log "  https://www.lge.co.kr/support/software-firmware" "Gray" }
    elseif ($mfr -like "*dell*")    { Log "  https://www.dell.com/support/home" "Gray" }
    elseif ($mfr -like "*hp*")      { Log "  https://support.hp.com/drivers" "Gray" }
    elseif ($mfr -like "*lenovo*")  { Log "  https://support.lenovo.com" "Gray" }
    elseif ($mfr -like "*asus*")    { Log "  https://www.asus.com/support" "Gray" }
    elseif ($mfr -like "*acer*")    { Log "  https://www.acer.com/support" "Gray" }
    elseif ($mfr -like "*msi*")     { Log "  https://www.msi.com/support" "Gray" }
    else { Log "  Search by model: $($cs.Model)" "Gray" }
} catch {
    Log "  Manufacturer info check failed" "Red"
}

# Step 4: Re-check
Section "4/4  Final Driver Check"
$remaining = Get-WmiObject Win32_PnPEntity |
    Where-Object { $_.ConfigManagerErrorCode -ne 0 } |
    Select-Object Name
if ($remaining) {
    Log "  Still missing drivers:" "Yellow"
    $remaining | ForEach-Object { Log "    - $($_.Name)" "Yellow" }
    Log "  Install manually from manufacturer site" "Yellow"
} else {
    Log "  All drivers installed successfully" "Green"
}

Write-Host ""
Write-Host ("=" * 55) -ForegroundColor Green
Write-Host "  Driver install complete" -ForegroundColor Green
Write-Host ("=" * 55) -ForegroundColor Green
Log "Done. Log: $LogFile" "Green"

$ans = Read-Host "Reboot now? (Y/N)"
if ($ans -eq "Y" -or $ans -eq "y") {
    Restart-Computer -Force
} else {
    Read-Host "Press Enter to close"
}
