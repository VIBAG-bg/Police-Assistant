@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0tools\pa-start.ps1" -Mode Monitor
exit /b %errorlevel%
