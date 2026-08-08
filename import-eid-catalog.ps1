param(
    [string]$EidPath,
    [Parameter(Mandatory = $true)][string]$OutputFile,
    [Parameter(Mandatory = $true)][string]$StatusFile
)

$ErrorActionPreference = 'Stop'

function Write-ImportStatus {
    param([bool]$Success, [string]$Code, [string]$Message, [hashtable]$Details = @{})
    $payload = [ordered]@{
        schemaVersion = 1
        success = $Success
        code = $Code
        message = $Message
        details = $Details
        timestamp = [DateTimeOffset]::Now.ToString('o')
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
    if (${env:ProgramFiles(x86)}) {
        Add-Candidate $candidates (Join-Path ${env:ProgramFiles(x86)} 'Steam\steamapps\workshop\content\250900\836319872')
        Add-Candidate $candidates (Join-Path ${env:ProgramFiles(x86)} 'Steam\steamapps\common\The Binding of Isaac Rebirth\mods\external item descriptions_836319872')
    }
    $steamRoots = [Collections.Generic.List[string]]::new()
    foreach ($key in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam')) {
        $props = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
        if ($props.SteamPath) { Add-Candidate $steamRoots $props.SteamPath }
        if ($props.InstallPath) { Add-Candidate $steamRoots $props.InstallPath }
    }
    foreach ($steamRoot in @($steamRoots)) {
        Add-Candidate $candidates (Join-Path $steamRoot 'steamapps\workshop\content\250900\836319872')
        Add-Candidate $candidates (Join-Path $steamRoot 'steamapps\common\The Binding of Isaac Rebirth\mods\external item descriptions_836319872')
        $libraries = Join-Path $steamRoot 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $libraries) {
            $text = Get-Content -LiteralPath $libraries -Raw
            foreach ($match in [regex]::Matches($text, '"path"\s+"([^"]+)"')) {
                $library = $match.Groups[1].Value.Replace('\\', '\')
                Add-Candidate $candidates (Join-Path $library 'steamapps\workshop\content\250900\836319872')
                Add-Candidate $candidates (Join-Path $library 'steamapps\common\The Binding of Isaac Rebirth\mods\external item descriptions_836319872')
            }
        }
    }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath (Join-Path $candidate 'descriptions\names\zh_cn.lua') -PathType Leaf) { return $candidate }
    }
    return $null
}

function Convert-LuaString {
    param([string]$Value)
    return $Value.Replace('\"', '"').Replace('\n', "`n").Replace('\r', '').Replace('\\', '\')
}

function Get-Names {
    param([string]$Path)
    $result = @{}
    $source = Get-Content -LiteralPath $Path -Raw -Encoding utf8
    foreach ($match in [regex]::Matches($source, '\[C_ID \.\. (\d+)\]\s*=\s*"((?:[^"\\]|\\.)*)"')) {
        $result[[int]$match.Groups[1].Value] = Convert-LuaString $match.Groups[2].Value
    }
    return $result
}

function Add-Descriptions {
    param([hashtable]$Descriptions, [string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $source = Get-Content -LiteralPath $Path -Raw -Encoding utf8
    $pattern = '\[(\d+)\]\s*=\s*\{\s*"\d+"\s*,\s*"(?:[^"\\]|\\.)*"\s*,\s*"((?:[^"\\]|\\.)*)"'
    foreach ($match in [regex]::Matches($source, $pattern)) {
        $value = Convert-LuaString $match.Groups[2].Value
        $value = [regex]::Replace($value, '\{\{[^}]+\}\}', '')
        $value = $value.Replace('#', '；').Trim()
        if ($value.Length -gt 600) { $value = $value.Substring(0, 600) + '…' }
        if ($value) { $Descriptions[[int]$match.Groups[1].Value] = $value }
    }
}

try {
    $root = Get-EidRoot
    if (-not $root) {
        Write-ImportStatus $false 'EID_NOT_FOUND' '没有找到本机 EID；可在界面中手动选择 EID 目录。'
        exit 2
    }
    $zhPath = Join-Path $root 'descriptions\names\zh_cn.lua'
    $enPath = Join-Path $root 'descriptions\names\en_us.lua'
    $zh = Get-Names $zhPath
    $en = Get-Names $enPath
    if ($zh.Count -lt 700 -or $en.Count -lt 700) { throw "EID_NAME_COUNT zh=$($zh.Count) en=$($en.Count)" }

    $descriptions = @{}
    foreach ($relative in @('descriptions\ab+\zh_cn.lua', 'descriptions\rep\zh_cn.lua', 'descriptions\rep+\zh_cn.lua')) {
        Add-Descriptions $descriptions (Join-Path $root $relative)
    }

    $aliases = @{}
    $pinyinAvailable = $false
    $aliasFile = Join-Path ([IO.Path]::GetTempPath()) ('isaac-cn-pinyin-' + [guid]::NewGuid().ToString('N') + '.lua')
    try {
        & (Join-Path $PSScriptRoot 'desktop\generate-pinyin-aliases.ps1') -NamesFile $zhPath -OutputFile $aliasFile *> $null
        $aliasSource = Get-Content -LiteralPath $aliasFile -Raw -Encoding utf8
        foreach ($match in [regex]::Matches($aliasSource, '\[(\d+)\]\s*=\s*"([^"]*)"')) {
            $aliases[[int]$match.Groups[1].Value] = $match.Groups[2].Value
        }
        $pinyinAvailable = $aliases.Count -ge 700
    }
    catch { $pinyinAvailable = $false }
    finally { Remove-Item -LiteralPath $aliasFile -Force -ErrorAction SilentlyContinue }

    $items = [Collections.Generic.List[object]]::new()
    foreach ($id in ($zh.Keys | Sort-Object)) {
        $parts = @(([string]$aliases[$id]) -split '\s+' | Where-Object { $_ })
        $items.Add([ordered]@{
            id = [int]$id
            name = [string]$zh[$id]
            en = [string]$en[$id]
            description = [string]$descriptions[$id]
            pinyin = if ($parts.Count -gt 0) { $parts[0] } else { '' }
            initials = if ($parts.Count -gt 1) { $parts[$parts.Count - 1] } else { '' }
            command = 'giveitem c' + $id
        })
    }
    $hashes = @($zhPath, $enPath | ForEach-Object { (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash })
    $cache = [ordered]@{
        schemaVersion = 1
        sourcePath = $root
        sourceHash = ($hashes -join ':')
        importedAt = [DateTimeOffset]::Now.ToString('o')
        itemCount = $items.Count
        pinyinAvailable = $pinyinAvailable
        items = @($items)
    } | ConvertTo-Json -Depth 6 -Compress
    $parent = Split-Path -Parent $OutputFile
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
    $temporary = $OutputFile + '.tmp'
    [IO.File]::WriteAllText($temporary, $cache, [Text.Encoding]::Unicode)
    Move-Item -LiteralPath $temporary -Destination $OutputFile -Force
    Write-ImportStatus $true 'IMPORTED' "已从本机 EID 导入 $($items.Count) 个道具。" @{
        sourcePath = $root
        sourceHash = ($hashes -join ':')
        itemCount = $items.Count
        pinyinAvailable = $pinyinAvailable
        outputFile = $OutputFile
    }
    exit 0
}
catch {
    Write-ImportStatus $false 'IMPORT_FAILED' $_.Exception.Message
    exit 1
}
