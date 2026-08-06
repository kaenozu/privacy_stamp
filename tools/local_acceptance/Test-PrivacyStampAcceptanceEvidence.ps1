[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'PrivacyStampAcceptanceEvidence.psm1') -Force

function Assert-Equal([object]$Actual, [object]$Expected, [string]$Message) {
    if ($Actual -ne $Expected) {
        throw "$Message. actual=[$Actual] expected=[$Expected]"
    }
}

function Assert-True([bool]$Value, [string]$Message) {
    if (-not $Value) { throw $Message }
}

$sample = ConvertFrom-PrivacyStampMeminfoSample `
    -ExpectedPid 4321 `
    -Lines @(
        '** MEMINFO in pid 4321 [com.example.privacy_stamp] **',
        ' App Summary',
        ' Java Heap:      1200                       2400',
        ' Native Heap:    3400                       4800',
        ' TOTAL:          8500                      12600'
    )
Assert-Equal $sample.Pid 4321 'PID parsing failed'
Assert-Equal $sample.TotalPssKb 8500 'TOTAL PSS parsing failed'
Assert-Equal $sample.TotalRssKb 12600 'TOTAL RSS parsing failed'
Assert-Equal $sample.JavaHeapKb 1200 'Java heap parsing failed'
Assert-Equal $sample.NativeHeapKb 3400 'Native heap parsing failed'

$pidMismatchThrew = $false
try {
    ConvertFrom-PrivacyStampMeminfoSample `
        -ExpectedPid 4321 `
        -Lines @(
            '** MEMINFO in pid 4322 [com.example.privacy_stamp] **',
            ' App Summary',
            ' TOTAL: 8500 12600'
        ) | Out-Null
} catch {
    $pidMismatchThrew = $_.Exception.Message -match 'process ID changed'
}
Assert-True $pidMismatchThrew 'Meminfo PID changes must fail closed'

Assert-Equal (
    ConvertFrom-PrivacyStampMeminfoTotalPssKb @(
        ' App Summary',
        ' TOTAL PSS:      237734            TOTAL RSS: 300000'
    )
) 237734 'TOTAL PSS summary parsing failed'

Assert-Equal (
    ConvertFrom-PrivacyStampMeminfoTotalPssKb @(
        ' TOTAL       188234    120000     5000      1000'
    )
) 188234 'Legacy TOTAL table parsing failed'

Assert-Equal (Get-PrivacyStampPeakPssKb @(120000, $null, 237734, 180000)) `
    237734 'Peak PSS calculation failed'
Assert-Equal (Get-PrivacyStampPeakPssKb -Samples @()) $null `
    'Empty peak sample must remain unavailable'

$runtime = Get-PrivacyStampRuntimeSummary `
    -Samples @(
        [pscustomobject]@{
            Pid = 4321
            TotalPssKb = 8000
            TotalRssKb = 12000
            JavaHeapKb = 2000
            NativeHeapKb = 3000
        },
        [pscustomobject]@{
            Pid = 4321
            TotalPssKb = 9000
            TotalRssKb = 13000
            JavaHeapKb = 2500
            NativeHeapKb = 3200
        }
    ) `
    -Events @() `
    -ProcessAliveAfterExport $true
Assert-Equal $runtime.SampleCount 2 'Runtime sample count failed'
Assert-Equal $runtime.PeakTotalPssKb 9000 'Peak runtime PSS failed'
Assert-Equal $runtime.PeakTotalRssKb 13000 'Peak runtime RSS failed'
Assert-Equal $runtime.ProcessRestartCount 0 'Stable PID reported a restart'
Assert-True $runtime.Passed 'Stable event-free runtime must pass'

$restarted = Get-PrivacyStampRuntimeSummary `
    -Samples @(
        [pscustomobject]@{
            Pid = 4321
            TotalPssKb = 8000
            TotalRssKb = $null
            JavaHeapKb = $null
            NativeHeapKb = $null
        },
        [pscustomobject]@{
            Pid = 4322
            TotalPssKb = 7000
            TotalRssKb = $null
            JavaHeapKb = $null
            NativeHeapKb = $null
        }
    ) `
    -Events @() `
    -ProcessAliveAfterExport $true
Assert-Equal $restarted.ProcessRestartCount 1 'PID restart was not counted'
Assert-True (-not $restarted.Passed) 'PID restart must block acceptance'

$singleSample = Get-PrivacyStampRuntimeSummary `
    -Samples @(
        [pscustomobject]@{
            Pid = 4321
            TotalPssKb = 8000
            TotalRssKb = $null
            JavaHeapKb = $null
            NativeHeapKb = $null
        }
    ) `
    -Events @() `
    -ProcessAliveAfterExport $true
Assert-True (-not $singleSample.Passed) `
    'A single memory sample must not prove peak memory safety'

$baseline = ConvertFrom-PrivacyStampDeviceFileSnapshot @(
    '100|1000|/sdcard/Download/existing.png',
    '101|2000|/sdcard/Download/input.jpg',
    'garbage'
)
$current = ConvertFrom-PrivacyStampDeviceFileSnapshot @(
    '100|1000|/sdcard/Download/existing.png',
    '101|2000|/sdcard/Download/input.jpg',
    '120|5000|/sdcard/Pictures/exported.png'
)
Assert-Equal $baseline.Count 2 'Snapshot parser accepted invalid lines'
$candidate = Select-PrivacyStampExportCandidate `
    -Baseline $baseline `
    -Current $current `
    -InputDevicePath '/sdcard/Download/input.jpg'
Assert-Equal $candidate.Path '/sdcard/Pictures/exported.png' `
    'Unique exported PNG was not selected'

$ambiguous = ConvertFrom-PrivacyStampDeviceFileSnapshot @(
    '120|5000|/sdcard/Pictures/exported-a.png',
    '121|5001|/sdcard/DCIM/exported-b.png'
)
$threw = $false
try {
    Select-PrivacyStampExportCandidate `
        -Baseline @() `
        -Current $ambiguous `
        -InputDevicePath '/sdcard/Download/input.jpg' | Out-Null
} catch {
    $threw = $_.Exception.Message -match 'More than one'
}
Assert-True $threw 'Ambiguous output selection must fail closed'

$exact = Select-PrivacyStampExportCandidate `
    -Baseline @() `
    -Current $ambiguous `
    -InputDevicePath '/sdcard/Download/input.jpg' `
    -ExpectedOutputDevicePath '/sdcard/DCIM/exported-b.png'
Assert-Equal $exact.Path '/sdcard/DCIM/exported-b.png' `
    'Expected output path selection failed'

$logcat = @(
    '08-05 10:00:00.000  4321  4500 E AndroidRuntime: FATAL EXCEPTION: main',
    '08-05 10:00:00.001  4321  4500 E AndroidRuntime: java.lang.OutOfMemoryError: Failed to allocate',
    '08-05 10:00:00.002  4321  4500 W lmkd: killing process due to low memory',
    '08-05 10:01:00.000  1000  1000 E ActivityManager: ANR in com.example.privacy_stamp',
    '08-05 10:02:00.000  1000  1000 I ActivityManager: Process com.example.privacy_stamp has died',
    '08-05 10:03:00.000  9999  9999 E AndroidRuntime: FATAL EXCEPTION: unrelated'
)
$events = @(
    Find-PrivacyStampFatalEvents `
        -Lines $logcat `
        -PackageName 'com.example.privacy_stamp' `
        -MonitoredPids @(4321)
)
Assert-True ($events -contains 'FATAL EXCEPTION') 'FATAL EXCEPTION not detected'
Assert-True ($events -contains 'OutOfMemoryError') 'OOM not detected'
Assert-True ($events -contains 'Low-memory kill') 'Low-memory kill not detected'
Assert-True ($events -contains 'ANR') 'ANR not detected'
Assert-True ($events -contains 'Process death') 'Process death not detected'

$unrelated = @(
    Find-PrivacyStampFatalEvents `
        -Lines @(
            '08-05 10:00:00.000  9999  9999 E AndroidRuntime: FATAL EXCEPTION: main',
            '08-05 10:00:00.001  9999  9999 E AndroidRuntime: Process: another.package, PID: 9999'
        ) `
        -PackageName 'com.example.privacy_stamp' `
        -MonitoredPids @(4321)
)
Assert-Equal $unrelated.Count 0 'Unrelated package fatal event was not excluded'

Assert-True (
    Test-PrivacyStampAcceptanceConfirmation `
        -Actual 'MASK_OK' `
        -Expected 'MASK_OK'
) 'Exact confirmation must pass'
Assert-True (-not (
    Test-PrivacyStampAcceptanceConfirmation `
        -Actual 'mask_ok' `
        -Expected 'MASK_OK'
)) 'Confirmation must be case-sensitive'

Write-Host 'Privacy Stamp acceptance evidence helper tests: PASS'
