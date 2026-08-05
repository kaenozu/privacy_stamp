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
Assert-Equal (Get-PrivacyStampPeakPssKb @()) $null `
    'Empty peak sample must remain unavailable'

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
    '08-05 10:00:00.000 E AndroidRuntime: FATAL EXCEPTION: main',
    '08-05 10:00:00.001 E AndroidRuntime: Process: com.example.privacy_stamp, PID: 4242',
    '08-05 10:00:00.002 E AndroidRuntime: java.lang.OutOfMemoryError: Failed to allocate',
    '08-05 10:01:00.000 E ActivityManager: ANR in com.example.privacy_stamp',
    '08-05 10:02:00.000 F libc: Fatal signal 6 (SIGABRT), code -1 in tid 55',
    '08-05 10:02:00.001 F DEBUG: >>> com.example.privacy_stamp <<<'
)
$events = Find-PrivacyStampFatalEvents `
    -Lines $logcat `
    -PackageName 'com.example.privacy_stamp'
Assert-True ($events -contains 'FATAL EXCEPTION') 'FATAL EXCEPTION not detected'
Assert-True ($events -contains 'OutOfMemoryError') 'OOM not detected'
Assert-True ($events -contains 'ANR') 'ANR not detected'
Assert-True ($events -contains 'Fatal signal') 'Fatal signal not detected'

$unrelated = Find-PrivacyStampFatalEvents `
    -Lines @(
        'E AndroidRuntime: FATAL EXCEPTION: main',
        'E AndroidRuntime: Process: another.package, PID: 99'
    ) `
    -PackageName 'com.example.privacy_stamp'
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
