@echo off
chcp 65001 >nul
title Last Resort - Auto Diagnosis & Recovery

set LOG=%~dp0lastresort_log_%DATE:~0,4%%DATE:~5,2%%DATE:~8,2%_%TIME:~0,2%%TIME:~3,2%.txt
set LOG=%LOG: =0%
set HW_OK=1

cls
echo. > "%LOG%"
echo =====================================================
echo   최후 수단 자동 복구
echo   하드웨어 진단 후 이상없으면 Windows 재설치까지
echo =====================================================
echo.
echo  순서: 진단 → 백업 → 재설치
echo  로그: %LOG%
echo.
pause

:: =====================================================
:: STEP 1: 하드웨어 진단
:: =====================================================
:STEP1
cls
echo =====================================================
echo  STEP 1/4  하드웨어 진단
echo =====================================================
echo.
echo [로그에 기록 중...]
echo [STEP1] Hardware Diagnosis >> "%LOG%"

:: --- Windows 시리얼 키 확인 ---
echo.
echo [Windows 시리얼 키 확인 중...]
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
"try { ^
    $key = (Get-WmiObject -Query 'select * from SoftwareLicensingService').OA3xOriginalProductKey; ^
    if($key){ ^
        Write-Host ('  Windows Key: ' + $key) -ForegroundColor Green; ^
        $line = 'PC: ' + $env:COMPUTERNAME + ' / Date: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm') + ' / Key: ' + $key; ^
        Add-Content '%~dp0윈도우_시리얼키.txt' $line; ^
        Add-Content '%LOG%' ('[KEY] ' + $key) ^
    } else { ^
        Write-Host '  OEM 키 없음 (재설치 후 인터넷 연결시 자동 인증)' -ForegroundColor Yellow; ^
        Add-Content '%LOG%' '[KEY] Not found - auto activation expected' ^
    } ^
} catch { ^
    Write-Host ('  키 확인 실패: ' + $_.Exception.Message) -ForegroundColor Red ^
}"
echo.

:: --- RAM 검사 예약 여부 ---
echo [RAM] Windows Memory Diagnostic 예약...
echo.
set /p ramcheck= RAM 검사를 먼저 하시겠습니까? (재부팅 필요) (Y/N): 
if /i "%ramcheck%"=="Y" (
    echo RAM 검사 예약됨. 재부팅 후 검사 완료되면 이 파일을 다시 실행하세요.
    echo [RAM] User requested memory test - reboot scheduled >> "%LOG%"
    mdsched.exe
    pause
    exit /b
)

:: --- 시스템 정보 수집 ---
echo.
echo [시스템 정보 수집 중...]
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
"$r = ''; ^
$cpu = Get-WmiObject Win32_Processor; ^
$r += 'CPU: ' + $cpu.Name + [Environment]::NewLine; ^
$ram = [math]::Round((Get-WmiObject Win32_ComputerSystem).TotalPhysicalMemory/1GB,1); ^
$r += 'RAM: ' + $ram + ' GB' + [Environment]::NewLine; ^
$disks = Get-WmiObject Win32_DiskDrive; ^
foreach($d in $disks){ $r += 'Disk: ' + $d.Model + ' ' + [math]::Round($d.Size/1GB,0) + 'GB' + [Environment]::NewLine }; ^
Write-Host $r; ^
Add-Content -Path '%LOG%' -Value $r"

:: --- S.M.A.R.T 디스크 상태 ---
echo.
echo [디스크 S.M.A.R.T 상태 확인 중...]
set DISK_FAIL=0
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
"$disks = Get-WmiObject -Namespace root\wmi -Class MSStorageDriver_FailurePredictStatus 2>$null; ^
$fail = $false; ^
if($disks){ ^
    foreach($d in $disks){ ^
        if($d.PredictFailure){ ^
            Write-Host '  !! 디스크 고장 예측 - 즉시 백업 필요!!' -ForegroundColor Red; ^
            Add-Content '%LOG%' '[DISK] SMART FAILURE PREDICTED'; ^
            $fail = $true ^
        } else { ^
            Write-Host '  OK: 디스크 S.M.A.R.T 정상' -ForegroundColor Green; ^
            Add-Content '%LOG%' '[DISK] SMART OK' ^
        } ^
    } ^
} else { ^
    Write-Host '  S.M.A.R.T 조회 불가 (정상으로 간주)' -ForegroundColor Yellow; ^
    Add-Content '%LOG%' '[DISK] SMART N/A' ^
}; ^
if($fail){ exit 1 } else { exit 0 }"
if %errorlevel%==1 (
    set DISK_FAIL=1
    set HW_OK=0
)

:: --- 이벤트 로그 심각 오류 확인 ---
echo.
echo [시스템 이벤트 오류 확인 중...]
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
"$errors = Get-EventLog -LogName System -EntryType Error -Newest 10 2>$null; ^
if($errors){ ^
    Write-Host '  최근 시스템 오류:' -ForegroundColor Yellow; ^
    $errors | Select-Object -First 5 | ForEach-Object { ^
        $msg = $_.Message.Substring(0,[math]::Min(100,$_.Message.Length)); ^
        Write-Host ('  ' + $_.TimeGenerated.ToString('MM/dd HH:mm') + ' ' + $_.Source + ': ' + $msg); ^
        Add-Content '%LOG%' ('[EVENT] ' + $_.Source + ': ' + $msg) ^
    } ^
} else { ^
    Write-Host '  심각한 이벤트 오류 없음' -ForegroundColor Green ^
}"

:: --- BSOD 덤프 확인 ---
echo.
echo [블루스크린 기록 확인 중...]
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
"$dumps = Get-ChildItem 'C:\Windows\Minidump' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending; ^
if($dumps){ ^
    Write-Host ('  BSOD 덤프 ' + $dumps.Count + '개 발견:') -ForegroundColor Yellow; ^
    $dumps | Select-Object -First 3 | ForEach-Object { ^
        Write-Host ('  ' + $_.Name + '  ' + $_.LastWriteTime); ^
        Add-Content '%LOG%' ('[BSOD] ' + $_.Name + ' ' + $_.LastWriteTime) ^
    } ^
} else { ^
    Write-Host '  BSOD 기록 없음' -ForegroundColor Green ^
}"

:: --- 진단 결과 판정 ---
echo.
echo ─────────────────────────────────────────────────
if %HW_OK%==0 (
    echo.
    echo  !! 하드웨어 이상 감지 !!
    echo.
    if %DISK_FAIL%==1 (
        echo  [디스크 불량 예측]
        echo   - 즉시 데이터 백업 후 HDD/SSD 교체 필요
        echo   - 재설치해도 같은 디스크면 또 고장납니다
        echo   - 새 디스크 구매 후 재설치 권장
    )
    echo.
    echo  재설치를 진행하려면 디스크를 교체한 후 다시 실행하세요.
    echo  [로그 저장됨: %LOG%]
    echo.
    set /p force= 그래도 강제로 재설치를 진행하시겠습니까? (Y/N): 
    if /i not "%force%"=="Y" (
        echo 종료합니다. 하드웨어 점검 후 다시 실행하세요.
        pause
        exit /b
    )
    echo 강제 진행합니다... >> "%LOG%"
) else (
    echo  하드웨어 이상 없음 - 재설치 진행 가능
    echo  [HW] All OK >> "%LOG%"
)
echo.
pause

:: =====================================================
:: STEP 2: 데이터 백업
:: =====================================================
:STEP2
cls
echo =====================================================
echo  STEP 2/4  데이터 자동 백업
echo =====================================================
echo.
echo  재설치 전 중요 파일을 백업합니다.
echo  백업할 드라이브를 선택하세요.
echo.
echo  현재 드라이브 목록:
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
"Get-PSDrive -PSProvider FileSystem | Where-Object {$_.Name -ne 'C'} | ^
ForEach-Object { Write-Host ('  ' + $_.Name + ': 드라이브  여유공간: ' + [math]::Round($_.Free/1GB,1) + ' GB') }"
echo.
set /p BDRIVE= 백업 드라이브 문자 입력 (예: D 또는 E, 없으면 Skip 입력): 

if /i "%BDRIVE%"=="skip" (
    echo 백업 건너뜀 - 데이터가 삭제될 수 있습니다!
    echo [BACKUP] Skipped by user >> "%LOG%"
    set /p bskip= 정말 백업 없이 진행하시겠습니까? (Y/N): 
    if /i not "%bskip%"=="Y" goto :STEP2
    goto :STEP3
)

set BPATH=%BDRIVE%:\Backup_%DATE:~0,4%%DATE:~5,2%%DATE:~8,2%
echo.
echo 백업 위치: %BPATH%
echo [BACKUP] Target: %BPATH% >> "%LOG%"
mkdir "%BPATH%" 2>nul

echo.
echo [바탕화면 백업 중...]
xcopy "%USERPROFILE%\Desktop" "%BPATH%\Desktop" /E /H /C /I /Y /Q 2>nul
echo [문서 백업 중...]
xcopy "%USERPROFILE%\Documents" "%BPATH%\Documents" /E /H /C /I /Y /Q 2>nul
echo [사진 백업 중...]
xcopy "%USERPROFILE%\Pictures" "%BPATH%\Pictures" /E /H /C /I /Y /Q 2>nul
echo [다운로드 백업 중...]
xcopy "%USERPROFILE%\Downloads" "%BPATH%\Downloads" /E /H /C /I /Y /Q 2>nul
echo [즐겨찾기 백업 중...]
xcopy "%USERPROFILE%\Favorites" "%BPATH%\Favorites" /E /H /C /I /Y /Q 2>nul
echo [와이파이 프로필 백업 중...]
netsh wlan export profile key=clear folder="%BPATH%" >nul 2>&1

echo.
echo =====================================================
echo  백업 완료: %BPATH%
echo =====================================================
echo [BACKUP] Done: %BPATH% >> "%LOG%"
echo.
pause

:: =====================================================
:: STEP 3: 재설치 방법 선택
:: =====================================================
:STEP3
cls
echo =====================================================
echo  STEP 3/4  재설치 방법 선택
echo =====================================================
echo.
echo  [1] Windows 초기화 - 파일 유지  (빠름, 10분)
echo      개인 파일 보존, 앱/설정 초기화
echo.
echo  [2] Windows 초기화 - 완전 초기화  (권장, 20분)
echo      모든 파일/앱/설정 삭제 후 깨끗하게 재설치
echo.
echo  [3] USB 부팅 디스크 자동 생성 + 재설치  (완전 새설치)
echo      ISO 자동 다운로드 + USB 자동 포맷/기록
echo      USB 8GB 이상 필요 (꽂아두세요)
echo.
set /p method= 방법을 선택하세요 (1/2/3): 

if "%method%"=="1" goto :RESET_KEEP
if "%method%"=="2" goto :RESET_FULL
if "%method%"=="3" goto :USB_AUTO
goto :STEP3

:: =====================================================
:: STEP 4a: 파일 유지 초기화
:: =====================================================
:RESET_KEEP
cls
echo =====================================================
echo  STEP 4/4  Windows 초기화 (파일 유지)
echo =====================================================
echo.
echo  - 개인 파일(문서, 사진 등) 유지
echo  - 설치된 앱 모두 삭제
echo  - Windows 설정 초기화
echo.
set /p ok= 진행하시겠습니까? (Y/N): 
if /i not "%ok%"=="Y" goto :STEP3
echo [RESET] Keep files reset initiated >> "%LOG%"
echo.
echo Windows 초기화를 시작합니다...
echo 설정 창이 열리면 [이 PC 초기화] - [내 파일 유지] 를 선택하세요.
echo.
timeout /t 3 >nul
powershell -Command "Start-Process 'ms-settings:recovery'"
echo.
echo 설정 창에서 진행하세요.
echo 완료 후 자동으로 재부팅됩니다.
pause
exit /b

:: =====================================================
:: STEP 4b: 완전 초기화
:: =====================================================
:RESET_FULL
cls
echo =====================================================
echo  STEP 4/4  Windows 완전 초기화
echo =====================================================
echo.
echo  !! 경고: 모든 파일과 앱이 삭제됩니다 !!
echo  백업이 완료된 경우에만 진행하세요.
echo.
set /p ok2= 정말 모든 데이터를 삭제하고 초기화하시겠습니까? (YES 입력): 
if not "%ok2%"=="YES" (
    echo 취소되었습니다.
    pause
    goto :STEP3
)
echo [RESET] Full reset initiated >> "%LOG%"
echo.
echo Windows 완전 초기화를 시작합니다...
timeout /t 3 >nul
:: systemreset으로 직접 초기화 실행
systemreset --factoryreset
echo.
echo 초기화 화면이 나타나면 [모두 제거] 를 선택하세요.
pause
exit /b

:: =====================================================
:: STEP 4c: USB 자동 생성 + 재설치
:: =====================================================
:USB_AUTO
cls
echo =====================================================
echo  STEP 4/4  USB 부팅 디스크 자동 생성
echo =====================================================
echo.
echo  USB를 꽂아두세요. (8GB 이상, 내용 모두 삭제됨)
echo.

:: USB 드라이브 목록 표시
echo  현재 연결된 USB/외장 드라이브:
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
"Get-WmiObject Win32_DiskDrive | Where-Object {$_.MediaType -like '*Removable*' -or $_.InterfaceType -eq 'USB'} | ForEach-Object { ^
    $disk = $_; ^
    Get-WmiObject -Query ('ASSOCIATORS OF {Win32_DiskDrive.DeviceID=""' + $disk.DeviceID.Replace('\','\\') + '""} WHERE AssocClass=Win32_DiskDriveToDiskPartition') | ForEach-Object { ^
        Get-WmiObject -Query ('ASSOCIATORS OF {Win32_DiskPartition.DeviceID=""' + $_.DeviceID + '""} WHERE AssocClass=Win32_LogicalDiskToPartition') | ForEach-Object { ^
            Write-Host ('  ' + $_.DeviceID + '  ' + [math]::Round($disk.Size/1GB,0) + 'GB  ' + $_.VolumeName) ^
        } ^
    } ^
}"
echo.
set /p USBDRIVE= USB 드라이브 문자 입력 (예: E): 
if "%USBDRIVE%"=="" goto :USB_AUTO

echo.
echo  Windows 버전 선택:
echo  [1] Windows 11 (권장, 2024년 이후 PC)
echo  [2] Windows 10 (구형 PC 또는 호환성 필요시)
echo.
set /p WINVER= 선택 (1/2): 

set MCT_URL=
if "%WINVER%"=="1" set MCT_URL=https://go.microsoft.com/fwlink/?LinkID=2156295
if "%WINVER%"=="2" set MCT_URL=https://go.microsoft.com/fwlink/?LinkId=691209
if "%MCT_URL%"=="" (
    echo 잘못된 선택입니다.
    goto :USB_AUTO
)

echo.
echo =====================================================
echo  진행 순서:
echo  1. MediaCreationTool 다운로드
echo  2. USB 자동 포맷 및 Windows 설치 미디어 생성
echo  3. 재부팅 후 USB로 부팅하여 설치 진행
echo =====================================================
echo.
set /p goahead= 시작하시겠습니까? USB %USBDRIVE%: 의 모든 데이터가 삭제됩니다 (YES 입력): 
if not "%goahead%"=="YES" goto :STEP3

echo.
echo [1/3] MediaCreationTool 다운로드 중... (잠시 기다려주세요)
set MCT_PATH=%TEMP%\MediaCreationTool.exe
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
"$url = '%MCT_URL%'; ^
$out = '%MCT_PATH%'; ^
Write-Host '  다운로드 중...'; ^
$wc = New-Object System.Net.WebClient; ^
$wc.DownloadFile($url, $out); ^
Write-Host '  다운로드 완료: ' $out"

if not exist "%MCT_PATH%" (
    echo.
    echo  !! 다운로드 실패 - 인터넷 연결을 확인하세요
    echo.
    echo  수동 다운로드:
    if "%WINVER%"=="1" echo  https://www.microsoft.com/ko-kr/software-download/windows11
    if "%WINVER%"=="2" echo  https://www.microsoft.com/ko-kr/software-download/windows10
    pause
    goto :STEP3
)

echo.
echo [2/3] MediaCreationTool 실행 중...
echo.
echo  !! 중요 안내 !!
echo  창이 열리면 아래 순서로 진행하세요:
echo.
echo  1. [동의] 클릭
echo  2. [다른 PC용 설치 미디어 만들기] 선택
echo  3. 언어/버전 기본값 유지 후 [다음]
echo  4. [USB 플래시 드라이브] 선택
echo  5. %USBDRIVE%: 드라이브 선택
echo  6. 다운로드 완료까지 대기 (약 20-40분)
echo.
echo  완료되면 이 창으로 돌아오세요.
echo.
start "" "%MCT_PATH%"
echo [USB] MCT launched >> "%LOG%"

pause

echo.
echo [3/3] USB 부팅 설정 안내
echo.
echo =====================================================
echo  USB 생성이 완료되었으면 아래 순서로 재설치하세요
echo =====================================================
echo.
echo  1. 이 PC를 재시작하면서 아래 키를 연타
echo.
echo   삼성/LG : F2          Dell  : F2 or F12
echo   HP      : F10 or ESC  Lenovo: F1 or F2
echo   ASUS    : F2 or DEL   MSI   : DEL
echo   조립PC  : DEL or F2
echo.
echo  2. BIOS Boot 메뉴에서 USB를 1순위로 변경 후 저장(F10)
echo.
echo  3. USB로 부팅 후:
echo     [지금 설치] → 키 없음(자동인증) → [사용자 지정]
echo     → 기존 파티션 포맷 → 설치
echo.
echo  4. 설치 후 Windows Update 실행하면 드라이버 자동 설치
echo.
echo =====================================================
echo  백업 위치: %BPATH%
echo  로그 파일: %LOG%
echo =====================================================
echo.

set /p reboot= 지금 재시작하시겠습니까? (Y/N): 
if /i "%reboot%"=="Y" (
    echo [REBOOT] User initiated reboot >> "%LOG%"
    shutdown /r /t 5 /c "Windows 재설치를 위해 재시작합니다. USB가 꽂혀있는지 확인하세요."
)
pause
exit /b
