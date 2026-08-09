param(
    [string]$EidPath,
    [Parameter(Mandatory = $true)][string]$OutputFile,
    [Parameter(Mandatory = $true)][string]$StatusFile,
    [switch]$DisableAutoDiscovery
)

$ErrorActionPreference = 'Stop'

function Write-ImportStatus {
    param([bool]$Success, [string]$Code, [string]$Message, [hashtable]$Details = @{})
    $payload = [ordered]@{
        schemaVersion = 2; success = $Success; code = $Code; message = $Message
        details = $Details; timestamp = [DateTimeOffset]::Now.ToString('o')
    } | ConvertTo-Json -Depth 6 -Compress
    $temporary = $StatusFile + '.tmp'
    [IO.File]::WriteAllText($temporary, $payload, [Text.Encoding]::Unicode)
    Move-Item -LiteralPath $temporary -Destination $StatusFile -Force
}

function Add-Candidate {
    param([Collections.Generic.List[string]]$List, [string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    try { $full = [IO.Path]::GetFullPath($Path) } catch { return }
    if (-not $List.Contains($full)) { $List.Add($full) }
}

function Get-EidRoot {
    $candidates = [Collections.Generic.List[string]]::new()
    Add-Candidate $candidates $EidPath
    if ($DisableAutoDiscovery) {
        foreach ($candidate in $candidates) {
            if (Test-Path -LiteralPath (Join-Path $candidate 'descriptions\rep\zh_cn.lua') -PathType Leaf) { return $candidate }
        }
        return $null
    }
    $steamRoots = [Collections.Generic.List[string]]::new()
    if (${env:ProgramFiles(x86)}) { Add-Candidate $steamRoots (Join-Path ${env:ProgramFiles(x86)} 'Steam') }
    foreach ($key in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam')) {
        $properties = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
        if ($properties.SteamPath) { Add-Candidate $steamRoots $properties.SteamPath }
        if ($properties.InstallPath) { Add-Candidate $steamRoots $properties.InstallPath }
    }
    foreach ($steamRoot in @($steamRoots)) {
        Add-Candidate $candidates (Join-Path $steamRoot 'steamapps\workshop\content\250900\836319872')
        Add-Candidate $candidates (Join-Path $steamRoot 'steamapps\common\The Binding of Isaac Rebirth\mods\external item descriptions_836319872')
        $libraries = Join-Path $steamRoot 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $libraries) {
            $source = Get-Content -LiteralPath $libraries -Raw
            foreach ($match in [regex]::Matches($source, '"path"\s+"([^"]+)"')) {
                $library = $match.Groups[1].Value.Replace('\\', '\')
                Add-Candidate $candidates (Join-Path $library 'steamapps\workshop\content\250900\836319872')
                Add-Candidate $candidates (Join-Path $library 'steamapps\common\The Binding of Isaac Rebirth\mods\external item descriptions_836319872')
            }
        }
    }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath (Join-Path $candidate 'descriptions\rep\zh_cn.lua') -PathType Leaf) { return $candidate }
    }
    return $null
}

function Convert-LuaString {
    param([string]$Value)
    return $Value.Replace('\"', '"').Replace('\n', "`n").Replace('\r', '').Replace('\\', '\')
}

function Test-ObjectId {
    param([string]$Type, [int]$Id)
    if ($Type -eq 'c') { return $Id -ge 1 -and $Id -le 732 -and $Id -notin @(43,61,235,587,613,620,630,648,662,666,718) }
    if ($Type -eq 't') { return $Id -ge 1 -and $Id -le 189 -and $Id -ne 47 }
    if ($Type -eq 'k') { return $Id -ge 1 -and $Id -le 97 }
    if ($Type -eq 'p') { return $Id -ge 0 -and $Id -le 49 }
    return $false
}

function Convert-Description {
    param([string]$Value)
    $value = Convert-LuaString $Value
    $value = [regex]::Replace($value, '\{\{([^}|]+)(?:\|[^}]*)?\}\}', {
        param($match)
        $words = @{ Heart='红心'; SoulHeart='魂心'; BlackHeart='黑心'; Coin='硬币'; Bomb='炸弹'; Key='钥匙'; Damage='伤害'; Tears='射速'; Range='射程'; Speed='移速'; Shotspeed='弹速'; Luck='幸运'; Flight='飞行'; Battery='电池'; Card='卡牌'; Rune='符文'; Pill='胶囊'; Poison='中毒'; Slow='减速' }
        if ($words.ContainsKey($match.Groups[1].Value)) { return $words[$match.Groups[1].Value] }
        return ''
    })
    $value = $value.Replace('#', '；')
    $value = [regex]::Replace($value, '\s*；\s*', '；')
    $value = [regex]::Replace($value, '；+', '；').Trim('；', ' ')
    if ($value.Length -gt 600) { $value = $value.Substring(0, 600) + '…' }
    return $value
}

function Add-DescriptionFile {
    param([hashtable]$Descriptions, [string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $source = Get-Content -LiteralPath $Path -Raw -Encoding utf8

    # The AB+ language file owns the complete base tables and stores rows as
    # { "id", "name", "description" }. Later files contain keyed override
    # tables. Parse the base form first so the override files can replace it.
    $basePattern = 'EID\.descriptions\[languageCode\]\.(collectibles|trinkets|cards|pills)\s*=\s*\{([\s\S]*?)(?:\r?\n)\}'
    foreach ($table in [regex]::Matches($source, $basePattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
        $type = switch ($table.Groups[1].Value.ToLowerInvariant()) {
            'collectibles' { 'c' }; 'trinkets' { 't' }; 'cards' { 'k' }; 'pills' { 'p' }
        }
        $entryPattern = '\{\s*"(\d+)"\s*,\s*"(?:[^"\\]|\\.)*"\s*,\s*"((?:[^"\\]|\\.)*)"'
        foreach ($entry in [regex]::Matches($table.Groups[2].Value, $entryPattern)) {
            $id = [int]$entry.Groups[1].Value
            if (-not (Test-ObjectId $type $id)) { continue }
            $description = Convert-Description $entry.Groups[2].Value
            if ($description) { $Descriptions["$type`:$id"] = $description }
        }
    }

    $tablePattern = 'local\s+\w*(Collectibles|Trinkets|Cards|Pills)\s*=\s*\{([\s\S]*?)\}\s*EID:updateDescriptionsViaTable'
    foreach ($table in [regex]::Matches($source, $tablePattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
        $type = switch ($table.Groups[1].Value.ToLowerInvariant()) {
            'collectibles' { 'c' }; 'trinkets' { 't' }; 'cards' { 'k' }; 'pills' { 'p' }
        }
        $entryPattern = '\[\d+\]\s*=\s*\{\s*"(\d*)"\s*,\s*"(?:[^"\\]|\\.)*"\s*,\s*"((?:[^"\\]|\\.)*)"'
        foreach ($entry in [regex]::Matches($table.Groups[2].Value, $entryPattern)) {
            if (-not $entry.Groups[1].Value) { continue }
            $id = [int]$entry.Groups[1].Value
            if (-not (Test-ObjectId $type $id)) { continue }
            $description = Convert-Description $entry.Groups[2].Value
            if ($description) { $Descriptions["$type`:$id"] = $description }
        }
    }
}

try {
    $root = Get-EidRoot
    if (-not $root) {
        Write-ImportStatus $false 'EID_NOT_FOUND' '没有找到本机 EID；内置 1056 项目录仍可完整使用。'
        exit 2
    }
    $relativeFiles = @(
        'descriptions\ab+\zh_cn.lua',
        'descriptions\rep\zh_cn.lua',
        'descriptions\rep+\zh_cn.lua'
    )
    $descriptions = @{}
    foreach ($relative in $relativeFiles) { Add-DescriptionFile $descriptions (Join-Path $root $relative) }
    if ($descriptions.Count -lt 1000) { throw "EID_DESCRIPTION_COUNT=$($descriptions.Count)" }
    $hashes = foreach ($relative in $relativeFiles) {
        $path = Join-Path $root $relative
        if (Test-Path -LiteralPath $path) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
    }
    $cache = [ordered]@{
        schemaVersion = 2; sourcePath = $root; sourceHash = ($hashes -join ':')
        importedAt = [DateTimeOffset]::Now.ToString('o'); descriptionCount = $descriptions.Count
        descriptions = $descriptions
    } | ConvertTo-Json -Depth 5 -Compress
    $parent = Split-Path -Parent $OutputFile
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
    $temporary = $OutputFile + '.tmp'
    [IO.File]::WriteAllText($temporary, $cache, [Text.Encoding]::Unicode)
    if (Test-Path -LiteralPath $OutputFile -PathType Leaf) {
        Copy-Item -LiteralPath $OutputFile -Destination ($OutputFile + '.bak') -Force
    }
    Move-Item -LiteralPath $temporary -Destination $OutputFile -Force
    $details = @{ sourcePath=$root; sourceHash=($hashes -join ':'); importedAt=[DateTimeOffset]::Now.ToString('o'); descriptionCount=$descriptions.Count; outputFile=$OutputFile }
    Write-ImportStatus $true 'IMPORTED' "已为内置目录补充 $($descriptions.Count) 条 EID 说明。" $details
    exit 0
}
catch {
    Write-ImportStatus $false 'IMPORT_FAILED' $_.Exception.Message
    exit 1
}
