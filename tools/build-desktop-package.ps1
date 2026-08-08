param(
    [string]$OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist'),
    [string]$Version = 'desktop-v1.4.2'
)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$outputRootFull = [IO.Path]::GetFullPath($OutputRoot)
$package = Join-Path $outputRootFull ('isaac-chinese-console-' + $Version)
$archive = $package + '.zip'
$allowlist = @(
    'IsaacConsole.hta','send-command.ps1','import-eid-catalog.ps1','START.cmd','start-console.ps1','README.md','README-使用教程.md',
    '版本信息.txt','常见问题.txt','RELEASE-desktop-v1.4.2.md','环境检测.ps1','开启游戏控制台.cmd','启动以撒中文控制台.cmd','一键环境检测.cmd',
    'desktop\app.css','desktop\app.js','desktop\catalog.js','desktop\curated-aliases.js',
    'desktop\state.js','desktop\search.js','desktop\queue.js','desktop\generate-pinyin-aliases.ps1'
)

if ($package -eq $root -or -not $package.StartsWith($outputRootFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Unsafe package path.'
}
if (Test-Path -LiteralPath $package) { Remove-Item -LiteralPath $package -Recurse -Force }
if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
New-Item -ItemType Directory -Path $package | Out-Null
foreach ($relative in $allowlist) {
    $source = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Allowlisted file missing: $relative" }
    $destination = Join-Path $package $relative
    $parent = Split-Path -Parent $destination
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
    Copy-Item -LiteralPath $source -Destination $destination
}

$checksumLines = [Collections.Generic.List[string]]::new()
$files = Get-ChildItem -LiteralPath $package -Recurse -File | Sort-Object FullName
foreach ($file in $files) {
    $relative = $file.FullName.Substring($package.Length + 1).Replace('\','/')
    $checksumLines.Add(('{0} *{1}' -f (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash, $relative))
}
[IO.File]::WriteAllLines((Join-Path $package 'SHA256SUMS.txt'), $checksumLines, [Text.UTF8Encoding]::new($false))
Compress-Archive -LiteralPath $package -DestinationPath $archive -CompressionLevel Optimal
$allFiles = Get-ChildItem -LiteralPath $package -Recurse -File
$stats = [ordered]@{
    version = $Version
    fileCount = $allFiles.Count
    uncompressedBytes = ($allFiles | Measure-Object Length -Sum).Sum
    archiveBytes = (Get-Item -LiteralPath $archive).Length
    archiveSha256 = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
    packagePath = $package
    archivePath = $archive
}
$stats | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $outputRootFull ($Version + '-package-stats.json')) -Encoding utf8
$stats | ConvertTo-Json
