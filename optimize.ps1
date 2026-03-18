# PC Optimizer & Updater Script
# Windows 10/11 compatible

$LogFile = "$PSScriptRoot\log_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

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
Write-Host "   Windows PC Optimizer & Updater" -ForegroundColor Cyan
Write-Host ("=" * 55) -ForegroundColor Cyan
Log "Start - PC: $env:COMPUTERNAME" "Green"

# Step 1: Windows Update
Section "1/6  Windows Update"
if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
    Log "Installing PSWindowsUpdate module..." "Yellow"
    try {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers | Out-Null
        Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers -AllowClobber | Out-Null
        Log "PSWindowsUpdate installed OK" "Green"
    } catch {
        Log "PSWindowsUpdate install failed: $($_.Exception.Message)" "Red"
    }
}
try {
    Import-Module PSWindowsUpdate -ErrorAction Stop
    Log "Checking for Windows updates..." "Cyan"
    $updates = Get-WindowsUpdate -AcceptAll -IgnoreReboot -ErrorAction Stop
    if ($updates.Count -eq 0) {
        Log "Already up to date" "Green"
    } else {
        Log "Installing $($updates.Count) updates..." "Yellow"
        Install-WindowsUpdate -AcceptAll -IgnoreReboot -AutoReboot:$false | ForEach-Object {
            Log "  OK: $($_.Title)" "Gray"
        }
        Log "Windows Update done" "Green"
    }
} catch {
    Log "Fallback: triggering update via UsoClient..." "Yellow"
    Start-Process "UsoClient.exe" -ArgumentList "StartScan" -Wait -NoNewWindow
    Start-Process "UsoClient.exe" -ArgumentList "StartDownload" -Wait -NoNewWindow
    Start-Process "UsoClient.exe" -ArgumentList "StartInstall" -Wait -NoNewWindow
    Log "Windows Update triggered (runs in background)" "Green"
}

# Step 2: App updates via winget
Section "2/6  App Updates (winget)"
$wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
if ($wingetCmd) {
    Log "Updating all apps via winget..." "Cyan"
    winget upgrade --all --silent --accept-source-agreements --accept-package-agreements 2>&1 | ForEach-Object {
        Log "  $_" "Gray"
    }
    Log "App updates done" "Green"
} else {
    Log "winget not found - install App Installer from Microsoft Store" "Yellow"
}

# Step 3: Temp files cleanup
Section "3/6  Temp Files & Recycle Bin"
$cleanPaths = @(
    $env:TEMP,
    $env:TMP,
    "C:\Windows\Temp",
    "C:\Windows\Prefetch",
    "$env:LOCALAPPDATA\Microsoft\Windows\INetCache",
    "$env:LOCALAPPDATA\Temp"
)
$totalMB = 0
foreach ($p in $cleanPaths) {
    if (Test-Path $p) {
        try {
            $sz = (Get-ChildItem $p -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            if ($null -eq $sz) { $sz = 0 }
            Remove-Item "$p\*" -Recurse -Force -ErrorAction SilentlyContinue
            $mb = [math]::Round($sz / 1MB, 1)
            $totalMB += $mb
            Log "  Cleaned: $p ($mb MB)" "Gray"
        } catch {
            Log "  Skipped: $p" "DarkGray"
        }
    }
}
try {
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    Log "Recycle Bin emptied" "Gray"
} catch {
    Log "Recycle Bin skip" "DarkGray"
}
Log "Cleanup done - freed ~$totalMB MB" "Green"

# Step 4: Disk Cleanup
Section "4/6  Disk Cleanup (cleanmgr)"
Log "Running disk cleanup..." "Cyan"
$regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
Get-ChildItem $regPath | ForEach-Object {
    Set-ItemProperty -Path $_.PSPath -Name "StateFlags65535" -Value 2 -Type DWORD -ErrorAction SilentlyContinue
}
Start-Process "cleanmgr.exe" -ArgumentList "/sagerun:65535" -Wait -NoNewWindow
Log "Disk cleanup done" "Green"

# Step 5: System file repair + Boot repair
Section "5/6  System File Repair + Boot Fix (SFC / DISM / BCD)"
Log "Running SFC scan (may take a few minutes)..." "Cyan"
sfc /scannow 2>&1 | Select-String "Windows Resource Protection" | ForEach-Object {
    Log "  $_" "Gray"
}
Log "SFC done" "Green"

Log "Running DISM repair..." "Cyan"
DISM /Online /Cleanup-Image /RestoreHealth 2>&1 | Select-String "(Error|complete|percent)" | ForEach-Object {
    Log "  $_" "Gray"
}
Log "DISM done" "Green"

Log "Repairing BCD boot record..." "Cyan"
try {
    # Rebuild BCD store (fixes most boot errors)
    bcdedit /export "$env:TEMP\bcd_backup" | Out-Null
    Log "  BCD backup saved to $env:TEMP\bcd_backup" "Gray"
    bootrec /fixmbr 2>&1 | ForEach-Object { Log "  fixmbr: $_" "Gray" }
    bootrec /fixboot 2>&1 | ForEach-Object { Log "  fixboot: $_" "Gray" }
    bootrec /scanos 2>&1 | ForEach-Object { Log "  scanos: $_" "Gray" }
    bootrec /rebuildbcd 2>&1 | ForEach-Object { Log "  rebuildbcd: $_" "Gray" }
    Log "BCD repair done" "Green"
} catch {
    Log "BCD repair error: $($_.Exception.Message)" "Red"
}

Log "Checking for problematic drivers..." "Cyan"
try {
    # Find unsigned / failed drivers
    $badDrivers = Get-WmiObject Win32_PnPSignedDriver |
        Where-Object { $_.IsSigned -eq $false -or $_.DeviceID -like "*UNKNOWN*" } |
        Select-Object DeviceName, DriverVersion, IsSigned
    if ($badDrivers) {
        Log "  WARNING - Unsigned/unknown drivers found:" "Yellow"
        $badDrivers | ForEach-Object { Log "    - $($_.DeviceName) (signed: $($_.IsSigned))" "Yellow" }
    } else {
        Log "  All drivers OK" "Gray"
    }

    # Find devices with errors in Device Manager
    $errorDevices = Get-WmiObject Win32_PnPEntity |
        Where-Object { $_.ConfigManagerErrorCode -ne 0 } |
        Select-Object Name, ConfigManagerErrorCode
    if ($errorDevices) {
        Log "  WARNING - Devices with errors:" "Yellow"
        $errorDevices | ForEach-Object { Log "    - $($_.Name) (error code: $($_.ConfigManagerErrorCode))" "Yellow" }
    } else {
        Log "  No device errors found" "Gray"
    }
} catch {
    Log "Driver check error: $($_.Exception.Message)" "Red"
}
Log "Boot & driver check done" "Green"

# Step 6: Network reset
Section "6/6  Network Cache Reset"
Log "Flushing DNS cache..." "Cyan"
ipconfig /flushdns | Out-Null
Log "DNS flushed" "Green"
Log "Resetting network stack..." "Cyan"
netsh winsock reset | Out-Null
netsh int ip reset | Out-Null
Log "Network reset done (reboot required)" "Green"

# Step 7: Performance Optimization
Section "7/9  Startup Programs (Boot Speed)"
Log "Disabling unnecessary startup entries..." "Cyan"

# Registry startup entries to disable (common bloat)
$startupKeys = @(
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"
)
$keepStartup = @(
    "SecurityHealth", "WindowsDefender", "OneDrive", "Teams",
    "Realtek", "NVIDIA", "AMD", "Intel", "ctfmon"
)
foreach ($key in $startupKeys) {
    if (Test-Path $key) {
        $entries = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
        $entries.PSObject.Properties | Where-Object {
            $_.Name -notlike "PS*" -and $keepStartup -notcontains $_.Name
        } | ForEach-Object {
            $name = $_.Name
            # Only disable known bloat, not unknown entries (safety)
            $bloat = @("Spotify", "Discord", "Steam", "EpicGamesLauncher",
                       "AdobeGCInvoker", "iTunesHelper", "GoogleUpdate",
                       "CCleaner", "Skype", "Zoom", "KakaoTalk", "LINE",
                       "BaiduIME", "WeChatApp", "DropboxUpdate", "GoogleDriveFS")
            if ($bloat -contains $name) {
                Remove-ItemProperty -Path $key -Name $name -ErrorAction SilentlyContinue
                Log "  Removed startup: $name" "Gray"
            }
        }
    }
}

# Disable startup delay
$delayKey = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Serialize"
if (-not (Test-Path $delayKey)) { New-Item -Path $delayKey -Force | Out-Null }
Set-ItemProperty -Path $delayKey -Name "StartupDelayInMSec" -Value 0 -Type DWORD
Log "Startup delay removed" "Gray"
Log "Startup optimization done" "Green"

# Step 8: Disable Unnecessary Services
Section "8/9  Background Services Optimization"
Log "Disabling unnecessary background services..." "Cyan"

$servicesToDisable = @(
    @{Name="DiagTrack";       Desc="Telemetry/Diagnostics tracking"},
    @{Name="dmwappushservice";Desc="WAP Push Message Routing"},
    @{Name="SysMain";         Desc="Superfetch (disable if SSD)"},
    @{Name="WSearch";         Desc="Windows Search indexing"},
    @{Name="Fax";             Desc="Fax service"},
    @{Name="XblAuthManager";  Desc="Xbox Live Auth"},
    @{Name="XblGameSave";     Desc="Xbox Live Game Save"},
    @{Name="XboxNetApiSvc";   Desc="Xbox Network"},
    @{Name="MapsBroker";      Desc="Downloaded Maps Manager"},
    @{Name="RetailDemo";      Desc="Retail Demo service"},
    @{Name="RemoteRegistry";  Desc="Remote Registry (security risk)"}
)

# Check if drive is SSD
$isSSD = $false
try {
    $disk = Get-PhysicalDisk | Where-Object { $_.MediaType -eq "SSD" }
    if ($disk) { $isSSD = $true }
} catch {}

foreach ($svc in $servicesToDisable) {
    # Keep SysMain (Superfetch) on HDD - only disable on SSD
    if ($svc.Name -eq "SysMain" -and -not $isSSD) {
        Log "  Kept SysMain (HDD detected - Superfetch helps)" "DarkGray"
        continue
    }
    $s = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
    if ($s -and $s.StartType -ne "Disabled") {
        try {
            Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
            Set-Service -Name $svc.Name -StartupType Disabled -ErrorAction SilentlyContinue
            Log "  Disabled: $($svc.Name) - $($svc.Desc)" "Gray"
        } catch {
            Log "  Skip: $($svc.Name)" "DarkGray"
        }
    }
}
Log "Service optimization done" "Green"

# Step 9: Visual & Power Performance
Section "9/9  Visual Effects & Power Plan"
Log "Setting visual effects to performance mode..." "Cyan"

# Visual effects - performance mode
$perfKey = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
if (-not (Test-Path $perfKey)) { New-Item -Path $perfKey -Force | Out-Null }
Set-ItemProperty -Path $perfKey -Name "VisualFXSetting" -Value 2 -Type DWORD

# Disable specific animations
$advKey = "HKCU:\Control Panel\Desktop"
Set-ItemProperty -Path $advKey -Name "UserPreferencesMask" -Value ([byte[]](0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00)) -Type Binary -ErrorAction SilentlyContinue
Set-ItemProperty -Path $advKey -Name "MenuShowDelay" -Value "0" -ErrorAction SilentlyContinue

$windowKey = "HKCU:\Control Panel\Desktop\WindowMetrics"
Set-ItemProperty -Path $windowKey -Name "MinAnimate" -Value "0" -ErrorAction SilentlyContinue

Log "Visual effects set to performance" "Gray"

# Power plan - High Performance
Log "Setting power plan to High Performance..." "Cyan"
$hp = powercfg /list 2>&1 | Select-String "High performance"
if ($hp) {
    $guid = ($hp -split "\s+")[3]
    powercfg /setactive $guid | Out-Null
    Log "Power plan: High Performance activated" "Gray"
} else {
    powercfg /setactive SCHEME_MIN | Out-Null
    Log "Power plan: High Performance activated" "Gray"
}

# Disable hibernation (frees disk space, faster shutdown)
powercfg /hibernate off | Out-Null
Log "Hibernation disabled (disk space freed)" "Gray"

# Disable transparency effects
$personKey = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize"
Set-ItemProperty -Path $personKey -Name "EnableTransparency" -Value 0 -Type DWORD -ErrorAction SilentlyContinue
Log "Transparency effects disabled" "Gray"

# Disable background apps
$bgKey = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"
Set-ItemProperty -Path $bgKey -Name "GlobalUserDisabled" -Value 1 -Type DWORD -ErrorAction SilentlyContinue
Log "Background apps disabled" "Gray"

Log "Performance optimization done" "Green"

# Done
Write-Host ""
Write-Host ("=" * 55) -ForegroundColor Green
Write-Host "  All tasks completed! (9 steps)" -ForegroundColor Green
Write-Host ("=" * 55) -ForegroundColor Green
Log "All done. Log: $LogFile" "Green"

Write-Host ""
Write-Host "Reboot required to apply all changes." -ForegroundColor Yellow
$ans = Read-Host "Reboot now? (Y/N)"
if ($ans -eq "Y" -or $ans -eq "y") {
    Log "Rebooting..." "Yellow"
    Restart-Computer -Force
} else {
    Log "Reboot skipped" "Gray"
    Write-Host "Log file: $LogFile" -ForegroundColor Cyan
    Read-Host "Press Enter to close"
}
