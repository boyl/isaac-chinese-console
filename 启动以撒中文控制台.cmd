@echo off
setlocal
chcp 65001 >nul
title 以撒中文控制台 - 启动器

set "APP_DIR=%~dp0"
set "ISAAC_UI=%APP_DIR%IsaacConsole.hta"
set "ISAAC_HELPER=%APP_DIR%send-command.ps1"

where mshta.exe >nul 2>nul
if errorlevel 1 (
  echo [错误] 当前 Windows 中找不到 mshta.exe，无法显示控制台界面。
  echo 请查看 README-使用教程.md 的“常见问题”。
  pause
  exit /b 2
)

where powershell.exe >nul 2>nul
if errorlevel 1 (
  echo [错误] 当前 Windows 中找不到 Windows PowerShell，无法发送命令。
  pause
  exit /b 3
)

if not exist "%ISAAC_UI%" (
  echo [错误] 缺少 IsaacConsole.hta。
  echo 请完整解压 ZIP，不要只单独运行启动器。
  pause
  exit /b 4
)

if not exist "%ISAAC_HELPER%" (
  echo [错误] 缺少 send-command.ps1。
  echo 请完整解压 ZIP；安全软件隔离脚本时请恢复该文件。
  pause
  exit /b 5
)

start "" "%SystemRoot%\System32\mshta.exe" "%ISAAC_UI%"
exit /b 0
