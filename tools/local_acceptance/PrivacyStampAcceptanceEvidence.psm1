Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-PrivacyStampInteger([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    return [long]($Value -replace ',', '')
}

function ConvertFrom-PrivacyStampMeminfoSample {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][string[]]$Lines = @(),
        [Nullable[long]]$ExpectedPid
    )

    $observedPid = $null
    foreach ($line in $Lines) {
        if ($line -match '\*\*\s+MEMINFO\s+in\s+pid\s+(?<pid>\d+)') {
            $observedPid = [long]$Matches.pid
            break
        }
    }
    if ($null -ne $ExpectedPid -and
        $null -ne $observedPid -and
        [long]$ExpectedPid -ne $observedPid) {
        throw 'The meminfo process ID changed during acceptance.'
    }
    $pid = if ($null -ne $ExpectedPid) {
        [long]$ExpectedPid
    } else {
        $observedPid
    }
    if ($null -eq $pid -or $pid -le 0) {
        throw 'A valid app process ID is required for memory evidence.'
    }

    $totalPssKb = $null
    $totalRssKb = $null
    $javaHeapKb = $null
    $nativeHeapKb = $null
    $inAppSummary = $false

    foreach ($line in $Lines) {
        $trimmed = $line.Trim()
        if ($trimmed -eq 'App Summary') {
            $inAppSummary = $true
            continue
        }
        if (-not $inAppSummary) { continue }
        if ($trimmed -notmatch '^(?<label>Java Heap|Native Heap|TOTAL):?\s+(?<values>.+)$') {
            continue
        }
        $values = @(
            [regex]::Matches($Matches.values, '\d[\d,]*') |
                ForEach-Object { ConvertTo-PrivacyStampInteger $_.Value }
        )
        if ($values.Count -eq 0) { continue }
        switch ($Matches.label) {
            'Java Heap' { $javaHeapKb = [long]$values[0] }
            'Native Heap' { $nativeHeapKb = [long]$values[0] }
            'TOTAL' {
                $totalPssKb = [long]$values[0]
                if ($values.Count -gt 1) {
                    $totalRssKb = [long]$values[$values.Count - 1]
                }
            }
        }
    }

    if ($null -eq $totalPssKb) {
        foreach ($line in $Lines) {
            if ($line -match '^\s*TOTAL PSS:\s*(?<pss>\d[\d,]*)(?:.*TOTAL RSS:\s*(?<rss>\d[\d,]*))?') {
                $totalPssKb = ConvertTo-PrivacyStampInteger $Matches.pss
                if ($Matches.ContainsKey('rss') -and
                    -not [string]::IsNullOrWhiteSpace($Matches.rss)) {
                    $totalRssKb = ConvertTo-PrivacyStampInteger $Matches.rss
                }
                break
            }
            if ($line -match '^\s*TOTAL\s+(?<pss>\d[\d,]*)\s+') {
                $totalPssKb = ConvertTo-PrivacyStampInteger $Matches.pss
                break
            }
        }
    }
    if ($null -eq $totalPssKb) {
        throw 'TOTAL PSS was not present in meminfo.'
    }

    return [pscustomobject]@{
        Pid = [long]$pid
        TotalPssKb = [long]$totalPssKb
        TotalRssKb = $totalRssKb
        JavaHeapKb = $javaHeapKb
        NativeHeapKb = $nativeHeapKb
    }
}

function ConvertFrom-PrivacyStampMeminfoTotalPssKb {
    [CmdletBinding()]
    param([AllowEmptyCollection()][string[]]$Lines = @())

    try {
        return [long](
            ConvertFrom-PrivacyStampMeminfoSample `
                -Lines $Lines `
                -ExpectedPid 1
        ).TotalPssKb
    } catch {
        foreach ($line in $Lines) {
            if ($line -match '^\s*TOTAL PSS:\s*(?<value>\d[\d,]*)\b') {
                return ConvertTo-PrivacyStampInteger $Matches.value
            }
            if ($line -match '^\s*TOTAL\s+(?<value>\d[\d,]*)\s+') {
                return ConvertTo-PrivacyStampInteger $Matches.value
            }
        }
        return $null
    }
}

function Get-PrivacyStampPeakPssKb {
    [CmdletBinding()]
    param([AllowEmptyCollection()][object[]]$Samples = @())

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

function Get-PrivacyStampRuntimeSummary {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]]$Samples = @(),
        [AllowEmptyCollection()][string[]]$Events = @(),
        [bool]$ProcessAliveAfterExport
    )

    $validSamples = @($Samples | Where-Object { $null -ne $_ })
    $restartCount = 0
    $previousPid = $null
    foreach ($sample in $validSamples) {
        if ($null -ne $previousPid -and [long]$previousPid -ne [long]$sample.Pid) {
            $restartCount++
        }
        $previousPid = [long]$sample.Pid
    }

    function Peak([string]$Property) {
        $values = @(
            $validSamples |
                ForEach-Object { $_.$Property } |
                Where-Object { $null -ne $_ } |
                ForEach-Object { [long]$_ }
        )
        if ($values.Count -eq 0) { return $null }
        return [long](($values | Measure-Object -Maximum).Maximum)
    }

    $eventTypes = @($Events | Where-Object { $_ } | Sort-Object -Unique)
    $sampleCount = $validSamples.Count
    $passed =
        $sampleCount -ge 2 -and
        $restartCount -eq 0 -and
        $ProcessAliveAfterExport -and
        $eventTypes.Count -eq 0

    return [pscustomobject]@{
        SampleCount = $sampleCount
        PeakTotalPssKb = Peak 'TotalPssKb'
        PeakTotalRssKb = Peak 'TotalRssKb'
        PeakJavaHeapKb = Peak 'JavaHeapKb'
        PeakNativeHeapKb = Peak 'NativeHeapKb'
        ProcessRestartCount = $restartCount
        ProcessAliveAfterExport = $ProcessAliveAfterExport
        Events = $eventTypes
        Passed = $passed
    }
}

function ConvertFrom-PrivacyStampDeviceFileSnapshot {
    [CmdletBinding()]
    param([AllowEmptyCollection()][string[]]$Lines = @())

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
        [AllowEmptyCollection()][object[]]$Baseline = @(),
        [AllowEmptyCollection()][object[]]$Current = @(),
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
        [AllowEmptyCollection()][string[]]$Lines = @(),
        [Parameter(Mandatory)][string]$PackageName,
        [AllowEmptyCollection()][long[]]$MonitoredPids = @()
    )

    $events = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $escaped = [regex]::Escape($PackageName)

    for ($index = 0; $index -lt $Lines.Count; $index++) {
        $line = $Lines[$index]
        $linePid = $null
        if ($line -match '^\d\d-\d\d\s+\d\d:\d\d:\d\d\.\d+\s+(?<pid>\d+)\s+\d+') {
            $linePid = [long]$Matches.pid
        }
        $belongsToPid = $null -ne $linePid -and $linePid -in $MonitoredPids
        $start = [Math]::Max(0, $index - 8)
        $end = [Math]::Min($Lines.Count - 1, $index + 16)
        $window = ($Lines[$start..$end] -join "`n")
        $belongsToPackage =
            $line -match $escaped -or
            $window -match "(?m)^.*Process:\s*$escaped(?:,|\s|$)" -or
            $window -match ">>>\s*$escaped\s*<<<" -or
            $window -match "ANR in\s+$escaped\b"
        $belongsToProcess = $belongsToPackage -or $belongsToPid

        if ($line -match "ANR in\s+$escaped\b") {
            [void]$events.Add('ANR')
        }
        if ($belongsToProcess -and $line -match 'OutOfMemoryError') {
            [void]$events.Add('OutOfMemoryError')
        }
        if ($belongsToProcess -and $line -match 'FATAL EXCEPTION') {
            [void]$events.Add('FATAL EXCEPTION')
        }
        if ($belongsToProcess -and $line -match 'Fatal signal') {
            [void]$events.Add('Fatal signal')
        }
        if ($line -match "(?:Process\s+)?$escaped.*(?:has died|process died)") {
            [void]$events.Add('Process death')
        }
        if ($belongsToProcess -and
            $line -match '(?i)(?:lmkd|low memory)' -and
            $line -match '(?i)kill(?:ing|ed)?') {
            [void]$events.Add('Low-memory kill')
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
    'ConvertFrom-PrivacyStampMeminfoSample',
    'ConvertFrom-PrivacyStampMeminfoTotalPssKb',
    'Get-PrivacyStampPeakPssKb',
    'Get-PrivacyStampRuntimeSummary',
    'ConvertFrom-PrivacyStampDeviceFileSnapshot',
    'Select-PrivacyStampExportCandidate',
    'Find-PrivacyStampFatalEvents',
    'Test-PrivacyStampAcceptanceConfirmation'
)
