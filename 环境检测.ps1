$ErrorActionPreference = 'SilentlyContinue'
$packageDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$lines = [System.Collections.Generic.List[string]]::new()

function Add-CheckLine {
    param([string]$State, [string]$Text)
    $line = "[$State] $Text"
    $null = $lines.Add($line)
    switch ($State) {
        '通过' { Write-Host $line -ForegroundColor Green }
        '警告' { Write-Host $line -ForegroundColor Yellow }
        default { Write-Host $line -ForegroundColor Red }
    }
}

Write-Host ''
Write-Host '以撒中文控制台 · 环境检测' -ForegroundColor Cyan
Write-Host '================================' -ForegroundColor DarkGray
$null = $lines.Add('以撒中文控制台 · 环境检测报告')
$null = $lines.Add(('生成时间：{0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
$null = $lines.Add('')

if ($PSVersionTable.PSVersion.Major -ge 5) {
    Add-CheckLine '通过' ("Windows PowerShell {0}" -f $PSVersionTable.PSVersion)
} else {
    Add-CheckLine '错误' '需要 Windows PowerShell 5.1 或更高版本。'
}

if (Get-Command mshta.exe -ErrorAction SilentlyContinue) {
    Add-CheckLine '通过' '已找到 Windows HTML Application 运行组件。'
} else {
    Add-CheckLine '错误' '找不到 mshta.exe，主界面无法启动。'
}

foreach ($required in @(
    'IsaacConsole.hta',
    'send-command.ps1',
    'import-eid-catalog.ps1',
    'desktop\app.css',
    'desktop\app.js',
    'desktop\catalog.js',
    'desktop\state.js',
    'desktop\search.js',
    'desktop\queue.js',
    'desktop\generate-pinyin-aliases.ps1',
    '启动以撒中文控制台.cmd'
)) {
    if (Test-Path -LiteralPath (Join-Path $packageDir $required)) {
        Add-CheckLine '通过' ("包内文件存在：{0}" -f $required)
    } else {
        Add-CheckLine '错误' ("包内文件缺失：{0}" -f $required)
    }
}

$stateDir = Join-Path $env:LOCALAPPDATA 'IsaacChineseConsole'
try {
    if (-not (Test-Path -LiteralPath $stateDir)) { New-Item -ItemType Directory -Path $stateDir | Out-Null }
    $probePath = Join-Path $stateDir '.write-test.tmp'
    [IO.File]::WriteAllText($probePath, 'ok', [Text.Encoding]::ASCII)
    Remove-Item -LiteralPath $probePath -Force
    Add-CheckLine '通过' ("用户状态目录可写：{0}" -f $stateDir)
}
catch {
    Add-CheckLine '错误' ("用户状态目录不可写：{0}" -f $stateDir)
}

$catalogCache = Join-Path $stateDir 'catalog-cache-v1.json'
if (Test-Path -LiteralPath $catalogCache) {
    try {
        $cache = Get-Content -LiteralPath $catalogCache -Raw | ConvertFrom-Json
        Add-CheckLine '通过' ("EID 离线目录缓存：{0} 项，拼音={1}" -f $cache.itemCount, $cache.pinyinAvailable)
    }
    catch { Add-CheckLine '警告' 'EID 离线目录缓存损坏，可在界面中重新导入。' }
}
else {
    Add-CheckLine '警告' '尚未导入 EID；控制台仍可使用 74 个精选道具。'
}

$isaac = Get-Process -Name 'isaac-ng', 'isaac-ng-x64', 'isaac' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($isaac) {
    if ($isaac.MainWindowHandle -ne [IntPtr]::Zero) {
        Add-CheckLine '通过' ("检测到游戏进程，PID {0}，窗口已就绪。" -f $isaac.Id)
    } else {
        Add-CheckLine '警告' '检测到游戏进程，但窗口尚未就绪；请进入一局后再发送命令。'
    }
} else {
    Add-CheckLine '警告' '当前未运行 Isaac；这不影响安装检查。'
}

$documents = [Environment]::GetFolderPath('MyDocuments')
$candidateDirs = @(
    (Join-Path $documents 'My Games\Binding of Isaac Repentance'),
    (Join-Path $documents 'My Games\Binding of Isaac Repentance+'),
    (Join-Path $documents 'My Games\Binding of Isaac Afterbirth+')
)
$foundOptions = $false
foreach ($dir in $candidateDirs) {
    $options = Join-Path $dir 'options.ini'
    if (Test-Path -LiteralPath $options) {
        $foundOptions = $true
        $setting = Get-Content -LiteralPath $options | Where-Object { $_ -match '^EnableDebugConsole=' } | Select-Object -First 1
        if ($setting -eq 'EnableDebugConsole=1') {
            Add-CheckLine '通过' ("控制台已开启：{0}" -f $options)
        } elseif ($setting) {
            Add-CheckLine '警告' ("控制台未开启（{0}）：{1}" -f $setting, $options)
        } else {
            Add-CheckLine '警告' ("options.ini 中没有 EnableDebugConsole：{0}" -f $options)
        }
    }
}
if (-not $foundOptions) {
    Add-CheckLine '警告' '未找到 options.ini。请至少启动一次游戏，或确认“文档”目录位置。'
}

$steamRoots = @()
foreach ($key in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam')) {
    $props = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
    if ($props.SteamPath) { $steamRoots += $props.SteamPath }
    if ($props.InstallPath) { $steamRoots += $props.InstallPath }
}
if ($steamRoots.Count -gt 0) {
    Add-CheckLine '通过' '已检测到 Steam 安装。'
} else {
    Add-CheckLine '警告' '注册表中未找到 Steam；便携版或自定义安装可忽略。'
}

$null = $lines.Add('')
$null = $lines.Add('结论：标为“错误”的项目必须修复；“警告”通常是游戏未启动或控制台尚未开启。')
$reportPath = Join-Path ([IO.Path]::GetTempPath()) 'Isaac中文控制台-环境检测报告.txt'
[IO.File]::WriteAllLines($reportPath, $lines, [Text.Encoding]::UTF8)
Write-Host ''
Write-Host ("检测报告已保存到：{0}" -f $reportPath) -ForegroundColor Cyan
Write-Host '按任意键返回；需要分享排障信息时，可发送该报告。' -ForegroundColor DarkGray
