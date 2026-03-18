# Speed Optimizer - 속도 최적화 전용 (5~10분)

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
Write-Host "   Windows 속도 최적화 (5~10분)" -ForegroundColor Cyan
Write-Host ("=" * 55) -ForegroundColor Cyan
Log "Start - PC: $env:COMPUTERNAME" "Green"

# Step 1: 시작프로그램 정리
Section "1/7  Startup Programs"
Log "Disabling unnecessary startup entries..." "Cyan"
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
                Log "  Removed startup: $($_.Name)" "Gray"
            }
        }
    }
}
$delayKey = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Serialize"
if (-not (Test-Path $delayKey)) { New-Item -Path $delayKey -Force | Out-Null }
Set-ItemProperty -Path $delayKey -Name "StartupDelayInMSec" -Value 0 -Type DWORD
Log "Startup delay removed" "Gray"
Log "Startup optimization done" "Green"

# Step 2: 불필요한 서비스 끄기
Section "2/7  Background Services"
Log "Disabling unnecessary services..." "Cyan"
$servicesToDisable = @(
    @{Name="DiagTrack";        Desc="Telemetry tracking"},
    @{Name="dmwappushservice"; Desc="WAP Push Routing"},
    @{Name="SysMain";          Desc="Superfetch (SSD only)"},
    @{Name="Fax";              Desc="Fax"},
    @{Name="XblAuthManager";   Desc="Xbox Live Auth"},
    @{Name="XblGameSave";      Desc="Xbox Live Game Save"},
    @{Name="XboxNetApiSvc";    Desc="Xbox Network"},
    @{Name="MapsBroker";       Desc="Maps Manager"},
    @{Name="RetailDemo";       Desc="Retail Demo"},
    @{Name="RemoteRegistry";   Desc="Remote Registry"}
)
$isSSD = $false
try {
    if (Get-PhysicalDisk | Where-Object { $_.MediaType -eq "SSD" }) { $isSSD = $true }
} catch {}
Log "  Drive type: $(if($isSSD){'SSD'}else{'HDD'})" "Gray"

foreach ($svc in $servicesToDisable) {
    if ($svc.Name -eq "SysMain" -and -not $isSSD) {
        Log "  Kept SysMain (HDD - Superfetch helps)" "DarkGray"
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

# Step 3: 임시파일 정리 (디스크 공간 확보)
Section "3/7  Temp Files Cleanup"
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

# Step 4: 디스크 최적화 (HDD=조각모음 / SSD=TRIM)
Section "4/7  Disk Optimization"
try {
    $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match "^[A-Z]:\\" }
    foreach ($drive in $drives) {
        $driveLetter = $drive.Root.TrimEnd('\')
        if ($isSSD) {
            Log "  SSD TRIM: $driveLetter" "Cyan"
            Optimize-Volume -DriveLetter $drive.Name -ReTrim -Verbose 2>&1 | Out-Null
            Log "  TRIM done: $driveLetter" "Gray"
        } else {
            Log "  HDD Defrag: $driveLetter (analysis only - full defrag takes long)" "Cyan"
            Optimize-Volume -DriveLetter $drive.Name -Analyze -Verbose 2>&1 | Out-Null
            Log "  Defrag analysis done: $driveLetter" "Gray"
        }
    }
} catch {
    Log "  Disk optimization error: $($_.Exception.Message)" "Red"
}
Log "Disk optimization done" "Green"

# Step 5: 가상메모리 최적화
Section "5/7  Virtual Memory (Page File)"
Log "Checking RAM and page file..." "Cyan"
try {
    $ram = [math]::Round((Get-WmiObject Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
    Log "  Total RAM: $ram GB" "Gray"
    if ($ram -le 4) {
        # RAM 4GB 이하면 페이지파일 시스템 관리로 설정 (자동 최적화)
        $cs = Get-WmiObject Win32_ComputerSystem
        $cs.AutomaticManagedPagefile = $true
        $cs.Put() | Out-Null
        Log "  RAM low ($ram GB) - page file set to system managed" "Yellow"
    } else {
        Log "  RAM sufficient ($ram GB) - page file OK" "Green"
    }
} catch {
    Log "  Page file check error: $($_.Exception.Message)" "Red"
}
Log "Virtual memory check done" "Green"

# Step 6: 드라이버 오류 확인
Section "6/7  Driver Error Check"
Log "Checking for driver errors..." "Cyan"
try {
    $errorDevices = Get-WmiObject Win32_PnPEntity |
        Where-Object { $_.ConfigManagerErrorCode -ne 0 } |
        Select-Object Name, ConfigManagerErrorCode
    if ($errorDevices) {
        Log "  WARNING - Devices with errors:" "Yellow"
        $errorDevices | ForEach-Object {
            Log "    ! $($_.Name) (error code: $($_.ConfigManagerErrorCode))" "Yellow"
        }
        Log "  -> Device Manager에서 확인 후 드라이버 재설치 권장" "Yellow"
    } else {
        Log "  All drivers OK" "Green"
    }
} catch {
    Log "  Driver check error: $($_.Exception.Message)" "Red"
}
Log "Driver check done" "Green"

# Step 7: 시각효과 & 전원 설정
Section "7/7  Visual Effects & Power Plan"
Log "Setting visual effects to performance..." "Cyan"
$perfKey = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
if (-not (Test-Path $perfKey)) { New-Item -Path $perfKey -Force | Out-Null }
Set-ItemProperty -Path $perfKey -Name "VisualFXSetting" -Value 2 -Type DWORD

$advKey = "HKCU:\Control Panel\Desktop"
Set-ItemProperty -Path $advKey -Name "UserPreferencesMask" -Value ([byte[]](0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00)) -Type Binary -ErrorAction SilentlyContinue
Set-ItemProperty -Path $advKey -Name "MenuShowDelay" -Value "0" -ErrorAction SilentlyContinue

$windowKey = "HKCU:\Control Panel\Desktop\WindowMetrics"
Set-ItemProperty -Path $windowKey -Name "MinAnimate" -Value "0" -ErrorAction SilentlyContinue
Log "Visual effects: performance mode" "Gray"

$hp = powercfg /list 2>&1 | Select-String "High performance"
if ($hp) {
    $guid = ($hp -split "\s+")[3]
    powercfg /setactive $guid | Out-Null
} else {
    powercfg /setactive SCHEME_MIN | Out-Null
}
Log "Power plan: High Performance" "Gray"

powercfg /hibernate off | Out-Null
Log "Hibernation disabled" "Gray"

$personKey = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize"
Set-ItemProperty -Path $personKey -Name "EnableTransparency" -Value 0 -Type DWORD -ErrorAction SilentlyContinue
Log "Transparency disabled" "Gray"

$bgKey = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"
Set-ItemProperty -Path $bgKey -Name "GlobalUserDisabled" -Value 1 -Type DWORD -ErrorAction SilentlyContinue
Log "Background apps disabled" "Gray"

# 바이러스 검사 실행 (Windows Defender)
Log "Running Windows Defender quick scan..." "Cyan"
try {
    Start-MpScan -ScanType QuickScan -ErrorAction Stop
    Log "Defender quick scan started (runs in background)" "Green"
} catch {
    Log "Defender scan skip: $($_.Exception.Message)" "DarkGray"
}

Log "Performance optimization done" "Green"

# 완료
Write-Host ""
Write-Host ("=" * 55) -ForegroundColor Green
Write-Host "  속도 최적화 완료! 재부팅하면 바로 체감됩니다." -ForegroundColor Green
Write-Host ("=" * 55) -ForegroundColor Green

# 드라이버 오류 있으면 다시 알림
$errorDevices = Get-WmiObject Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -ne 0 }
if ($errorDevices) {
    Write-Host ""
    Write-Host "  ! 드라이버 오류 감지됨 - 장치 관리자 확인 필요" -ForegroundColor Yellow
}

Log "Done. Log: $LogFile" "Green"
Write-Host ""
$ans = Read-Host "Reboot now? (Y/N)"
if ($ans -eq "Y" -or $ans -eq "y") {
    Restart-Computer -Force
} else {
    Write-Host "Log: $LogFile" -ForegroundColor Cyan
    Read-Host "Press Enter to close"
}
