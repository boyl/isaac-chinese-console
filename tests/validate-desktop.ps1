param([string]$NodePath = 'C:\Users\lw\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe')

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$required = @(
    'IsaacConsole.hta','START.cmd','start-console.ps1','send-command.ps1','import-eid-catalog.ps1','desktop\app.css','desktop\app.js',
    'desktop\catalog.js','desktop\objects.js','desktop\state.js','desktop\search.js','desktop\queue.js'
)
foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relative) -PathType Leaf)) { throw "Missing required file: $relative" }
}

$startBytes = [IO.File]::ReadAllBytes((Join-Path $root 'START.cmd'))
if (@($startBytes | Where-Object { $_ -gt 127 }).Count -gt 0) { throw 'START.cmd must remain ASCII-only.' }
$startCmdText = [Text.Encoding]::ASCII.GetString($startBytes)
if ($startCmdText -notmatch 'WindowsPowerShell\\v1\.0\\powershell\.exe') { throw 'START.cmd does not use the fixed Windows PowerShell path.' }
$startScript = Get-Content -LiteralPath (Join-Path $root 'start-console.ps1') -Raw
foreach ($marker in @('PACKAGE_FILE_MISSING','VISIBLE_WINDOW_TIMEOUT','launcher-status.json','desktop-v1.5.0')) {
    if ($startScript -notmatch [regex]::Escape($marker)) { throw "Self-checking launcher marker missing: $marker" }
}

$hta = Get-Content -LiteralPath (Join-Path $root 'IsaacConsole.hta') -Raw
$loadedScripts = [regex]::Matches($hta, 'src="desktop/([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
$expectedScripts = @('catalog.js','objects.js','state.js','search.js','queue.js','app.js')
if (($loadedScripts -join '|') -ne ($expectedScripts -join '|')) { throw "Unexpected HTA script graph: $($loadedScripts -join ', ')" }

$errors = @()
Get-ChildItem -LiteralPath $root -Recurse -Filter '*.ps1' | ForEach-Object {
    $tokens = $null; $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) { $errors += "$($_.FullName): $($parseError.Message)" }
}
if ($errors.Count) { throw ($errors -join "`n") }

if (-not (Test-Path -LiteralPath $NodePath -PathType Leaf)) { throw "Bundled Node.js not found: $NodePath" }
Get-ChildItem -LiteralPath (Join-Path $root 'desktop') -Filter '*.js' | ForEach-Object {
    & $NodePath --check $_.FullName
    if ($LASTEXITCODE -ne 0) { throw "JavaScript syntax failed: $($_.Name)" }
}
Push-Location $root
try {
    foreach ($test in @('test-search.js','test-state.js','test-app-smoke.js','test-host-bridge.js')) {
        & $NodePath (Join-Path $root "tests\$test")
        if ($LASTEXITCODE -ne 0) { throw "Node test failed: $test" }
    }
    & (Join-Path $root 'tests\test-sender.ps1')
    & (Join-Path $root 'tests\test-eid-import.ps1')
    & (Join-Path $root 'tests\test-reachability.ps1')
}
finally { Pop-Location }

'desktop validation passed'
