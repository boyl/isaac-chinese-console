param(
    [string]$CommandFile,
    [string]$JobFile,
    [Parameter(Mandatory = $true)][string]$StatusFile,
    [string]$CancelFile,
    [switch]$ProbeOnly,
    [switch]$ConsoleAlreadyOpen,
    [int]$RepeatCount = 1,
    [switch]$DryRun,
    [int]$DryRunDelayMilliseconds = 0
)

$ErrorActionPreference = 'Stop'
$script:JobId = ''
$script:StepResults = [System.Collections.ArrayList]::new()
$script:NormalizedSteps = @()

function Write-JsonStatus {
    param(
        [Parameter(Mandatory = $true)][string]$State,
        [int]$CurrentStep = 0,
        [int]$StepCount = 0,
        [int]$RepeatDone = 0,
        [int]$RepeatTotal = 0,
        [string]$ErrorCode = '',
        [bool]$CanResume = $false,
        [object[]]$RemainingSteps = @()
    )
    $payload = [ordered]@{
        schemaVersion = 1
        jobId = $script:JobId
        state = $State
        currentStep = $CurrentStep
        stepCount = $StepCount
        repeatDone = $RepeatDone
        repeatTotal = $RepeatTotal
        submittedSteps = @($script:StepResults | Where-Object { $_.state -eq 'submitted' }).Count
        errorCode = $ErrorCode
        canResume = $CanResume
        stepResults = @($script:StepResults)
        remainingSteps = @($RemainingSteps)
        timestamp = [DateTimeOffset]::Now.ToString('o')
    }
    $json = $payload | ConvertTo-Json -Depth 8 -Compress
    $temporary = $StatusFile + '.tmp'
    [IO.File]::WriteAllText($temporary, $json, [Text.Encoding]::Unicode)
    Move-Item -LiteralPath $temporary -Destination $StatusFile -Force
}

function Test-Cancelled {
    return -not [string]::IsNullOrWhiteSpace($CancelFile) -and (Test-Path -LiteralPath $CancelFile)
}

function Get-RemainingSteps {
    param([int]$StepIndex, [int]$SubmittedInStep)
    $remaining = [Collections.Generic.List[object]]::new()
    for ($index = $StepIndex; $index -lt $script:NormalizedSteps.Count; $index++) {
        $step = $script:NormalizedSteps[$index]
        $repeat = [int]$step.repeat
        if ($index -eq $StepIndex) { $repeat = [Math]::Max(0, $repeat - $SubmittedInStep) }
        if ($repeat -gt 0) {
            $remaining.Add([ordered]@{
                stepId = [string]$step.stepId
                label = [string]$step.label
                command = [string]$step.command
                repeat = $repeat
                source = [string]$step.source
            })
        }
    }
    return @($remaining)
}

function Add-StepResult {
    param([object]$Step, [int]$Requested, [int]$Submitted, [string]$State, [string]$Note)
    $null = $script:StepResults.Add([ordered]@{
        stepId = [string]$Step.stepId
        label = [string]$Step.label
        command = [string]$Step.command
        requested = $Requested
        submitted = $Submitted
        state = $State
        note = $Note
    })
}

try {
    if ($ProbeOnly) {
        $script:JobId = 'probe'
        $probe = Get-Process -Name 'isaac-ng', 'isaac-ng-x64', 'isaac' -ErrorAction SilentlyContinue | Select-Object -First 1
        $payload = [ordered]@{
            schemaVersion = 1
            jobId = 'probe'
            state = 'completed'
            running = [bool]$probe
            processId = if ($probe) { $probe.Id } else { 0 }
            timestamp = [DateTimeOffset]::Now.ToString('o')
        } | ConvertTo-Json -Compress
        $temporary = $StatusFile + '.tmp'
        [IO.File]::WriteAllText($temporary, $payload, [Text.Encoding]::Unicode)
        Move-Item -LiteralPath $temporary -Destination $StatusFile -Force
        exit 0
    }

    $rawJob = $null
    if (-not [string]::IsNullOrWhiteSpace($JobFile)) {
        if (-not (Test-Path -LiteralPath $JobFile -PathType Leaf)) { throw 'JOB_FILE' }
        $rawJob = Get-Content -LiteralPath $JobFile -Raw | ConvertFrom-Json
        if ([int]$rawJob.schemaVersion -ne 1) { throw 'JOB_SCHEMA' }
        $script:JobId = [string]$rawJob.jobId
        if ([string]::IsNullOrWhiteSpace($script:JobId)) { throw 'JOB_ID' }
        $ConsoleAlreadyOpen = [string]$rawJob.consoleMode -eq 'open'
        $rawSteps = @($rawJob.steps)
    }
    else {
        if ([string]::IsNullOrWhiteSpace($CommandFile) -or -not (Test-Path -LiteralPath $CommandFile -PathType Leaf)) { throw 'COMMAND_FILE' }
        $legacyCommand = (Get-Content -LiteralPath $CommandFile -Raw -Encoding Unicode).Trim()
        $script:JobId = 'legacy-' + [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
        $rawSteps = @([pscustomobject]@{
            stepId = 'legacy-step'
            label = '旧版单命令'
            command = $legacyCommand
            repeat = $RepeatCount
            source = 'legacy'
        })
    }

    if ($rawSteps.Count -lt 1 -or $rawSteps.Count -gt 200) { throw 'STEP_COUNT' }
    $normalized = [Collections.Generic.List[object]]::new()
    foreach ($step in $rawSteps) {
        $command = ([string]$step.command).Trim()
        if ([string]::IsNullOrWhiteSpace($command) -or $command.Length -gt 500 -or $command -match '[\r\n]') { throw 'INVALID_COMMAND' }
        $requested = 1
        if ($null -ne $step.repeat) { $requested = [int]$step.repeat }
        if ($requested -lt 1 -or $requested -gt 99) { throw 'REPEAT_RANGE' }
        $repeat = $requested
        $limited = $false
        $singleObject = $command -match '^giveitem\s+[tkp]\d+\s*$'
        if ($repeat -gt 1 -and ($singleObject -or $command -notmatch '^(giveitem|spawn)\s+')) { $repeat = 1; $limited = $true }
        $normalized.Add([pscustomobject]@{
            stepId = if ([string]::IsNullOrWhiteSpace([string]$step.stepId)) { 'step-' + $normalized.Count } else { [string]$step.stepId }
            label = if ([string]::IsNullOrWhiteSpace([string]$step.label)) { $command } else { ([string]$step.label).Substring(0, [Math]::Min(120, ([string]$step.label).Length)) }
            command = $command
            repeat = $repeat
            requested = $requested
            repeatLimited = $limited
            source = [string]$step.source
        })
    }
    $script:NormalizedSteps = @($normalized)
    Write-JsonStatus -State 'running' -StepCount $script:NormalizedSteps.Count

    if ($DryRun) {
        for ($stepIndex = 0; $stepIndex -lt $script:NormalizedSteps.Count; $stepIndex++) {
            $step = $script:NormalizedSteps[$stepIndex]
            $submitted = 0
            for ($iteration = 1; $iteration -le [int]$step.repeat; $iteration++) {
                if (Test-Cancelled) {
                    if ($submitted -gt 0) { Add-StepResult $step ([int]$step.repeat) $submitted 'partial' 'DryRun cancelled' }
                    $remaining = Get-RemainingSteps $stepIndex $submitted
                    Write-JsonStatus -State 'cancelled' -CurrentStep ($stepIndex + 1) -StepCount $script:NormalizedSteps.Count -RepeatDone $submitted -RepeatTotal ([int]$step.repeat) -ErrorCode 'CANCELLED' -CanResume ($remaining.Count -gt 0) -RemainingSteps $remaining
                    exit 0
                }
                if ($DryRunDelayMilliseconds -gt 0) { Start-Sleep -Milliseconds $DryRunDelayMilliseconds }
                $submitted++
                Write-JsonStatus -State 'running' -CurrentStep ($stepIndex + 1) -StepCount $script:NormalizedSteps.Count -RepeatDone $submitted -RepeatTotal ([int]$step.repeat)
            }
            Add-StepResult $step ([int]$step.repeat) $submitted 'submitted' $(if ($step.repeatLimited) { 'Repeat limited to one' } else { 'DryRun submitted' })
        }
        Write-JsonStatus -State 'completed' -CurrentStep $script:NormalizedSteps.Count -StepCount $script:NormalizedSteps.Count
        exit 0
    }

    $isaac = Get-Process -Name 'isaac-ng', 'isaac-ng-x64', 'isaac' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $isaac) {
        Write-JsonStatus -State 'failed' -StepCount $script:NormalizedSteps.Count -ErrorCode 'NO_GAME' -CanResume $true -RemainingSteps $script:NormalizedSteps
        exit 2
    }

    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Threading;

public static class IsaacInput {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern bool BringWindowToTop(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern IntPtr SetActiveWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern IntPtr SetFocus(IntPtr hWnd);

    [DllImport("kernel32.dll")]
    public static extern uint GetCurrentThreadId();

    [DllImport("user32.dll")]
    public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool attach);

    [DllImport("user32.dll")]
    public static extern short VkKeyScan(char ch);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    [StructLayout(LayoutKind.Sequential)]
    public struct INPUT {
        public uint type;
        public InputUnion U;
    }

    [StructLayout(LayoutKind.Explicit)]
    public struct InputUnion {
        [FieldOffset(0)] public KEYBDINPUT ki;
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public HARDWAREINPUT hi;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct KEYBDINPUT {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public UIntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MOUSEINPUT {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public UIntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct HARDWAREINPUT {
        public uint uMsg;
        public ushort wParamL;
        public ushort wParamH;
    }

    private const uint INPUT_KEYBOARD = 1;
    private const uint KEYEVENTF_KEYUP = 0x0002;
    private const uint KEYEVENTF_SCANCODE = 0x0008;
    private const byte VK_SHIFT = 0x10;
    private const byte VK_CONTROL = 0x11;
    private const byte VK_MENU = 0x12;
    private const byte VK_A = 0x41;
    private const byte VK_BACK = 0x08;

    public static IntPtr FindWindowForProcess(uint targetProcessId) {
        IntPtr visible = IntPtr.Zero;
        IntPtr fallback = IntPtr.Zero;
        EnumWindows(delegate(IntPtr hWnd, IntPtr lParam) {
            uint processId;
            GetWindowThreadProcessId(hWnd, out processId);
            if (processId == targetProcessId) {
                if (fallback == IntPtr.Zero) fallback = hWnd;
                if (IsWindowVisible(hWnd)) {
                    visible = hWnd;
                    return false;
                }
            }
            return true;
        }, IntPtr.Zero);
        return visible != IntPtr.Zero ? visible : fallback;
    }

    public static void TapKey(byte virtualKey) {
        keybd_event(virtualKey, 0, 0, UIntPtr.Zero);
        keybd_event(virtualKey, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
    }

    public static bool TapScanCode(ushort scanCode) {
        INPUT down = new INPUT();
        down.type = INPUT_KEYBOARD;
        down.U.ki.wVk = 0;
        down.U.ki.wScan = scanCode;
        down.U.ki.dwFlags = KEYEVENTF_SCANCODE;
        INPUT up = down;
        up.U.ki.dwFlags = KEYEVENTF_SCANCODE | KEYEVENTF_KEYUP;
        INPUT[] pair = new INPUT[] { down, up };
        return SendInput((uint)pair.Length, pair, Marshal.SizeOf(typeof(INPUT))) == pair.Length;
    }

    public static bool IsForegroundProcess(uint targetProcessId) {
        IntPtr foreground = GetForegroundWindow();
        if (foreground == IntPtr.Zero) return false;
        uint processId;
        GetWindowThreadProcessId(foreground, out processId);
        return processId == targetProcessId;
    }

    public static bool ForceForeground(IntPtr hWnd, uint targetProcessId) {
        if (hWnd == IntPtr.Zero) return false;
        ShowWindowAsync(hWnd, 9);
        IntPtr foreground = GetForegroundWindow();
        uint foregroundProcess;
        uint foregroundThread = foreground == IntPtr.Zero ? 0 : GetWindowThreadProcessId(foreground, out foregroundProcess);
        uint targetProcess;
        uint targetThread = GetWindowThreadProcessId(hWnd, out targetProcess);
        uint currentThread = GetCurrentThreadId();
        bool attachedCurrent = targetThread != 0 && AttachThreadInput(currentThread, targetThread, true);
        bool attachedForeground = foregroundThread != 0 && targetThread != 0 && foregroundThread != targetThread && AttachThreadInput(foregroundThread, targetThread, true);
        BringWindowToTop(hWnd);
        SetForegroundWindow(hWnd);
        SetActiveWindow(hWnd);
        SetFocus(hWnd);
        if (attachedForeground) AttachThreadInput(foregroundThread, targetThread, false);
        if (attachedCurrent) AttachThreadInput(currentThread, targetThread, false);
        Thread.Sleep(120);
        return IsForegroundProcess(targetProcessId);
    }

    public static bool SendVirtualText(string text) {
        foreach (char ch in text) {
            short mapped = VkKeyScan(ch);
            if (mapped == -1) return false;
            byte key = (byte)(mapped & 0xff);
            byte modifiers = (byte)((mapped >> 8) & 0xff);
            if ((modifiers & 1) != 0) keybd_event(VK_SHIFT, 0, 0, UIntPtr.Zero);
            if ((modifiers & 2) != 0) keybd_event(VK_CONTROL, 0, 0, UIntPtr.Zero);
            if ((modifiers & 4) != 0) keybd_event(VK_MENU, 0, 0, UIntPtr.Zero);
            TapKey(key);
            if ((modifiers & 4) != 0) keybd_event(VK_MENU, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
            if ((modifiers & 2) != 0) keybd_event(VK_CONTROL, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
            if ((modifiers & 1) != 0) keybd_event(VK_SHIFT, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
            Thread.Sleep(5);
        }
        return true;
    }

    public static void ClearConsoleLine() {
        // The physical console hotkey can also leave a literal ` in the edit
        // line on some layouts. Select everything and clear it before typing.
        keybd_event(VK_CONTROL, 0, 0, UIntPtr.Zero);
        TapKey(VK_A);
        keybd_event(VK_CONTROL, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
        Thread.Sleep(45);
        TapKey(VK_BACK);
        Thread.Sleep(80);
    }
}
'@

    $gameWindow = [IsaacInput]::FindWindowForProcess([uint32]$isaac.Id)
    $focused = $false
    if ($gameWindow -ne [IntPtr]::Zero) { $focused = [IsaacInput]::ForceForeground($gameWindow, [uint32]$isaac.Id) }
    if (-not $focused) {
        try {
            $wshell = New-Object -ComObject WScript.Shell
            $null = $wshell.AppActivate($isaac.Id)
            Start-Sleep -Milliseconds 220
            $focused = [IsaacInput]::IsForegroundProcess([uint32]$isaac.Id)
        } catch { $focused = $false }
    }
    if (-not $focused) {
        $code = if ($gameWindow -eq [IntPtr]::Zero) { 'NO_WINDOW' } else { 'FOCUS_FAILED' }
        Write-JsonStatus -State 'failed' -StepCount $script:NormalizedSteps.Count -ErrorCode $code -CanResume $true -RemainingSteps $script:NormalizedSteps
        exit 6
    }
    Start-Sleep -Milliseconds 320

    if (-not $ConsoleAlreadyOpen) {
        if (-not [IsaacInput]::TapScanCode(0x29)) {
            Write-JsonStatus -State 'failed' -StepCount $script:NormalizedSteps.Count -ErrorCode 'INPUT_BLOCKED' -CanResume $true -RemainingSteps $script:NormalizedSteps
            exit 7
        }
        Start-Sleep -Milliseconds 480
    }
    [IsaacInput]::ClearConsoleLine()

    for ($stepIndex = 0; $stepIndex -lt $script:NormalizedSteps.Count; $stepIndex++) {
        $step = $script:NormalizedSteps[$stepIndex]
        $submitted = 0
        if ($stepIndex -gt 0) { [IsaacInput]::ClearConsoleLine() }
        for ($iteration = 1; $iteration -le [int]$step.repeat; $iteration++) {
            if (Test-Cancelled) {
                if ([IsaacInput]::IsForegroundProcess([uint32]$isaac.Id)) { [IsaacInput]::TapScanCode(0x01) | Out-Null }
                if ($submitted -gt 0) { Add-StepResult $step ([int]$step.repeat) $submitted 'partial' '用户取消' }
                $remaining = Get-RemainingSteps $stepIndex $submitted
                Write-JsonStatus -State 'cancelled' -CurrentStep ($stepIndex + 1) -StepCount $script:NormalizedSteps.Count -RepeatDone $submitted -RepeatTotal ([int]$step.repeat) -ErrorCode 'CANCELLED' -CanResume ($remaining.Count -gt 0) -RemainingSteps $remaining
                exit 0
            }
            if (-not [IsaacInput]::IsForegroundProcess([uint32]$isaac.Id)) {
                if ($submitted -gt 0) { Add-StepResult $step ([int]$step.repeat) $submitted 'partial' '游戏失去焦点' }
                $remaining = Get-RemainingSteps $stepIndex $submitted
                Write-JsonStatus -State $(if ($script:StepResults.Count -gt 0 -or $submitted -gt 0) { 'partial' } else { 'failed' }) -CurrentStep ($stepIndex + 1) -StepCount $script:NormalizedSteps.Count -RepeatDone $submitted -RepeatTotal ([int]$step.repeat) -ErrorCode 'FOCUS_LOST' -CanResume $true -RemainingSteps $remaining
                exit 8
            }
            if (-not [IsaacInput]::SendVirtualText([string]$step.command)) {
                [IsaacInput]::TapScanCode(0x01) | Out-Null
                if ($submitted -gt 0) { Add-StepResult $step ([int]$step.repeat) $submitted 'partial' '输入被拦截' }
                $remaining = Get-RemainingSteps $stepIndex $submitted
                Write-JsonStatus -State $(if ($script:StepResults.Count -gt 0 -or $submitted -gt 0) { 'partial' } else { 'failed' }) -CurrentStep ($stepIndex + 1) -StepCount $script:NormalizedSteps.Count -RepeatDone $submitted -RepeatTotal ([int]$step.repeat) -ErrorCode 'INPUT_BLOCKED' -CanResume $true -RemainingSteps $remaining
                exit 7
            }
            Start-Sleep -Milliseconds 140
            if (-not [IsaacInput]::TapScanCode(0x1C)) {
                [IsaacInput]::TapScanCode(0x01) | Out-Null
                $remaining = Get-RemainingSteps $stepIndex $submitted
                Write-JsonStatus -State $(if ($script:StepResults.Count -gt 0) { 'partial' } else { 'failed' }) -CurrentStep ($stepIndex + 1) -StepCount $script:NormalizedSteps.Count -RepeatDone $submitted -RepeatTotal ([int]$step.repeat) -ErrorCode 'INPUT_BLOCKED' -CanResume $true -RemainingSteps $remaining
                exit 7
            }
            $submitted++
            Write-JsonStatus -State 'running' -CurrentStep ($stepIndex + 1) -StepCount $script:NormalizedSteps.Count -RepeatDone $submitted -RepeatTotal ([int]$step.repeat)
            if ($iteration -lt [int]$step.repeat) { Start-Sleep -Milliseconds 220 }
        }
        Add-StepResult $step ([int]$step.repeat) $submitted 'submitted' $(if ($step.repeatLimited) { '按安全规则仅提交一次' } else { '输入已提交；请在游戏内确认实际效果' })
    }

    Start-Sleep -Milliseconds 650
    $closed = [IsaacInput]::IsForegroundProcess([uint32]$isaac.Id) -and [IsaacInput]::TapScanCode(0x01)
    Start-Sleep -Milliseconds 180
    Write-JsonStatus -State 'completed' -CurrentStep $script:NormalizedSteps.Count -StepCount $script:NormalizedSteps.Count -ErrorCode $(if ($closed) { '' } else { 'CLOSE_FAILED' })
    exit 0
}
catch {
    if ([string]::IsNullOrWhiteSpace($script:JobId)) { $script:JobId = 'invalid-job' }
    $code = $_.Exception.Message
    if ($code -notmatch '^[A-Z_]+$') { $code = 'HELPER_' + $_.Exception.GetType().Name }
    try { Write-JsonStatus -State 'failed' -StepCount $script:NormalizedSteps.Count -ErrorCode $code -CanResume ($script:NormalizedSteps.Count -gt 0) -RemainingSteps $script:NormalizedSteps } catch {}
    exit 1
}
finally {
    foreach ($path in @($CommandFile, $JobFile)) {
        if (-not [string]::IsNullOrWhiteSpace($path)) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
    }
}
