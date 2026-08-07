param([string]$NodePath = 'C:\Users\lw\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe')

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$required = @(
    'IsaacConsole.hta','send-command.ps1','import-eid-catalog.ps1','desktop\app.css','desktop\app.js',
    'desktop\catalog.js','desktop\curated-aliases.js','desktop\state.js','desktop\search.js','desktop\queue.js',
    'desktop\generate-pinyin-aliases.ps1'
)
foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relative) -PathType Leaf)) { throw "Missing required file: $relative" }
}

$hta = Get-Content -LiteralPath (Join-Path $root 'IsaacConsole.hta') -Raw
foreach ($script in @('catalog.js','curated-aliases.js','state.js','search.js','queue.js','app.js')) {
    if ($hta -notmatch [regex]::Escape("desktop/$script")) { throw "HTA does not load desktop/$script" }
}

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
    & $NodePath (Join-Path $root 'tests\test-search.js')
    if ($LASTEXITCODE -ne 0) { throw 'Search/catalog tests failed.' }
    & $NodePath (Join-Path $root 'tests\test-app-smoke.js')
    if ($LASTEXITCODE -ne 0) { throw 'App DOM smoke tests failed.' }
    & (Join-Path $root 'tests\test-sender.ps1')
}
finally { Pop-Location }

'desktop validation passed'
