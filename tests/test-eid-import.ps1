$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$importer = Join-Path $root 'import-eid-catalog.ps1'
$testParent = Join-Path $root 'test-artifacts'
$testRoot = Join-Path $testParent ('eid-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null

function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }

try {
    $missingStatus = Join-Path $testRoot 'missing-status.json'
    & $importer -EidPath (Join-Path $testRoot 'not-installed') -OutputFile (Join-Path $testRoot 'missing.json') -StatusFile $missingStatus -DisableAutoDiscovery
    Assert-True ($LASTEXITCODE -eq 2) 'Missing EID must return exit code 2.'
    $missing = Get-Content -LiteralPath $missingStatus -Raw -Encoding Unicode | ConvertFrom-Json
    Assert-True (-not $missing.success -and $missing.code -eq 'EID_NOT_FOUND') 'Missing EID degradation status changed.'
    Assert-True ($missing.message -match '1056') 'Missing EID status must explain that the built-in catalog remains available.'

    $eid = 'C:\Program Files (x86)\Steam\steamapps\common\The Binding of Isaac Rebirth\mods\external item descriptions_836319872'
    if (Test-Path -LiteralPath (Join-Path $eid 'descriptions\rep\zh_cn.lua') -PathType Leaf) {
        $cachePath = Join-Path $testRoot 'catalog-v2.json'
        $statusPath = Join-Path $testRoot 'status.json'
        & $importer -EidPath $eid -OutputFile $cachePath -StatusFile $statusPath -DisableAutoDiscovery
        Assert-True ($LASTEXITCODE -eq 0) 'Local EID description import failed.'
        $cache = Get-Content -LiteralPath $cachePath -Raw -Encoding Unicode | ConvertFrom-Json
        Assert-True ($cache.schemaVersion -eq 2 -and $cache.descriptionCount -eq 1056) 'EID description cache count changed.'
        $names = @($cache.descriptions.PSObject.Properties.Name)
        Assert-True (@($names -like 'c:*').Count -eq 721) 'EID collectible description count changed.'
        Assert-True (@($names -like 't:*').Count -eq 188) 'EID trinket description count changed.'
        Assert-True (@($names -like 'k:*').Count -eq 97) 'EID card description count changed.'
        Assert-True (@($names -like 'p:*').Count -eq 50) 'EID pill description count changed.'
    }
    'EID import tests passed'
}
finally {
    $resolved = [IO.Path]::GetFullPath($testRoot)
    $safeParent = [IO.Path]::GetFullPath($testParent)
    if ($resolved.StartsWith($safeParent + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolved)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
