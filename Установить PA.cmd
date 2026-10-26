@echo off
chcp 65001 >nul
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" -Interactive -FetchDependencies
if errorlevel 1 (
  echo.
  echo Установка остановлена. Прочитайте сообщение выше.
) else (
  echo.
  echo Police Assistant установлен. Теперь можно запустить игру и нажать F9.
)
pause
