param(
    [string]$CommandFile,

    [Parameter(Mandatory = $true)]
    [string]$StatusFile,

    [switch]$ProbeOnly,

    [switch]$ConsoleAlreadyOpen,

    [int]$RepeatCount = 1
)

$ErrorActionPreference = 'Stop'

function Write-IsaacStatus {
    param([string]$Value)
    try {
        [System.IO.File]::WriteAllText($StatusFile, $Value, [System.Text.Encoding]::ASCII)
    } catch {
        # The UI also has a timeout fallback if the status file cannot be written.
    }
}

try {
    if ($ProbeOnly) {
        $probe = Get-Process -Name 'isaac-ng', 'isaac-ng-x64', 'isaac' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($probe) { Write-IsaacStatus 'RUNNING' } else { Write-IsaacStatus 'STOPPED' }
        exit 0
    }

    if ([string]::IsNullOrWhiteSpace($CommandFile)) {
        Write-IsaacStatus 'ERR|COMMAND_FILE'
        exit 3
    }
    if (-not (Test-Path -LiteralPath $CommandFile)) {
        Write-IsaacStatus 'ERR|COMMAND_FILE'
        exit 3
    }

    $isaacCommand = (Get-Content -LiteralPath $CommandFile -Raw -Encoding Unicode).Trim()
    Remove-Item -LiteralPath $CommandFile -Force -ErrorAction SilentlyContinue

    if ([string]::IsNullOrWhiteSpace($isaacCommand)) {
        Write-IsaacStatus 'ERR|EMPTY_COMMAND'
        exit 4
    }
    if ($isaacCommand.Length -gt 500 -or $isaacCommand -match '[\r\n]') {
        Write-IsaacStatus 'ERR|UNSAFE_COMMAND'
        exit 5
    }
    if ($RepeatCount -lt 1 -or $RepeatCount -gt 99) {
        Write-IsaacStatus 'ERR|REPEAT_RANGE'
        exit 5
    }
    if ($RepeatCount -gt 1 -and $isaacCommand -notmatch '^(giveitem|spawn)\s+') {
        Write-IsaacStatus 'ERR|REPEAT_NOT_ALLOWED'
        exit 5
    }

    $isaac = Get-Process -Name 'isaac-ng', 'isaac-ng-x64', 'isaac' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $isaac) {
        Write-IsaacStatus 'ERR|NO_GAME'
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

    # Find and activate the game without relying on Process.MainWindowHandle,
    # which can be zero for SDL/full-screen windows on some systems.
    $gameWindow = [IsaacInput]::FindWindowForProcess([uint32]$isaac.Id)
    $focused = $false
    if ($gameWindow -ne [IntPtr]::Zero) {
        $focused = [IsaacInput]::ForceForeground($gameWindow, [uint32]$isaac.Id)
    }
    if (-not $focused) {
        try {
            $wshell = New-Object -ComObject WScript.Shell
            $null = $wshell.AppActivate($isaac.Id)
            Start-Sleep -Milliseconds 220
            $focused = [IsaacInput]::IsForegroundProcess([uint32]$isaac.Id)
        } catch {
            $focused = $false
        }
    }
    if (-not $focused) {
        Write-IsaacStatus $(if ($gameWindow -eq [IntPtr]::Zero) { 'ERR|NO_WINDOW' } else { 'ERR|FOCUS_FAILED' })
        exit 6
    }
    Start-Sleep -Milliseconds 320

    if (-not [IsaacInput]::IsForegroundProcess([uint32]$isaac.Id)) {
        Write-IsaacStatus 'ERR|FOCUS_LOST'
        exit 8
    }
    if (-not $ConsoleAlreadyOpen) {
        # Scan code 0x29 is the physical top-left ` / ~ key and is independent
        # of the active Chinese/English keyboard layout.
        if (-not [IsaacInput]::TapScanCode(0x29)) {
            Write-IsaacStatus 'ERR|INPUT_BLOCKED'
            exit 7
        }
        Start-Sleep -Milliseconds 480
    }
    if (-not [IsaacInput]::IsForegroundProcess([uint32]$isaac.Id)) {
        Write-IsaacStatus 'ERR|FOCUS_LOST'
        exit 8
    }
    # Clear once before the batch starts. Enter leaves a fresh prompt after
    # every successful command, so the console stays open for the whole batch.
    [IsaacInput]::ClearConsoleLine()

    $completed = 0
    for ($iteration = 1; $iteration -le $RepeatCount; $iteration++) {
        if (-not [IsaacInput]::IsForegroundProcess([uint32]$isaac.Id)) {
            if ($completed -gt 0) { Write-IsaacStatus ("PARTIAL|{0}|{1}|FOCUS_LOST" -f $completed, $RepeatCount) }
            else { Write-IsaacStatus 'ERR|FOCUS_LOST' }
            exit 8
        }
        if (-not [IsaacInput]::SendVirtualText($isaacCommand)) {
            [IsaacInput]::TapScanCode(0x01) | Out-Null
            if ($completed -gt 0) { Write-IsaacStatus ("PARTIAL|{0}|{1}|INPUT_BLOCKED" -f $completed, $RepeatCount) }
            else { Write-IsaacStatus 'ERR|INPUT_BLOCKED' }
            exit 7
        }
        Start-Sleep -Milliseconds 140
        if (-not [IsaacInput]::TapScanCode(0x1C)) {
            [IsaacInput]::TapScanCode(0x01) | Out-Null
            if ($completed -gt 0) { Write-IsaacStatus ("PARTIAL|{0}|{1}|INPUT_BLOCKED" -f $completed, $RepeatCount) }
            else { Write-IsaacStatus 'ERR|INPUT_BLOCKED' }
            exit 7
        }
        $completed = $iteration
        Write-IsaacStatus ("PROGRESS|{0}|{1}" -f $completed, $RepeatCount)
        if ($iteration -lt $RepeatCount) { Start-Sleep -Milliseconds 220 }
    }
    # Enter executes the command but leaves Isaac's console open. Do not press
    # the ` / ~ hotkey again here: while the edit line has focus Isaac treats
    # it as literal text. Escape closes the console without adding a character.
    Start-Sleep -Milliseconds 650
    if (-not [IsaacInput]::TapScanCode(0x01)) {
        Write-IsaacStatus ("SENT|CLOSE_FAILED|{0}" -f $completed)
        exit 0
    }
    Start-Sleep -Milliseconds 180

    Write-IsaacStatus ("SENT|CLOSED|{0}" -f $completed)
    exit 0
} catch {
    Write-IsaacStatus ('ERR|HELPER|' + $_.Exception.GetType().Name)
    exit 1
} finally {
    if (-not [string]::IsNullOrWhiteSpace($CommandFile)) {
        Remove-Item -LiteralPath $CommandFile -Force -ErrorAction SilentlyContinue
    }
}
