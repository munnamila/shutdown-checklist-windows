@echo off
setlocal
set "APP_SCRIPT=%~dp0ShutdownChecklist.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%APP_SCRIPT%"
if errorlevel 1 (
  echo.
  echo The program failed to start. Error code: %errorlevel%
  echo Please take a screenshot of this window.
  pause
)
endlocal


