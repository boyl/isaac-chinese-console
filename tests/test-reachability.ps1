$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

$desktopExpected = @('app.css','app.js','catalog.js','objects.js','queue.js','search.js','state.js')
$desktopActual = @(Get-ChildItem -LiteralPath (Join-Path $root 'desktop') -File | Sort-Object Name | ForEach-Object Name)
if (($desktopActual -join '|') -ne (($desktopExpected | Sort-Object) -join '|')) {
    throw "Orphan or missing desktop runtime file: $($desktopActual -join ', ')"
}

$forbidden = @(
    'desktop\curated-aliases.js','desktop\generate-pinyin-aliases.ps1','启动以撒中文控制台.cmd',
    'SHA256SUMS.txt','RELEASE-desktop-v1.4.2.md','RELEASE-desktop-v1.4.3.md'
)
foreach ($relative in $forbidden) {
    if (Test-Path -LiteralPath (Join-Path $root $relative)) { throw "Obsolete source artifact remains: $relative" }
}

$runtimeScripts = @('start-console.ps1','send-command.ps1','import-eid-catalog.ps1','环境检测.ps1')
foreach ($relative in $runtimeScripts) {
    $path = Join-Path $root $relative
    $tokens = $null; $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
    if (@($parseErrors).Count) { throw "PowerShell AST parse failed: $relative" }
    $definitions = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $true))
    $calls = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() } | Where-Object { $_ })
    foreach ($definition in $definitions) {
        if ($calls -notcontains $definition.Name) { throw "Unreferenced PowerShell function: $relative::$($definition.Name)" }
    }
}

$hta = Get-Content -LiteralPath (Join-Path $root 'IsaacConsole.hta') -Raw
$app = Get-Content -LiteralPath (Join-Path $root 'desktop\app.js') -Raw
foreach ($handler in @('selectCategory','setStageMode','changePage','openDetail','closeDrawers','openQueue','toggleFavorite','addEntry','sendEntry','adjustManualRepeat','addManualToQueue','sendManual','copyManual','moveStep','removeStep','updateStepRepeat','clearQueue','executeQueue','cancelQueue','dragStart','dragOver','dropStep','saveCurrentQueue','showHistory','showSavedQueues','closeModal','loadSavedQueue','deleteSavedQueue','importCatalog','detailFavorite','removeDetailItem','addDetailToQueue','sendDetail')) {
    if (($hta + $app) -notmatch [regex]::Escape('IsaacApp.' + $handler)) { throw "Unreachable exported HTA handler: $handler" }
}

if ($app -match 'MSIME|pinyinAvailable|generatePinyin|catalogOnly') { throw 'Removed runtime catalog/pinyin branch reappeared.' }
'reachability/orphan tests passed'
