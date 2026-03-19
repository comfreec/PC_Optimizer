# Speed Optimizer

$LogFile = "$PSScriptRoot\log_speed_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

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
Write-Host "   Windows Speed Optimizer (5~10min)" -ForegroundColor Cyan
Write-Host ("=" * 55) -ForegroundColor Cyan
Log "Start - PC: $env:COMPUTERNAME" "Green"

# SSD 여부 확인 (여러 단계에서 사용)
$isSSD = $false
try {
    if (Get-PhysicalDisk | Where-Object { $_.MediaType -eq "SSD" }) { $isSSD = $true }
} catch {}
Log "Drive type: $(if($isSSD){'SSD'}else{'HDD'})" "Gray"

# Step 1: 시작프로그램 정리
Section "1/9  Startup Programs"
Log "Removing unnecessary startup entries..." "Cyan"
$startupKeys = @(
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"
)
$bloat = @("Spotify","Discord","Steam","EpicGamesLauncher","AdobeGCInvoker",
           "iTunesHelper","GoogleUpdate","CCleaner","Skype","Zoom",
           "KakaoTalk","LINE","BaiduIME","WeChatApp","DropboxUpdate","GoogleDriveFS")
foreach ($key in $startupKeys) {
    if (Test-Path $key) {
        $entries = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
        $entries.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" } | ForEach-Object {
            if ($bloat -contains $_.Name) {
                Remove-ItemProperty -Path $key -Name $_.Name -ErrorAction SilentlyContinue
                Log "  Removed: $($_.Name)" "Gray"
            }
        }
    }
}
$delayKey = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Serialize"
if (-not (Test-Path $delayKey)) { New-Item -Path $delayKey -Force | Out-Null }
Set-ItemProperty -Path $delayKey -Name "StartupDelayInMSec" -Value 0 -Type DWORD
Log "Startup delay: 0ms" "Gray"
Log "Startup done" "Green"

# Step 2: 불필요한 서비스 끄기
Section "2/9  Background Services"
Log "Disabling unnecessary services..." "Cyan"
$servicesToDisable = @(
    @{Name="DiagTrack";        Desc="Telemetry"},
    @{Name="dmwappushservice"; Desc="WAP Push"},
    @{Name="SysMain";          Desc="Superfetch"},
    @{Name="Fax";              Desc="Fax"},
    @{Name="XblAuthManager";   Desc="Xbox Auth"},
    @{Name="XblGameSave";      Desc="Xbox GameSave"},
    @{Name="XboxNetApiSvc";    Desc="Xbox Network"},
    @{Name="MapsBroker";       Desc="Maps"},
    @{Name="RetailDemo";       Desc="RetailDemo"},
    @{Name="RemoteRegistry";   Desc="RemoteRegistry"}
)
foreach ($svc in $servicesToDisable) {
    if ($svc.Name -eq "SysMain" -and -not $isSSD) {
        Log "  Kept SysMain (HDD)" "DarkGray"
        continue
    }
    $s = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
    if ($s -and $s.StartType -ne "Disabled") {
        try {
            Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
            Set-Service -Name $svc.Name -StartupType Disabled -ErrorAction SilentlyContinue
            Log "  Disabled: $($svc.Name)" "Gray"
        } catch {
            Log "  Skip: $($svc.Name)" "DarkGray"
        }
    }
}
Log "Services done" "Green"

# Step 3: 임시파일 정리
Section "3/9  Temp Files Cleanup"
Log "Cleaning temp files..." "Cyan"
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
try { Clear-RecycleBin -Force -ErrorAction SilentlyContinue; Log "  Recycle Bin emptied" "Gray" } catch {}
Log "Cleanup done - freed ~$totalMB MB" "Green"

# Step 4: 디스크 최적화
Section "4/9  Disk Optimization"
Log "Optimizing disk..." "Cyan"
try {
    $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match "^[A-Z]:\\" }
    foreach ($drive in $drives) {
        if ($isSSD) {
            Optimize-Volume -DriveLetter $drive.Name -ReTrim -Verbose 2>&1 | Out-Null
            Log "  TRIM: $($drive.Root)" "Gray"
        } else {
            Optimize-Volume -DriveLetter $drive.Name -Analyze -Verbose 2>&1 | Out-Null
            Log "  Analyzed: $($drive.Root)" "Gray"
        }
    }
} catch {
    Log "  Disk optimization error: $($_.Exception.Message)" "Red"
}
Log "Disk done" "Green"

# Step 5: 가상메모리
Section "5/9  Virtual Memory"
Log "Checking RAM..." "Cyan"
try {
    $ram = [math]::Round((Get-WmiObject Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
    Log "  RAM: $ram GB" "Gray"
    if ($ram -le 4) {
        $cs = Get-WmiObject Win32_ComputerSystem
        $cs.AutomaticManagedPagefile = $true
        $cs.Put() | Out-Null
        Log "  Page file: system managed (low RAM)" "Yellow"
    } else {
        Log "  Page file: OK" "Green"
    }
} catch {
    Log "  RAM check error: $($_.Exception.Message)" "Red"
}
Log "Memory done" "Green"

# Step 6: 드라이버 확인
Section "6/9  Driver Check"
Log "Checking drivers..." "Cyan"
try {
    $errorDevices = Get-WmiObject Win32_PnPEntity |
        Where-Object { $_.ConfigManagerErrorCode -ne 0 } |
        Select-Object Name, ConfigManagerErrorCode
    if ($errorDevices) {
        foreach ($d in $errorDevices) {
            Log "  Info: $($d.Name) (code $($d.ConfigManagerErrorCode)) - not speed related" "DarkGray"
        }
    } else {
        Log "  All drivers OK" "Green"
    }
} catch {
    Log "  Driver check error: $($_.Exception.Message)" "Red"
}
Log "Driver check done" "Green"

# Step 7: 시각효과 및 전원
Section "7/9  Visual Effects and Power"
Log "Setting performance mode..." "Cyan"
$perfKey = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
if (-not (Test-Path $perfKey)) { New-Item -Path $perfKey -Force | Out-Null }
Set-ItemProperty -Path $perfKey -Name "VisualFXSetting" -Value 2 -Type DWORD

$advKey = "HKCU:\Control Panel\Desktop"
Set-ItemProperty -Path $advKey -Name "UserPreferencesMask" -Value ([byte[]](0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00)) -Type Binary -ErrorAction SilentlyContinue
Set-ItemProperty -Path $advKey -Name "MenuShowDelay" -Value "0" -ErrorAction SilentlyContinue

$windowKey = "HKCU:\Control Panel\Desktop\WindowMetrics"
Set-ItemProperty -Path $windowKey -Name "MinAnimate" -Value "0" -ErrorAction SilentlyContinue
Log "  Visual effects: performance" "Gray"

$hp = powercfg /list 2>&1 | Select-String "High performance"
if ($hp) {
    $guid = ($hp -split "\s+")[3]
    powercfg /setactive $guid | Out-Null
} else {
    powercfg /setactive SCHEME_MIN | Out-Null
}
Log "  Power plan: High Performance" "Gray"

powercfg /hibernate off | Out-Null
Log "  Hibernation: disabled" "Gray"

$personKey = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize"
Set-ItemProperty -Path $personKey -Name "EnableTransparency" -Value 0 -Type DWORD -ErrorAction SilentlyContinue
Log "  Transparency: off" "Gray"

$bgKey = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"
Set-ItemProperty -Path $bgKey -Name "GlobalUserDisabled" -Value 1 -Type DWORD -ErrorAction SilentlyContinue
Log "  Background apps: off" "Gray"
Log "Visual and power done" "Green"

# Step 8: 레지스트리 최적화
Section "8/9  Registry Optimization"
Log "Applying registry tweaks..." "Cyan"

# 메뉴 반응속도
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -Value "0" -ErrorAction SilentlyContinue
Log "  Menu delay: 0ms" "Gray"

# 탐색기 반응속도
$explorerKey = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
Set-ItemProperty -Path $explorerKey -Name "ExtendedUIHoverTime" -Value 1 -Type DWORD -ErrorAction SilentlyContinue
Log "  Explorer response: fast" "Gray"

# 알림센터 끄기
$notifKey = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer"
if (-not (Test-Path $notifKey)) { New-Item -Path $notifKey -Force | Out-Null }
Set-ItemProperty -Path $notifKey -Name "DisableNotificationCenter" -Value 1 -Type DWORD -ErrorAction SilentlyContinue
Log "  Notification center: off" "Gray"

# 게임바 끄기
$gameKey = "HKCU:\SOFTWARE\Microsoft\GameBar"
if (-not (Test-Path $gameKey)) { New-Item -Path $gameKey -Force | Out-Null }
Set-ItemProperty -Path $gameKey -Name "AutoGameModeEnabled" -Value 0 -Type DWORD -ErrorAction SilentlyContinue
Set-ItemProperty -Path $gameKey -Name "AllowAutoGameMode" -Value 0 -Type DWORD -ErrorAction SilentlyContinue
$gameCapKey = "HKCU:\System\GameConfigStore"
if (-not (Test-Path $gameCapKey)) { New-Item -Path $gameCapKey -Force | Out-Null }
Set-ItemProperty -Path $gameCapKey -Name "GameDVR_Enabled" -Value 0 -Type DWORD -ErrorAction SilentlyContinue
Log "  Game bar: off" "Gray"

# 커널 RAM 상주
$memKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
Set-ItemProperty -Path $memKey -Name "DisablePagingExecutive" -Value 1 -Type DWORD -ErrorAction SilentlyContinue
Log "  Kernel in RAM: on" "Gray"

# SSD 최적화
if ($isSSD) {
    Set-ItemProperty -Path $memKey -Name "LargeSystemCache" -Value 0 -Type DWORD -ErrorAction SilentlyContinue
    Log "  SSD paging: optimized" "Gray"
}

# TCP 최적화
$tcpKey = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
Set-ItemProperty -Path $tcpKey -Name "TcpTimedWaitDelay" -Value 30 -Type DWORD -ErrorAction SilentlyContinue
Set-ItemProperty -Path $tcpKey -Name "DefaultTTL" -Value 64 -Type DWORD -ErrorAction SilentlyContinue
Log "  TCP: optimized" "Gray"

# 빠른 시작
$fastbootKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power"
Set-ItemProperty -Path $fastbootKey -Name "HiberbootEnabled" -Value 1 -Type DWORD -ErrorAction SilentlyContinue
Log "  Fast startup: on" "Gray"

# 부팅 멀티코어
try {
    $cpuCount = (Get-WmiObject Win32_Processor).NumberOfLogicalProcessors
    bcdedit /set numproc $cpuCount 2>&1 | Out-Null
    Log "  Boot cores: $cpuCount" "Gray"
} catch {
    Log "  Boot core setting skipped" "DarkGray"
}

Log "Registry done" "Green"

# Step 9: Defender 빠른 검사
Section "9/9  Windows Defender Scan"
Log "Starting quick scan (background)..." "Cyan"
try {
    Start-MpScan -ScanType QuickScan -ErrorAction Stop
    Log "Defender scan started in background" "Green"
} catch {
    Log "Defender scan skip: $($_.Exception.Message)" "DarkGray"
}

# 완료
Write-Host ""
Write-Host ("=" * 55) -ForegroundColor Green
Write-Host "  Speed optimization complete!" -ForegroundColor Green
Write-Host "  Reboot for full effect." -ForegroundColor Green
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
