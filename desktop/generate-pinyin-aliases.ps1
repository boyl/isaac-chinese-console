param(
  [Parameter(Mandatory = $true)]
  [string]$NamesFile,

  [Parameter(Mandatory = $true)]
  [string]$OutputFile
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $NamesFile -PathType Leaf)) {
  throw "EID Chinese names file not found: $NamesFile"
}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

[ComImport]
[Guid("019F7152-E6DB-11D0-83C3-00C04FDDB82E")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IFELanguageNative
{
    [PreserveSig] int Open();
    [PreserveSig] int Close();
    [PreserveSig] int GetJMorphResult(
        uint request,
        uint mode,
        int inputLength,
        [MarshalAs(UnmanagedType.LPWStr)] string input,
        IntPtr cinfo,
        out IntPtr result);
    [PreserveSig] int GetConversionModeCaps(out uint caps);
    [PreserveSig] int GetConversion(
        [MarshalAs(UnmanagedType.BStr)] string input,
        int start,
        int length,
        [MarshalAs(UnmanagedType.BStr)] out string result);
}

public sealed class ChinesePinyinIme : IDisposable
{
    const uint FELANG_REQ_REV = 0x00030000;
    const uint FELANG_CMODE_PINYIN = 0x00000100;
    const uint FELANG_CMODE_NOINVISIBLECHAR = 0x40000000;

    public ChinesePinyinIme() { }

    public string Convert(string text)
    {
        if (String.IsNullOrEmpty(text)) return String.Empty;
        Type type = Type.GetTypeFromProgID("MSIME.China");
        if (type == null) throw new InvalidOperationException("Microsoft Chinese IME is not installed.");
        object comObject = Activator.CreateInstance(type);
        IFELanguageNative ime = (IFELanguageNative)comObject;
        IntPtr result = IntPtr.Zero;
        try
        {
            int hr = ime.Open();
            if (hr < 0) Marshal.ThrowExceptionForHR(hr);
            hr = ime.GetJMorphResult(
                FELANG_REQ_REV,
                FELANG_CMODE_PINYIN | FELANG_CMODE_NOINVISIBLECHAR,
                text.Length,
                text,
                IntPtr.Zero,
                out result);
            if (hr < 0) Marshal.ThrowExceptionForHR(hr);
            if (result == IntPtr.Zero) return String.Empty;

            // MORRSLT is packed on four-byte boundaries by the IME ABI,
            // including in a 64-bit process: DWORD size, pointer, DWORD length.
            int resultSize = Marshal.ReadInt32(result, 0);
            IntPtr output = Marshal.ReadIntPtr(result, 4);
            int outputLength = (ushort)Marshal.ReadInt16(result, 12);
            long outputOffset = output.ToInt64() - result.ToInt64();
            if (output == IntPtr.Zero || outputLength <= 0 ||
                outputLength > text.Length * 16 + 32 ||
                outputOffset < 0 || outputOffset + outputLength * 2L > resultSize)
                throw new InvalidOperationException(
                    "Invalid MORRSLT: size=" + resultSize +
                    " offset=" + outputOffset + " length=" + outputLength);
            return Marshal.PtrToStringUni(output, outputLength);
        }
        finally
        {
            if (result != IntPtr.Zero) Marshal.FreeCoTaskMem(result);
            try { ime.Close(); } catch { }
            Marshal.FinalReleaseComObject(comObject);
        }
    }

    public void Dispose() { }
}
'@

function ConvertTo-PlainPinyin {
  param([string]$Value)

  $value = $Value -replace '[üǖǘǚǜÜǕǗǙǛ]', 'v'
  $builder = [Text.StringBuilder]::new()
  foreach ($character in $value.Normalize([Text.NormalizationForm]::FormD).ToCharArray()) {
    $category = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($character)
    if ($category -ne [Globalization.UnicodeCategory]::NonSpacingMark -and
        (($character -ge 'a' -and $character -le 'z') -or
         ($character -ge 'A' -and $character -le 'Z'))) {
      [void]$builder.Append([char]::ToLowerInvariant($character))
    }
  }
  return $builder.ToString()
}

function Split-PinyinSyllables {
  param(
    [string]$Pinyin,
    [string[]]$DefaultReadings,
    [Collections.Generic.HashSet[string]]$KnownSyllables
  )

  $memo = @{}
  function Find-Split([int]$offset, [int]$index) {
    $key = "$offset`:$index"
    if ($memo.ContainsKey($key)) { return $memo[$key] }
    if ($index -eq $DefaultReadings.Count) {
      $result = if ($offset -eq $Pinyin.Length) { ,@() } else { $null }
      $memo[$key] = $result
      return $result
    }

    $remainingCharacters = $DefaultReadings.Count - $index - 1
    $maximumLength = [Math]::Min(6, $Pinyin.Length - $offset - $remainingCharacters)
    $candidates = for ($length = 1; $length -le $maximumLength; $length++) {
      $syllable = $Pinyin.Substring($offset, $length)
      if ($KnownSyllables.Contains($syllable)) {
        [pscustomobject]@{
          Value = $syllable
          Score = if ($syllable -eq $DefaultReadings[$index]) { 100 + $length } else { $length }
        }
      }
    }

    foreach ($candidate in ($candidates | Sort-Object Score -Descending)) {
      $tail = Find-Split ($offset + $candidate.Value.Length) ($index + 1)
      if ($null -ne $tail) {
        $result = @($candidate.Value) + @($tail)
        $memo[$key] = $result
        return $result
      }
    }
    $memo[$key] = $null
    return $null
  }

  return Find-Split 0 0
}

$source = Get-Content -LiteralPath $NamesFile -Raw -Encoding utf8
$matches = [regex]::Matches($source, '\[C_ID \.\. (\d+)\]\s*=\s*"([^"]*)"')
if ($matches.Count -ne 732) {
  throw "Expected 732 official collectible names, found $($matches.Count)."
}

$names = @{}
foreach ($match in $matches) {
  $names[[int]$match.Groups[1].Value] = $match.Groups[2].Value
}

$hanCharacters = $names.Values |
  ForEach-Object { [regex]::Matches($_, '[\u4e00-\u9fff]') | ForEach-Object Value } |
  Sort-Object -Unique

$defaultReadings = @{}
$knownSyllables = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$ime = [ChinesePinyinIme]::new()
try {
  foreach ($character in $hanCharacters) {
    try {
      $converted = $ime.Convert([string]$character)
      $reading = ConvertTo-PlainPinyin $converted
    }
    catch {
      throw "Pinyin conversion failed for character '$character': $($_.Exception.Message)"
    }
    if ($reading -eq '') { throw "No pinyin reading returned for character '$character' (raw='$converted')." }
    $defaultReadings[$character] = $reading
    [void]$knownSyllables.Add($reading)
  }

$aliases = @{}
  foreach ($id in 1..732) {
    $name = $names[$id]
    if ($name -eq '') {
      $aliases[$id] = ''
      continue
    }

    $fullBuilder = [Text.StringBuilder]::new()
    $initialBuilder = [Text.StringBuilder]::new()
    $position = 0
    while ($position -lt $name.Length) {
      if ($name[$position] -match '[\u4e00-\u9fff]') {
        $start = $position
        while ($position -lt $name.Length -and $name[$position] -match '[\u4e00-\u9fff]') { $position++ }
        $run = $name.Substring($start, $position - $start)
        $convertedRun = $ime.Convert($run)
        $plain = ConvertTo-PlainPinyin $convertedRun
        $defaults = @($run.ToCharArray() | ForEach-Object { $defaultReadings[[string]$_] })
        $syllables = @(Split-PinyinSyllables $plain $defaults $knownSyllables)
        $invalidSyllables = @($syllables | Where-Object { [string]::IsNullOrEmpty($_) }).Count -gt 0
        if ($syllables.Count -ne $defaults.Count -or $invalidSyllables) {
          $syllables = $defaults
          $plain = $syllables -join ''
        }
        [void]$fullBuilder.Append($plain)
        foreach ($syllable in $syllables) { [void]$initialBuilder.Append($syllable[0]) }
      }
      elseif ([char]::IsLetterOrDigit($name[$position])) {
        $start = $position
        while ($position -lt $name.Length -and [char]::IsLetterOrDigit($name[$position]) -and
            $name[$position] -notmatch '[\u4e00-\u9fff]') { $position++ }
        $token = $name.Substring($start, $position - $start).ToLowerInvariant()
        [void]$fullBuilder.Append($token)
        [void]$initialBuilder.Append($token)
      }
      else {
        $position++
      }
    }

    $full = $fullBuilder.ToString()
    $initials = $initialBuilder.ToString()
    $aliases[$id] = if ($initials -ne '' -and $initials -ne $full) { "$full $initials" } else { $full }
  }
}
finally {
  $ime.Dispose()
}

if ($aliases[260] -ne 'heilazhu hlz') {
  throw "Black Candle alias mismatch: $($aliases[260])"
}

$lines = [Collections.Generic.List[string]]::new()
$lines.Add('-- Generated by desktop/generate-pinyin-aliases.ps1; do not edit by hand.')
$lines.Add('-- Source: EID descriptions/names/zh_cn.lua; values are ASCII search aliases only.')
$lines.Add('return {')
foreach ($id in 1..732) {
  $value = $aliases[$id].Replace('\\', '\\\\').Replace('"', '\\"')
  $lines.Add("  [$id] = `"$value`",")
}
$lines.Add('}')

$parent = Split-Path -Parent $OutputFile
if (-not (Test-Path -LiteralPath $parent)) {
  New-Item -ItemType Directory -Path $parent | Out-Null
}
[IO.File]::WriteAllLines($OutputFile, $lines, [Text.UTF8Encoding]::new($false))
Write-Host "generated $($aliases.Count) aliases -> $OutputFile"

