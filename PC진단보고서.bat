@echo off
chcp 65001 >nul
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0PC진단보고서.ps1"
pause
