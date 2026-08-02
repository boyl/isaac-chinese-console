@echo off
chcp 65001 >nul
title 开启 Isaac 内置控制台
echo 本操作会把对应 options.ini 中的 EnableDebugConsole 改为 1。
echo 修改前会在同目录创建 options.ini.console-backup 备份。
echo 请先完全关闭游戏。
echo.
choice /c YN /n /m "是否继续？[Y/N] "
if errorlevel 2 exit /b 0
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$docs=[Environment]::GetFolderPath('MyDocuments'); $dirs=@('Binding of Isaac Repentance','Binding of Isaac Repentance+','Binding of Isaac Afterbirth+'); $changed=0; foreach($name in $dirs){$file=Join-Path $docs ('My Games\'+$name+'\options.ini'); if(Test-Path -LiteralPath $file){Copy-Item -LiteralPath $file -Destination ($file+'.console-backup') -Force; $text=[IO.File]::ReadAllText($file); if($text -match '(?m)^EnableDebugConsole='){ $text=[regex]::Replace($text,'(?m)^EnableDebugConsole=.*$','EnableDebugConsole=1') } else { $text=$text.TrimEnd()+[Environment]::NewLine+'EnableDebugConsole=1'+[Environment]::NewLine }; [IO.File]::WriteAllText($file,$text,[Text.Encoding]::UTF8); Write-Host ('[完成] '+$file) -ForegroundColor Green; $changed++ }}; if($changed -eq 0){Write-Host '[未找到] 请先启动一次游戏，再手动查看 README。' -ForegroundColor Yellow}"
echo.
pause
