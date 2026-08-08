$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sender = Join-Path $root 'send-command.ps1'
$pwsh = 'C:\Program Files\PowerShell\7\pwsh.exe'
$testParent = Join-Path $root 'test-artifacts'
$testRoot = Join-Path $testParent ('sender-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Write-Job([string]$Path, [object]$Value) {
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 8 -Compress), [Text.Encoding]::Unicode)
}

try {
    $jobPath = Join-Path $testRoot 'job.json'
    $statusPath = Join-Path $testRoot 'status.json'
    Write-Job $jobPath ([ordered]@{
        schemaVersion = 1; jobId = 'dryrun-main'; consoleMode = 'auto'; steps = @(
            [ordered]@{ stepId='a'; label='repeat'; command='giveitem c182'; repeat=3; source='test' },
            [ordered]@{ stepId='b'; label='toggle'; command='debug 3'; repeat=5; source='test' },
            [ordered]@{ stepId='c'; label='custom'; command='custom command'; repeat=9; source='test' }
        )
    })
    & $pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $sender -JobFile $jobPath -StatusFile $statusPath -DryRun
    Assert-True ($LASTEXITCODE -eq 0) 'DryRun sender failed.'
    $status = Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json
    Assert-True ($status.state -eq 'completed') 'DryRun did not complete.'
    Assert-True ($status.stepResults.Count -eq 3) 'Expected three step results.'
    Assert-True ($status.stepResults[0].submitted -eq 3) 'giveitem repeat count changed.'
    Assert-True ($status.stepResults[1].submitted -eq 1) 'debug must be limited to one.'
    Assert-True ($status.stepResults[2].submitted -eq 1) 'unknown commands must be limited to one.'
    Assert-True (-not (Test-Path -LiteralPath ($statusPath + '.tmp'))) 'Atomic status temporary file remained.'

    $legacyCommand = Join-Path $testRoot 'legacy.dat'
    $legacyStatus = Join-Path $testRoot 'legacy-status.json'
    [IO.File]::WriteAllText($legacyCommand, 'spawn 5.10.3', [Text.Encoding]::Unicode)
    & $pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $sender -CommandFile $legacyCommand -StatusFile $legacyStatus -RepeatCount 2 -DryRun
    $legacy = Get-Content -LiteralPath $legacyStatus -Raw | ConvertFrom-Json
    Assert-True ($legacy.state -eq 'completed' -and $legacy.stepResults[0].submitted -eq 2) 'Legacy parameters failed.'

    $cancelJob = Join-Path $testRoot 'cancel-job.json'
    $cancelStatus = Join-Path $testRoot 'cancel-status.json'
    $cancelFlag = Join-Path $testRoot 'cancel.flag'
    Write-Job $cancelJob ([ordered]@{
        schemaVersion = 1; jobId = 'dryrun-cancel'; consoleMode = 'auto'; steps = @(
            [ordered]@{ stepId='cancel'; label='cancel'; command='spawn 5.10.3'; repeat=20; source='test' },
            [ordered]@{ stepId='after'; label='after'; command='giveitem c182'; repeat=2; source='test' }
        )
    })
    $arguments = @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$sender,'-JobFile',$cancelJob,'-StatusFile',$cancelStatus,'-CancelFile',$cancelFlag,'-DryRun','-DryRunDelayMilliseconds','80')
    $process = Start-Process -FilePath $pwsh -ArgumentList $arguments -WindowStyle Hidden -PassThru
    Start-Sleep -Milliseconds 260
    [IO.File]::WriteAllText($cancelFlag, 'cancel', [Text.Encoding]::ASCII)
    $process.WaitForExit(10000) | Out-Null
    $cancelled = Get-Content -LiteralPath $cancelStatus -Raw | ConvertFrom-Json
    Assert-True ($cancelled.state -eq 'cancelled') 'Cancellation state was not returned.'
    Assert-True ($cancelled.canResume -eq $true) 'Cancelled job must be resumable.'
    Assert-True (@($cancelled.remainingSteps).Count -ge 1) 'Cancelled job lost remaining steps.'

    'sender protocol tests passed'
}
finally {
    $resolved = [IO.Path]::GetFullPath($testRoot)
    $safeParent = [IO.Path]::GetFullPath($testParent)
    if ($resolved.StartsWith($safeParent + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolved)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
