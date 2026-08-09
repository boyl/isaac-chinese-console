$ErrorActionPreference = 'Stop'
$appDir = [IO.Path]::GetFullPath($PSScriptRoot)
$htaPath = Join-Path $appDir 'IsaacConsole.hta'
$stateDir = Join-Path $env:LOCALAPPDATA 'IsaacChineseConsole'
$logPath = Join-Path $stateDir 'launcher.log'
$statusPath = Join-Path $stateDir 'launcher-status.json'

function Write-LauncherLog {
    param([string]$Message)
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Message
    Write-Host $line
    try { Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8 } catch {}
}

function Write-LauncherStatus {
    param([bool]$Success, [string]$Code, [string]$Message, [int]$ProcessId = 0)
    try {
        $json = [ordered]@{
            schemaVersion = 1
            success = $Success
            code = $Code
            message = $Message
            processId = $ProcessId
            timestamp = [DateTimeOffset]::Now.ToString('o')
        } | ConvertTo-Json -Compress
        $temporary = $statusPath + '.tmp'
        [IO.File]::WriteAllText($temporary, $json, [Text.Encoding]::Unicode)
        Move-Item -LiteralPath $temporary -Destination $statusPath -Force
    } catch {}
}

try {
    if (-not (Test-Path -LiteralPath $stateDir)) { New-Item -ItemType Directory -Path $stateDir | Out-Null }

    $required = @(
        'IsaacConsole.hta', 'send-command.ps1', 'import-eid-catalog.ps1',
        'desktop\app.css', 'desktop\app.js', 'desktop\catalog.js', 'desktop\objects.js',
        'desktop\state.js', 'desktop\search.js', 'desktop\queue.js'
    )
    foreach ($relative in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $appDir $relative) -PathType Leaf)) {
            throw "PACKAGE_FILE_MISSING: $relative"
        }
    }

    $mshtaPath = Join-Path $env:SystemRoot 'System32\mshta.exe'
    if (-not (Test-Path -LiteralPath $mshtaPath -PathType Leaf)) { throw 'MSHTA_NOT_FOUND' }

    Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class IsaacConsoleWindow {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClassName(IntPtr hWnd, StringBuilder text, int count);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool ShowWindowAsync(IntPtr hWnd, int command);

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr hWnd);

    public static IntPtr FindVisibleWindow(string titlePrefix) {
        IntPtr found = IntPtr.Zero;
        EnumWindows(delegate(IntPtr hWnd, IntPtr lParam) {
            if (!IsWindowVisible(hWnd)) return true;
            StringBuilder className = new StringBuilder(128);
            StringBuilder title = new StringBuilder(512);
            GetClassName(hWnd, className, className.Capacity);
            GetWindowText(hWnd, title, title.Capacity);
            if (className.ToString() == "HTML Application Host Window Class" &&
                title.ToString().StartsWith(titlePrefix, StringComparison.Ordinal)) {
                found = hWnd;
                return false;
            }
            return true;
        }, IntPtr.Zero);
        return found;
    }

    public static void RestoreAndForeground(IntPtr hWnd) {
        if (hWnd == IntPtr.Zero) return;
        ShowWindowAsync(hWnd, 9);
        SetForegroundWindow(hWnd);
    }
}
'@

    Write-LauncherLog ("准备启动：{0}" -f $htaPath)
    $argument = '"' + $htaPath.Replace('"', '""') + '"'
    $process = Start-Process -FilePath $mshtaPath -ArgumentList $argument -PassThru
    $deadline = (Get-Date).AddSeconds(10)
    $window = [IntPtr]::Zero
    do {
        Start-Sleep -Milliseconds 200
        $window = [IsaacConsoleWindow]::FindVisibleWindow('以撒 · 中文控制台 desktop-v1.5.1')
        if ($window -ne [IntPtr]::Zero) { break }
        $process.Refresh()
        if ($process.HasExited) { throw ("MSHTA_EXITED: {0}" -f $process.ExitCode) }
    } while ((Get-Date) -lt $deadline)

    if ($window -eq [IntPtr]::Zero) { throw 'VISIBLE_WINDOW_TIMEOUT' }
    [IsaacConsoleWindow]::RestoreAndForeground($window)
    Write-LauncherLog ("启动成功：PID {0}，可见窗口 {1}" -f $process.Id, $window)
    Write-LauncherStatus $true 'STARTED' '控制台可见窗口已创建。' $process.Id
    exit 0
}
catch {
    $message = $_.Exception.Message
    Write-LauncherLog ("启动失败：{0}" -f $message)
    Write-LauncherStatus $false 'START_FAILED' $message
    Write-Host ''
    Write-Host '无法启动以撒中文控制台。' -ForegroundColor Red
    Write-Host ("错误：{0}" -f $message) -ForegroundColor Yellow
    Write-Host ("日志：{0}" -f $logPath)
    Write-Host '请完整解压 ZIP 后，在文件资源管理器中双击 START.cmd。'
    exit 1
}
