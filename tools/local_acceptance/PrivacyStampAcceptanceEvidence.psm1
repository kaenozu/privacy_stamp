Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertFrom-PrivacyStampMeminfoTotalPssKb {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Lines)

    foreach ($line in $Lines) {
        if ($line -match '^\s*TOTAL PSS:\s*(?<value>\d+)\b') {
            return [long]$Matches.value
        }
    }
    foreach ($line in $Lines) {
        if ($line -match '^\s*TOTAL\s+(?<value>\d+)\s+') {
            return [long]$Matches.value
        }
    }
    return $null
}

function Get-PrivacyStampPeakPssKb {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Samples)

    $values = @(
        $Samples |
            ForEach-Object {
                if ($null -ne $_ -and "$_" -match '^\d+$') {
                    [long]$_
                }
            }
    )
    if ($values.Count -eq 0) { return $null }
    return [long](($values | Measure-Object -Maximum).Maximum)
}

function ConvertFrom-PrivacyStampDeviceFileSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Lines)

    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($line in $Lines) {
        if ($line -notmatch '^(?<epoch>\d+)\|(?<size>\d+)\|(?<path>/sdcard/.+)$') {
            continue
        }
        $entries.Add(
            [pscustomobject]@{
                EpochSeconds = [long]$Matches.epoch
                SizeBytes = [long]$Matches.size
                Path = [string]$Matches.path
            }
        )
    }
    return @($entries)
}

function Select-PrivacyStampExportCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Baseline,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Current,
        [Parameter(Mandatory)][string]$InputDevicePath,
        [string]$ExpectedOutputDevicePath
    )

    if (-not [string]::IsNullOrWhiteSpace($ExpectedOutputDevicePath)) {
        $exact = @($Current | Where-Object { $_.Path -eq $ExpectedOutputDevicePath })
        if ($exact.Count -eq 1) { return $exact[0] }
        if ($exact.Count -gt 1) {
            throw 'Expected output path appeared more than once in the snapshot.'
        }
        return $null
    }

    $baselineByPath = @{}
    foreach ($entry in $Baseline) {
        $baselineByPath[$entry.Path] = $entry
    }
    $candidates = @(
        $Current |
            Where-Object {
                $_.Path -ne $InputDevicePath -and
                $_.Path -match '(?i)\.png$' -and
                (
                    -not $baselineByPath.ContainsKey($_.Path) -or
                    $_.EpochSeconds -gt $baselineByPath[$_.Path].EpochSeconds -or
                    $_.SizeBytes -ne $baselineByPath[$_.Path].SizeBytes
                )
            } |
            Sort-Object EpochSeconds, Path
    )
    if ($candidates.Count -eq 0) { return $null }
    if ($candidates.Count -gt 1) {
        throw "More than one new or modified PNG was detected ($($candidates.Count)). Supply -ExpectedOutputDevicePath and rerun."
    }
    return $candidates[0]
}

function Find-PrivacyStampFatalEvents {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Lines,
        [Parameter(Mandatory)][string]$PackageName
    )

    $events = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $escaped = [regex]::Escape($PackageName)

    for ($index = 0; $index -lt $Lines.Count; $index++) {
        $line = $Lines[$index]
        $start = [Math]::Max(0, $index - 8)
        $end = [Math]::Min($Lines.Count - 1, $index + 16)
        $window = ($Lines[$start..$end] -join "`n")
        $belongsToPackage =
            $line -match $escaped -or
            $window -match "(?m)^.*Process:\s*$escaped(?:,|\s|$)" -or
            $window -match ">>>\s*$escaped\s*<<<" -or
            $window -match "ANR in\s+$escaped\b"

        if ($line -match "ANR in\s+$escaped\b") {
            [void]$events.Add('ANR')
        }
        if ($belongsToPackage -and $line -match 'OutOfMemoryError') {
            [void]$events.Add('OutOfMemoryError')
        }
        if ($line -match 'FATAL EXCEPTION' -and $belongsToPackage) {
            [void]$events.Add('FATAL EXCEPTION')
        }
        if ($line -match 'Fatal signal' -and $belongsToPackage) {
            [void]$events.Add('Fatal signal')
        }
        if ($line -match "Force finishing activity.*$escaped") {
            [void]$events.Add('Force finishing activity')
        }
    }

    return @($events | Sort-Object)
}

function Test-PrivacyStampAcceptanceConfirmation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Actual,
        [Parameter(Mandatory)][string]$Expected
    )

    return $Actual.Trim() -ceq $Expected
}

Export-ModuleMember -Function @(
    'ConvertFrom-PrivacyStampMeminfoTotalPssKb',
    'Get-PrivacyStampPeakPssKb',
    'ConvertFrom-PrivacyStampDeviceFileSnapshot',
    'Select-PrivacyStampExportCandidate',
    'Find-PrivacyStampFatalEvents',
    'Test-PrivacyStampAcceptanceConfirmation'
)
