[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$EidRoot,
    [Parameter(Mandatory = $true)][string]$ModRoot,
    [string]$OutputFile = (Join-Path (Split-Path -Parent $PSScriptRoot) 'desktop\objects.js')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Convert-LuaString {
    param([string]$Value)
    return $Value.Replace('\"', '"').Replace('\\', '\')
}

function Read-Names {
    param([string]$Path)
    $result = @{}
    $source = Get-Content -LiteralPath $Path -Raw -Encoding utf8
    $pattern = '\[(C_ID|T_ID|Card_ID|Pill_ID) \.\. (\d+)\]\s*=\s*"((?:[^"\\]|\\.)*)"'
    foreach ($match in [regex]::Matches($source, $pattern)) {
        $type = switch ($match.Groups[1].Value) {
            'C_ID' { 'c' }
            'T_ID' { 't' }
            'Card_ID' { 'k' }
            'Pill_ID' { 'p' }
        }
        $id = [int]$match.Groups[2].Value
        $value = Convert-LuaString $match.Groups[3].Value
        if ($value -and (($type -eq 'c' -and $id -ge 1 -and $id -le 732) -or
                ($type -eq 't' -and $id -ge 1 -and $id -le 189) -or
                ($type -eq 'k' -and $id -ge 1 -and $id -le 97) -or
                ($type -eq 'p' -and $id -ge 0 -and $id -le 49))) {
            $result["$type`:$id"] = $value
        }
    }
    return $result
}

function Read-Aliases {
    param([string]$CollectiblePath, [string]$ObjectPath)
    $result = @{}
    $source = Get-Content -LiteralPath $CollectiblePath -Raw -Encoding utf8
    foreach ($match in [regex]::Matches($source, '\[(\d+)\]\s*=\s*"([^"]*)"')) {
        $result['c:' + [int]$match.Groups[1].Value] = $match.Groups[2].Value
    }
    $source = Get-Content -LiteralPath $ObjectPath -Raw -Encoding utf8
    foreach ($match in [regex]::Matches($source, '\["([tkp]:\d+)"\]\s*=\s*"([^"]*)"')) {
        $result[$match.Groups[1].Value] = $match.Groups[2].Value
    }
    return $result
}

$zh = Read-Names (Join-Path $EidRoot 'descriptions\names\zh_cn.lua')
$en = Read-Names (Join-Path $EidRoot 'descriptions\names\en_us.lua')
$aliases = Read-Aliases (Join-Path $ModRoot 'scripts\pinyin_aliases.lua') (Join-Path $ModRoot 'scripts\object_pinyin_aliases.lua')
$expected = [ordered]@{ c = 721; t = 188; k = 97; p = 50 }
$rows = [Collections.Generic.List[object]]::new()

foreach ($type in @('c', 't', 'k', 'p')) {
    $keys = @($zh.Keys | Where-Object { $_ -like "$type`:*" } | Sort-Object { [int]($_ -split ':')[1] })
    if ($keys.Count -ne $expected[$type]) {
        throw "Unexpected $type count: $($keys.Count), expected $($expected[$type])"
    }
    foreach ($key in $keys) {
        if (-not $en.ContainsKey($key)) { throw "Missing English name: $key" }
        if (-not $aliases.ContainsKey($key)) { throw "Missing pinyin alias: $key" }
        $id = [int]($key -split ':')[1]
        $parts = @($aliases[$key] -split '\s+' | Where-Object { $_ })
        $pinyin = if ($parts.Count) { $parts[0] } else { '' }
        $initials = if ($parts.Count -gt 1) { $parts[-1] } else { $pinyin }
        if (-not $pinyin -and $key -eq 'p:31') { $pinyin = 'weizhi'; $initials = 'wz' }
        if (-not $pinyin -or -not $initials) { throw "Incomplete pinyin alias: $key" }
        $rows.Add(@($type, $id, $zh[$key], $en[$key], $pinyin, $initials))
    }
}

if ($rows.Count -ne 1056) { throw "Unexpected total count: $($rows.Count)" }
$json = ConvertTo-Json -InputObject @($rows) -Depth 3 -Compress
$content = "(function(root){`n  `"use strict`";`n  root.IsaacObjectRows=$json;`n}(window));`n"
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputFile), $content, [Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    output = [IO.Path]::GetFullPath($OutputFile)
    count = $rows.Count
    bytes = (Get-Item -LiteralPath $OutputFile).Length
} | ConvertTo-Json
