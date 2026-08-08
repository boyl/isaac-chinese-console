@echo off
setlocal
set "LAUNCHER=%~dp0start-console.ps1"
set "WINDOWS_POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

if not exist "%LAUNCHER%" (
  echo [ERROR] Missing start-console.ps1. Extract the complete ZIP first.
  pause
  exit /b 2
)

if not exist "%WINDOWS_POWERSHELL%" (
  echo [ERROR] Windows PowerShell 5.1 was not found.
  pause
  exit /b 3
)

"%WINDOWS_POWERSHELL%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%LAUNCHER%"
set "START_EXIT=%ERRORLEVEL%"
if not "%START_EXIT%"=="0" pause
exit /b %START_EXIT%
