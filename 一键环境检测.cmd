@echo off
chcp 65001 >nul
set "CHECKER=%~dp0环境检测.ps1"
if not exist "%CHECKER%" (
  echo [错误] 缺少 环境检测.ps1，请完整解压 ZIP。
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%CHECKER%"
pause
