# Updater - 업데이트 + 정리 전용 (20분~1시간)

$LogFile = "$PSScriptRoot\log_update_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

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
Write-Host "   Windows 최신 상태로 업데이트 (20분~1시간)" -ForegroundColor Cyan
Write-Host ("=" * 55) -ForegroundColor Cyan
Log "Start - PC: $env:COMPUTERNAME" "Green"

# Windows 시리얼 키 확인 및 저장
Log "Checking Windows license key..." "Cyan"
try {
    $key = (Get-WmiObject -Query 'select * from SoftwareLicensingService').OA3xOriginalProductKey
    if ($key) {
        Log "  Windows Key: $key" "Green"
        Add-Content -Path "$PSScriptRoot\윈도우_시리얼키.txt" -Value "PC: $env:COMPUTERNAME"
        Add-Content -Path "$PSScriptRoot\윈도우_시리얼키.txt" -Value "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
        Add-Content -Path "$PSScriptRoot\윈도우_시리얼키.txt" -Value "Key: $key"
        Add-Content -Path "$PSScriptRoot\윈도우_시리얼키.txt" -Value "---"
        Log "  Key saved to 윈도우_시리얼키.txt" "Green"
    } else {
        Log "  No OEM key found (may auto-activate via internet after reinstall)" "Yellow"
    }
} catch {
    Log "  Key check failed: $($_.Exception.Message)" "Red"
}

# Step 1: Windows Update
Section "1/5  Windows Update"
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
    Log "Windows Update triggered" "Green"
}

# Step 2: 앱 업데이트 (winget)
Section "2/5  App Updates (winget)"
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

# Step 3: 임시파일 정리
Section "3/5  Temp Files & Recycle Bin"
$cleanPaths = @(
    $env:TEMP, $env:TMP,
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
} catch {}
Log "Cleanup done - freed ~$totalMB MB" "Green"

# Step 4: 디스크 정리
Section "4/5  Disk Cleanup (cleanmgr)"
Log "Running disk cleanup..." "Cyan"
$regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
Get-ChildItem $regPath | ForEach-Object {
    Set-ItemProperty -Path $_.PSPath -Name "StateFlags65535" -Value 2 -Type DWORD -ErrorAction SilentlyContinue
}
Start-Process "cleanmgr.exe" -ArgumentList "/sagerun:65535" -Wait -NoNewWindow
Log "Disk cleanup done" "Green"

# Step 5: 시스템 파일 복구 + BCD
Section "5/5  System Repair (SFC / DISM / BCD)"
Log "Running SFC scan..." "Cyan"
sfc /scannow 2>&1 | Select-String "Windows Resource Protection" | ForEach-Object { Log "  $_" "Gray" }
Log "SFC done" "Green"

Log "Running DISM repair..." "Cyan"
DISM /Online /Cleanup-Image /RestoreHealth 2>&1 | Select-String "(Error|complete|percent)" | ForEach-Object { Log "  $_" "Gray" }
Log "DISM done" "Green"

Log "Repairing BCD boot record..." "Cyan"
try {
    bcdedit /export "$env:TEMP\bcd_backup" | Out-Null
    bootrec /fixmbr 2>&1 | ForEach-Object { Log "  fixmbr: $_" "Gray" }
    bootrec /fixboot 2>&1 | ForEach-Object { Log "  fixboot: $_" "Gray" }
    bootrec /rebuildbcd 2>&1 | ForEach-Object { Log "  rebuildbcd: $_" "Gray" }
    Log "BCD repair done" "Green"
} catch {
    Log "BCD repair error: $($_.Exception.Message)" "Red"
}

Log "Checking drivers..." "Cyan"
try {
    $errorDevices = Get-WmiObject Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -ne 0 }
    if ($errorDevices) {
        $errorDevices | ForEach-Object { Log "  WARNING: $($_.Name) (code: $($_.ConfigManagerErrorCode))" "Yellow" }
    } else {
        Log "  All drivers OK" "Gray"
    }
} catch {
    Log "Driver check error: $($_.Exception.Message)" "Red"
}

Log "Network reset..." "Cyan"
ipconfig /flushdns | Out-Null
netsh winsock reset | Out-Null
netsh int ip reset | Out-Null
Log "Network reset done" "Green"

# 완료
Write-Host ""
Write-Host ("=" * 55) -ForegroundColor Green
Write-Host "  업데이트 완료! 재부팅을 권장합니다." -ForegroundColor Green
Write-Host ("=" * 55) -ForegroundColor Green
Log "Done. Log: $LogFile" "Green"

Write-Host ""
$ans = Read-Host "Reboot now? (Y/N)"
if ($ans -eq "Y" -or $ans -eq "y") {
    Restart-Computer -Force
} else {
    Write-Host "Log: $LogFile" -ForegroundColor Cyan
    Read-Host "Press Enter to close"
}
