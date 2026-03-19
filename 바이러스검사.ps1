# Virus Full Scan + Malware Removal

$LogFile = "$PSScriptRoot\log_virus_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

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
Write-Host "   바이러스 정밀 검사 및 제거" -ForegroundColor Cyan
Write-Host ("=" * 55) -ForegroundColor Cyan
Log "Start - PC: $env:COMPUTERNAME" "Green"

# Step 1: Defender 업데이트
Section "1/4  Defender 바이러스 정의 업데이트"
Log "Updating virus definitions..." "Cyan"
try {
    Update-MpSignature -ErrorAction Stop
    Log "Virus definitions updated" "Green"
} catch {
    Log "Update failed (offline?): $($_.Exception.Message)" "Yellow"
}

# Step 2: Defender 전체 검사
Section "2/4  Windows Defender 전체 검사"
Log "Starting full scan - 시간이 오래 걸립니다 (30분~2시간)..." "Yellow"
Log "검사 중에는 창을 닫지 마세요" "Yellow"
try {
    Start-MpScan -ScanType FullScan -ErrorAction Stop
    Log "Full scan completed" "Green"
} catch {
    Log "Full scan error: $($_.Exception.Message)" "Red"
}

# Step 3: 검사 결과 확인
Section "3/4  검사 결과"
try {
    $threats = Get-MpThreatDetection -ErrorAction SilentlyContinue
    if ($threats) {
        Log "  발견된 위협:" "Red"
        $threats | ForEach-Object {
            Log "    ! $($_.ThreatName) - $($_.Resources)" "Red"
        }
        Log "  자동 제거 시도 중..." "Yellow"
        Remove-MpThreat -ErrorAction SilentlyContinue
        Log "  위협 제거 완료" "Green"
    } else {
        Log "  위협 없음 - 깨끗한 상태" "Green"
    }
} catch {
    Log "  결과 확인 오류: $($_.Exception.Message)" "Red"
}

# Step 4: 의심 프로세스 확인
Section "4/4  의심 프로세스 확인"
Log "Checking suspicious processes..." "Cyan"
$suspiciousNames = @("miner","cryptominer","trojan","malware","adware",
                     "spyware","keylogger","backdoor","rootkit","worm")
$processes = Get-Process -ErrorAction SilentlyContinue
$found = $false
foreach ($proc in $processes) {
    foreach ($name in $suspiciousNames) {
        if ($proc.Name -like "*$name*") {
            Log "  ! 의심 프로세스: $($proc.Name) (PID: $($proc.Id))" "Red"
            $found = $true
        }
    }
}
if (-not $found) {
    Log "  의심 프로세스 없음" "Green"
}

# 완료
Write-Host ""
Write-Host ("=" * 55) -ForegroundColor Green
Write-Host "  바이러스 검사 완료" -ForegroundColor Green
Write-Host ("=" * 55) -ForegroundColor Green
Log "Done. Log: $LogFile" "Green"
Read-Host "Press Enter to close"
