@echo off
chcp 65001 >nul
title USB 부팅 디스크 만들기

cls
echo =====================================================
echo   USB 부팅 디스크 자동 생성
echo   Windows 10 / 11 설치 USB + 복구도구 포함
echo =====================================================
echo.
echo  준비물: USB 8GB 이상 (내용 전부 삭제됨)
echo.
pause

:: =====================================================
:: STEP 1: USB 선택
:: =====================================================
:SELECT_USB
cls
echo =====================================================
echo  STEP 1/4  USB 드라이브 선택
echo =====================================================
echo.
echo  현재 연결된 드라이브 목록:
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
"Get-WmiObject Win32_DiskDrive | ForEach-Object { ^
    $disk = $_; ^
    $type = if($disk.MediaType -like '*Removable*' -or $disk.InterfaceType -eq 'USB'){'[USB]'}else{'[HDD]'}; ^
    $size = [math]::Round($disk.Size/1GB,0); ^
    Get-WmiObject -Query ('ASSOCIATORS OF {Win32_DiskDrive.DeviceID=""' + $disk.DeviceID.Replace('\','\\') + '""} WHERE AssocClass=Win32_DiskDriveToDiskPartition') | ^
    ForEach-Object { ^
        Get-WmiObject -Query ('ASSOCIATORS OF {Win32_DiskPartition.DeviceID=""' + $_.DeviceID + '""} WHERE AssocClass=Win32_LogicalDiskToPartition') | ^
        ForEach-Object { Write-Host ('  ' + $type + ' ' + $_.DeviceID + '  ' + $size + 'GB  ' + $disk.Model) } ^
    } ^
}"
echo.
set /p USBDRIVE= USB 드라이브 문자 입력 (예: E): 
if "%USBDRIVE%"=="" goto :SELECT_USB

:: 드라이브 존재 확인
if not exist "%USBDRIVE%:\" (
    echo  드라이브 %USBDRIVE%: 를 찾을 수 없습니다. 다시 입력하세요.
    pause
    goto :SELECT_USB
)

:: C 드라이브 실수 방지
if /i "%USBDRIVE%"=="C" (
    echo  !! C 드라이브는 선택할 수 없습니다 !!
    pause
    goto :SELECT_USB
)

echo.
echo  선택된 드라이브: %USBDRIVE%:
echo  이 드라이브의 모든 데이터가 삭제됩니다.
set /p confirm= 계속하시겠습니까? (YES 입력): 
if not "%confirm%"=="YES" goto :SELECT_USB

:: =====================================================
:: STEP 2: Windows 버전 선택
:: =====================================================
:SELECT_WIN
cls
echo =====================================================
echo  STEP 2/4  Windows 버전 선택
echo =====================================================
echo.
echo  [1] Windows 11  (2020년 이후 PC 권장)
echo      요구사항: TPM 2.0, 64비트, RAM 4GB 이상
echo.
echo  [2] Windows 10  (구형 PC 또는 호환성 필요시)
echo      요구사항: 32/64비트, RAM 1GB 이상
echo.
set /p WINVER= 선택 (1/2): 
if "%WINVER%"=="1" (
    set WIN_NAME=Windows 11
    set MCT_URL=https://go.microsoft.com/fwlink/?LinkID=2156295
)
if "%WINVER%"=="2" (
    set WIN_NAME=Windows 10
    set MCT_URL=https://go.microsoft.com/fwlink/?LinkId=691209
)
if "%MCT_URL%"=="" goto :SELECT_WIN

echo.
echo  선택: %WIN_NAME%

:: =====================================================
:: STEP 3: MediaCreationTool 다운로드
:: =====================================================
:DOWNLOAD_MCT
cls
echo =====================================================
echo  STEP 3/4  MediaCreationTool 다운로드
echo =====================================================
echo.
echo  Microsoft 공식 서버에서 다운로드 중...
echo  (인터넷 연결 필요, 잠시 기다려주세요)
echo.

set MCT_PATH=%TEMP%\MediaCreationTool_%WINVER%.exe

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
"try { ^
    $wc = New-Object System.Net.WebClient; ^
    $wc.Headers.Add('User-Agent','Mozilla/5.0'); ^
    Write-Host '  다운로드 시작...'; ^
    $wc.DownloadFile('%MCT_URL%', '%MCT_PATH%'); ^
    Write-Host '  완료: %MCT_PATH%' -ForegroundColor Green ^
} catch { ^
    Write-Host ('  실패: ' + $_.Exception.Message) -ForegroundColor Red; ^
    exit 1 ^
}"

if %errorlevel% neq 0 (
    echo.
    echo  !! 다운로드 실패 !!
    echo  인터넷 연결을 확인하고 다시 시도하세요.
    echo.
    echo  수동 다운로드 주소:
    if "%WINVER%"=="1" echo  https://www.microsoft.com/ko-kr/software-download/windows11
    if "%WINVER%"=="2" echo  https://www.microsoft.com/ko-kr/software-download/windows10
    pause
    exit /b
)

:: =====================================================
:: STEP 4: USB에 Windows 설치 미디어 생성
:: =====================================================
:CREATE_USB
cls
echo =====================================================
echo  STEP 4/4  USB 부팅 디스크 생성
echo =====================================================
echo.
echo  %WIN_NAME% 설치 미디어를 %USBDRIVE%: 에 생성합니다.
echo.
echo  !! MediaCreationTool 창이 열립니다 !!
echo  아래 순서대로 진행하세요:
echo.
echo   1. [동의] 클릭
echo   2. [다른 PC용 설치 미디어 만들기] 선택 후 [다음]
echo   3. 언어/버전/아키텍처 기본값 유지 후 [다음]
echo   4. [USB 플래시 드라이브] 선택 후 [다음]
echo   5. 목록에서 %USBDRIVE%: 드라이브 선택
echo   6. 다운로드 완료까지 대기 (약 20-40분)
echo   7. 완료 후 [마침] 클릭
echo.
echo  완료되면 이 창으로 돌아오세요.
echo.
pause

start "" "%MCT_PATH%"

echo.
echo  MediaCreationTool이 실행되었습니다.
echo  위 안내대로 진행해주세요...
echo.
pause

:: =====================================================
:: PC_Optimizer 폴더를 USB에 복사
:: =====================================================
:COPY_TOOLS
cls
echo =====================================================
echo  PC_Optimizer 복구 도구를 USB에 복사 중...
echo =====================================================
echo.

set SRC=%~dp0
set DEST=%USBDRIVE%:\PC_Optimizer

echo  복사 위치: %DEST%
echo.

xcopy "%SRC%*" "%DEST%\" /E /H /C /I /Y /Q 2>nul

if exist "%DEST%\실행.bat" (
    echo  복사 완료!
    echo.
    echo =====================================================
    echo  USB 부팅 디스크 생성 완료!
    echo =====================================================
    echo.
    echo  USB 구성:
    echo   - Windows %WIN_NAME% 설치 파일  (부팅용)
    echo   - PC_Optimizer 복구 도구        (복구용)
    echo.
    echo  사용 방법:
    echo.
    echo  [Windows가 켜지는 PC]
    echo   USB 꽂고 PC_Optimizer\실행.bat 더블클릭
    echo.
    echo  [Windows가 안 켜지는 PC]
    echo   1. USB 꽂고 전원 켜면서 F2/F12/DEL 연타
    echo   2. BIOS에서 USB 부팅 1순위로 변경
    echo   3. 부팅 후 "컴퓨터 복구" 클릭
    echo   4. 문제 해결 - 고급 옵션 - 명령 프롬프트
    echo   5. wmic logicaldisk get name,description
    echo      (USB 드라이브 문자 확인)
    echo   6. E:\PC_Optimizer\부팅복구_WinRE.bat 실행
    echo      (E: 는 USB 드라이브 문자로 변경)
    echo.
) else (
    echo  !! 복사 실패 - USB가 제대로 연결되어 있는지 확인하세요
)

pause
exit /b
