@echo off
chcp 65001 >nul
title Boot Recovery Tool - Run from Windows RE / USB

echo.
echo =====================================================
echo   Windows Boot Recovery Tool
echo =====================================================
echo.
echo  [USB 부팅 후 이 파일 실행 방법]
echo  1. USB로 부팅
echo  2. "컴퓨터 복구" 클릭
echo  3. 문제 해결 - 고급 옵션 - 명령 프롬프트
echo  4. USB 드라이브 문자 확인:
echo       wmic logicaldisk get name,description
echo  5. USB가 E: 드라이브면:
echo       E:\PC_Optimizer\부팅복구_WinRE.bat
echo =====================================================
echo.
echo  [1] MBR + BCD 완전 복구  (부팅 안될때 1순위)
echo  [2] 시스템 파일 복구     (SFC - Windows 켜질때)
echo  [3] 디스크 오류 검사     (chkdsk)
echo  [4] 안전모드로 재부팅    (드라이버 문제 의심시)
echo  [5] 최근 업데이트 제거   (업데이트 후 부팅 안될때)
echo  [6] 시스템 복원          (복원 지점으로 되돌리기)
echo  [7] 전체 자동 복구       (1+2+3 순서대로 실행)
echo  [0] 종료
echo.
set /p choice=번호를 선택하세요: 

if "%choice%"=="1" goto :MBR_BCD
if "%choice%"=="2" goto :SFC
if "%choice%"=="3" goto :CHKDSK
if "%choice%"=="4" goto :SAFEMODE
if "%choice%"=="5" goto :REMOVE_UPDATE
if "%choice%"=="6" goto :RESTORE
if "%choice%"=="7" goto :AUTO_ALL
if "%choice%"=="0" goto :END
goto :END

:: ─────────────────────────────────────────────────────
:MBR_BCD
echo.
echo [MBR + BCD 복구 시작]
echo.
echo Step 1/4: MBR 복구...
bootrec /fixmbr
echo.
echo Step 2/4: Boot Sector 복구...
bootrec /fixboot
echo.
echo Step 3/4: OS 스캔...
bootrec /scanos
echo.
echo Step 4/4: BCD 재구성...
bootrec /rebuildbcd
echo.
echo [완료] 재부팅 후 확인하세요.
pause
goto :MENU_AGAIN

:: ─────────────────────────────────────────────────────
:SFC
echo.
echo [시스템 파일 복구 - Windows가 켜진 상태에서만 동작]
echo.
echo DISM 복구 중...
DISM /Online /Cleanup-Image /RestoreHealth
echo.
echo SFC 스캔 중...
sfc /scannow
echo.
echo [완료]
pause
goto :MENU_AGAIN

:: ─────────────────────────────────────────────────────
:CHKDSK
echo.
echo [디스크 오류 검사]
echo 주의: C 드라이브는 재부팅 후 검사됩니다.
echo.
chkdsk C: /f /r /x
echo.
echo [완료] 재부팅 후 자동으로 검사가 진행됩니다.
pause
goto :MENU_AGAIN

:: ─────────────────────────────────────────────────────
:SAFEMODE
echo.
echo [안전모드 재부팅 설정]
echo.
bcdedit /set {default} safeboot minimal
echo 안전모드가 설정되었습니다. 재부팅하면 안전모드로 진입합니다.
echo.
echo 안전모드 해제하려면: bcdedit /deletevalue {default} safeboot
echo.
set /p rb=지금 재부팅하시겠습니까? (Y/N): 
if /i "%rb%"=="Y" shutdown /r /t 3
pause
goto :MENU_AGAIN

:: ─────────────────────────────────────────────────────
:REMOVE_UPDATE
echo.
echo [최근 Windows 업데이트 제거]
echo.
echo 최근 설치된 업데이트 목록:
wmic qfe list brief /format:table | more
echo.
echo 업데이트 제거는 제어판 > 프로그램 > 설치된 업데이트에서 하거나
echo 아래 명령어를 사용하세요:
echo   wusa /uninstall /kb:XXXXXXX
echo.
echo 또는 Windows 복구 환경에서:
echo   [문제 해결] - [고급 옵션] - [업데이트 제거]
pause
goto :MENU_AGAIN

:: ─────────────────────────────────────────────────────
:RESTORE
echo.
echo [시스템 복원]
echo.
echo 복원 지점 목록:
vssadmin list shadows /for=C: 2>nul
echo.
echo GUI 복원 실행 중...
rstrui.exe
pause
goto :MENU_AGAIN

:: ─────────────────────────────────────────────────────
:AUTO_ALL
echo.
echo [전체 자동 복구 시작 - MBR + BCD + DISM + SFC + CHKDSK]
echo.
echo [1/5] MBR 복구...
bootrec /fixmbr
echo [2/5] Boot Sector 복구...
bootrec /fixboot
echo [3/5] BCD 재구성...
bootrec /rebuildbcd
echo [4/5] DISM 복구...
DISM /Online /Cleanup-Image /RestoreHealth
echo [5/5] SFC 스캔...
sfc /scannow
echo.
echo =====================================================
echo  전체 복구 완료! 재부팅 후 확인하세요.
echo =====================================================
pause
goto :MENU_AGAIN

:: ─────────────────────────────────────────────────────
:MENU_AGAIN
echo.
set /p again=메뉴로 돌아가시겠습니까? (Y/N): 
if /i "%again%"=="Y" (
    cls
    goto :eof
    call "%~f0"
)

:END
echo 종료합니다.
exit /b
