[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InputImage,
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
    [string]$AvdName = 'PrivacyStamp_LowMem_API35',
    [string]$Serial = 'emulator-5556',
    [int]$RamMb = 1536,
    [string]$SystemImage = 'system-images;android-35;google_apis;x86_64',
    [string]$PackageName = 'com.example.privacy_stamp',
    [string]$ApkPath,
    [string]$ExpectedOutputDevicePath,
    [int]$OutputWaitSeconds = 300,
    [switch]$SkipBuild,
    [switch]$SkipAvdCreation,
    [switch]$KeepAvdData,
    [switch]$RequireInputGps,
    [switch]$AllowInputWithoutGps,
    [string]$OrientationConfirmation,
    [string]$MaskConfirmation,
    [string]$PickerCancelConfirmation,
    [string]$BackDiscardConfirmation,
    [string]$LifecycleConfirmation,
    [string]$TemporaryFilesConfirmation,
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'PrivacyStampAcceptanceEvidence.psm1') -Force

function Require-Command([string]$Name) {
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $command) { throw "Required command not found: $Name" }
    $command.Source
}

function Run([string]$File, [string[]]$Args, [switch]$AllowFailure) {
    $lines = @(& $File @Args 2>&1 | ForEach-Object { "$_" })
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "Command failed with exit code $exitCode."
    }
    [pscustomobject]@{
        ExitCode = $exitCode
        Lines = $lines
        Text = ($lines -join "`n")
    }
}

function Adb([string[]]$Args, [switch]$AllowFailure) {
    Run (Require-Command 'adb') (@('-s', $Serial) + $Args) -AllowFailure:$AllowFailure
}

function Wait-Boot([int]$TimeoutSeconds = 300) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $boot = Adb @('shell', 'getprop', 'sys.boot_completed') -AllowFailure
        if ($boot.Text.Trim() -eq '1') { return }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    throw "Emulator $Serial did not boot within $TimeoutSeconds seconds."
}

function DeviceFileSnapshot {
    $script = 'for d in /sdcard/Download /sdcard/Pictures /sdcard/DCIM; do if [ -d "$d" ]; then find "$d" -type f 2>/dev/null | while IFS= read -r f; do m=$(stat -c %Y "$f" 2>/dev/null || echo 0); s=$(stat -c %s "$f" 2>/dev/null || echo 0); printf "%s|%s|%s\n" "$m" "$s" "$f"; done; fi; done'
    $lines = (Adb @('shell', 'sh', '-c', $script) -AllowFailure).Lines
    ConvertFrom-PrivacyStampDeviceFileSnapshot -Lines $lines
}

function Get-SingleAppPid {
    $pidText = (Adb @('shell', 'pidof', $PackageName) -AllowFailure).Text.Trim()
    $pids = @($pidText -split '\s+' | Where-Object { $_ -match '^\d+$' })
    if ($pids.Count -ne 1) {
        throw 'Expected exactly one running app process.'
    }
    return [long]$pids[0]
}

function Get-CurrentMemorySample([long]$ExpectedPid) {
    $pid = Get-SingleAppPid
    if ($pid -ne $ExpectedPid) {
        throw 'The app process ID changed during export acceptance.'
    }
    $meminfo = Adb @('shell', 'dumpsys', 'meminfo', $PackageName) -AllowFailure
    if ($meminfo.ExitCode -ne 0) {
        throw 'dumpsys meminfo failed during export acceptance.'
    }
    ConvertFrom-PrivacyStampMeminfoSample `
        -Lines $meminfo.Lines `
        -ExpectedPid $ExpectedPid
}

function Require-OperatorConfirmation(
    [string]$Name,
    [string]$Expected,
    [string]$Provided,
    [string]$Prompt
) {
    $actual = $Provided
    if (-not $NonInteractive -and [string]::IsNullOrWhiteSpace($actual)) {
        $actual = Read-Host $Prompt
    }
    if (-not (Test-PrivacyStampAcceptanceConfirmation `
        -Actual ([string]$actual) `
        -Expected $Expected)) {
        throw "$Name requires an explicit operator confirmation."
    }
    return $true
}

function Get-ImageMetadata([string]$Path) {
    Push-Location $repo
    try {
        $probe = Run $dart @(
            'run',
            'tool/acceptance/image_metadata_probe.dart',
            $Path
        )
    } finally {
        Pop-Location
    }
    $jsonLine = @($probe.Lines | Where-Object { $_.TrimStart().StartsWith('{') }) |
        Select-Object -Last 1
    if ([string]::IsNullOrWhiteSpace($jsonLine)) {
        throw 'Image metadata probe did not return JSON.'
    }
    $jsonLine | ConvertFrom-Json -Depth 20
}

function Ensure-SystemImage {
    $sdkmanager = Require-Command 'sdkmanager'
    $licenses = 1..20 | ForEach-Object { 'y' }
    $licenses | & $sdkmanager --licenses *> $null
    if ($LASTEXITCODE -notin @(0, 1)) {
        throw 'Android SDK license acceptance failed.'
    }
    & $sdkmanager --install $SystemImage
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to install Android system image: $SystemImage"
    }
}

$repo = [System.IO.Path]::GetFullPath($RepoRoot)
$input = [System.IO.Path]::GetFullPath($InputImage)
if (-not (Test-Path -LiteralPath $input -PathType Leaf)) {
    throw 'Input image was not found.'
}
$flutter = Require-Command 'flutter'
$dart = Require-Command 'dart'
Push-Location $repo
try {
    Run $flutter @('pub', 'get') | Out-Null
} finally {
    Pop-Location
}

$inputInfo = Get-ImageMetadata $input
$inputPixels = [long]$inputInfo.pixels
if ($inputPixels -lt 40000000) {
    throw "Input is $inputPixels pixels; use a real high-resolution image of at least 40 MP."
}
if ($inputInfo.format -notin @('JPEG', 'PNG', 'WEBP')) {
    throw "Unsupported source image format for this acceptance: $($inputInfo.format)"
}
$inputHasGps = [bool]$inputInfo.gpsPresent
$finalInputContract =
    -not $AllowInputWithoutGps -and
    $inputInfo.format -eq 'JPEG' -and
    $inputHasGps
if (-not $finalInputContract -and -not $AllowInputWithoutGps) {
    throw 'Final acceptance requires a GPS-bearing JPEG input.'
}
if ($RequireInputGps -and -not $inputHasGps) {
    throw 'RequireInputGps was specified, but no GPS metadata was found.'
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$runDirectory = [System.IO.Path]::GetFullPath(
    (Join-Path $repo ".acceptance/privacy-stamp-high-resolution-$stamp")
)
New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null
$lockPath = Join-Path (
    [System.IO.Path]::GetFullPath((Join-Path $repo '.acceptance'))
) '.local-acceptance.lock'
$lock = $null
$emulatorProcess = $null
$checks = [System.Collections.Generic.List[object]]::new()
$memorySamples = [System.Collections.Generic.List[object]]::new()
$orientationConfirmed = $false
$maskConfirmed = $false
$pickerCancelConfirmed = $false
$backDiscardConfirmed = $false
$lifecycleConfirmed = $false
$temporaryFilesConfirmed = $false
$result = 'BLOCKER'

function Check([string]$Name, [bool]$Passed, [string]$Detail) {
    $checks.Add(
        [ordered]@{
            name = $Name
            status = $(if ($Passed) { 'PASS' } else { 'FAIL' })
            detail = $Detail
        }
    )
}

try {
    New-Item -ItemType Directory -Path (Split-Path -Parent $lockPath) -Force |
        Out-Null
    try {
        $lock = [System.IO.File]::Open(
            $lockPath,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None
        )
    } catch {
        throw 'Another local acceptance run appears active.'
    }

    $adb = Require-Command 'adb'
    $emulator = Require-Command 'emulator'
    $devices = (Run $adb @('devices')).Lines
    $deviceOnline = $devices |
        Where-Object { $_ -match "^$([regex]::Escape($Serial))\s+device$" }

    if (-not $deviceOnline) {
        $avds = (Run $emulator @('-list-avds')).Lines
        if ($AvdName -notin $avds) {
            if ($SkipAvdCreation) {
                throw "AVD $AvdName is missing and -SkipAvdCreation was supplied."
            }
            Ensure-SystemImage
            $avdmanager = Require-Command 'avdmanager'
            $create = "no`n" |
                & $avdmanager create avd --force --name $AvdName `
                    --package $SystemImage --device 'pixel_2' 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw 'AVD creation failed.'
            }
        }
        $port = [int]($Serial -replace '^emulator-', '')
        $arguments = @(
            '-avd', $AvdName,
            '-port', "$port",
            '-memory', "$RamMb",
            '-gpu', 'swiftshader_indirect',
            '-no-snapshot',
            '-no-boot-anim'
        )
        if (-not $KeepAvdData) { $arguments += '-wipe-data' }
        $emulatorProcess = Start-Process -FilePath $emulator `
            -ArgumentList $arguments -PassThru
        & $adb -s $Serial wait-for-device | Out-Null
    }

    Wait-Boot
    Check 'Low-memory AVD' $true `
        "$AvdName booted with requested RAM $RamMb MB on $Serial."
    Check 'Final input contract' $finalInputContract $(
        if ($finalInputContract) {
            'GPS-bearing JPEG input confirmed.'
        } else {
            'Exploratory input cannot produce a final PASS.'
        }
    )

    Adb @('logcat', '-c') | Out-Null
    if (-not $SkipBuild -and [string]::IsNullOrWhiteSpace($ApkPath)) {
        Push-Location $repo
        try {
            $build = Run $flutter @('build', 'apk', '--debug')
            $build.Lines | Set-Content -LiteralPath (
                Join-Path $runDirectory 'flutter-build.log'
            ) -Encoding utf8
            $ApkPath = Join-Path $repo `
                'build/app/outputs/flutter-apk/app-debug.apk'
        } finally {
            Pop-Location
        }
    }
    if ([string]::IsNullOrWhiteSpace($ApkPath)) {
        throw 'Specify -ApkPath or omit -SkipBuild.'
    }
    $ApkPath = [System.IO.Path]::GetFullPath($ApkPath)
    if (-not (Test-Path -LiteralPath $ApkPath)) {
        throw 'APK was not found.'
    }
    Adb @('install', '-r', '-t', $ApkPath) | Out-Null
    Check 'APK install' $true 'APK installed successfully.'

    $extension = [System.IO.Path]::GetExtension($input).ToLowerInvariant()
    $deviceInput = "/sdcard/Download/privacy-stamp-input$extension"
    Adb @('push', $input, $deviceInput) | Out-Null
    $baseline = @(DeviceFileSnapshot)

    Adb @('shell', 'am', 'force-stop', $PackageName) | Out-Null
    Adb @('logcat', '-c') | Out-Null
    Adb @(
        'shell', 'monkey', '-p', $PackageName,
        '-c', 'android.intent.category.LAUNCHER', '1'
    ) | Out-Null
    Start-Sleep -Seconds 2
    $exportPid = Get-SingleAppPid
    [void]$memorySamples.Add((Get-CurrentMemorySample -ExpectedPid $exportPid))

    if (-not $NonInteractive) {
        Write-Host ''
        Write-Host `
            'Cancel the picker once, reopen it, select the private image, verify orientation, add a visible mask, test back/discard, then export.' `
            -ForegroundColor Cyan
        Write-Host `
            'Save into Download, Pictures, or DCIM. The script detects exactly one new or modified PNG.' `
            -ForegroundColor Cyan
    }

    $outputDevicePath = $ExpectedOutputDevicePath
    $deadline = (Get-Date).AddSeconds($OutputWaitSeconds)
    do {
        [void]$memorySamples.Add((Get-CurrentMemorySample -ExpectedPid $exportPid))
        $current = @(DeviceFileSnapshot)
        $candidate = Select-PrivacyStampExportCandidate `
            -Baseline $baseline `
            -Current $current `
            -InputDevicePath $deviceInput `
            -ExpectedOutputDevicePath $ExpectedOutputDevicePath
        if ($null -ne $candidate) {
            $outputDevicePath = $candidate.Path
            break
        }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)

    if (-not $outputDevicePath) {
        throw "No exported PNG was detected within $OutputWaitSeconds seconds."
    }
    [void]$memorySamples.Add((Get-CurrentMemorySample -ExpectedPid $exportPid))
    $processAliveAfterExport = (Get-SingleAppPid) -eq $exportPid

    $runtimeLogcat = Adb @('logcat', '-d', '-v', 'threadtime')
    $runtimeLogcat.Lines | Set-Content -LiteralPath (
        Join-Path $runDirectory 'runtime-logcat.txt'
    ) -Encoding utf8
    $runtimeEvents = @(
        Find-PrivacyStampFatalEvents `
            -Lines $runtimeLogcat.Lines `
            -PackageName $PackageName `
            -MonitoredPids @($exportPid)
    )

    $pulled = Join-Path $runDirectory 'exported-output.png'
    Adb @('pull', $outputDevicePath, $pulled) | Out-Null
    $outputInfo = Get-ImageMetadata $pulled
    $outputPixels = [long]$outputInfo.pixels
    $outputHasGps = [bool]$outputInfo.gpsPresent
    $outputHasSensitiveMetadata = [bool]$outputInfo.metadataContainerPresent

    Check 'Output format' ($outputInfo.format -eq 'PNG') `
        "format=$($outputInfo.format)"
    Check 'Resolution preserved' ($outputPixels -eq $inputPixels) `
        "inputPixels=$inputPixels outputPixels=$outputPixels"
    Check 'GPS removed' ($inputHasGps -and -not $outputHasGps) `
        "inputHadGps=$inputHasGps outputHasGps=$outputHasGps"
    Check 'Sensitive PNG metadata absent' (-not $outputHasSensitiveMetadata) `
        'No eXIf, tEXt, iTXt, or zTXt metadata container was detected.'

    $orientationConfirmed = Require-OperatorConfirmation `
        -Name 'Orientation review' `
        -Expected 'ORIENTATION_OK' `
        -Provided $OrientationConfirmation `
        -Prompt 'Type ORIENTATION_OK only after confirming the displayed orientation.'
    Check 'Orientation reviewed' $orientationConfirmed `
        'Operator confirmed orientation without recording image content.'

    $maskConfirmed = Require-OperatorConfirmation `
        -Name 'Visible mask review' `
        -Expected 'MASK_OK' `
        -Provided $MaskConfirmation `
        -Prompt 'Type MASK_OK only after confirming visible mask burn-in in the export.'
    Check 'Visible mask reviewed' $maskConfirmed `
        'Operator confirmed visible mask burn-in.'

    $pickerCancelConfirmed = Require-OperatorConfirmation `
        -Name 'Picker cancel review' `
        -Expected 'PICKER_CANCEL_OK' `
        -Provided $PickerCancelConfirmation `
        -Prompt 'Type PICKER_CANCEL_OK only after completing the picker cancel scenario.'
    Check 'Picker cancel reviewed' $pickerCancelConfirmed `
        'Operator confirmed picker cancel without crash or stale update.'

    $backDiscardConfirmed = Require-OperatorConfirmation `
        -Name 'Back/discard review' `
        -Expected 'BACK_DISCARD_OK' `
        -Provided $BackDiscardConfirmation `
        -Prompt 'Type BACK_DISCARD_OK only after completing back/discard and returning safely.'
    Check 'Back/discard reviewed' $backDiscardConfirmed `
        'Operator confirmed back/discard lifecycle behavior.'

    $temporaryFilesConfirmed = Require-OperatorConfirmation `
        -Name 'Temporary file review' `
        -Expected 'TEMP_FILES_OK' `
        -Provided $TemporaryFilesConfirmation `
        -Prompt 'Type TEMP_FILES_OK only after confirming no orphan temporary files remained.'
    Check 'Temporary files reviewed' $temporaryFilesConfirmed `
        'Operator confirmed no orphan temporary files were observed.'

    Adb @('shell', 'am', 'force-stop', $PackageName) | Out-Null
    Adb @('logcat', '-c') | Out-Null
    Adb @(
        'shell', 'monkey', '-p', $PackageName,
        '-c', 'android.intent.category.LAUNCHER', '1'
    ) | Out-Null
    Start-Sleep -Seconds 2
    $restartedPid = Get-SingleAppPid
    $lifecycleLogcat = Adb @('logcat', '-d', '-v', 'threadtime')
    $lifecycleLogcat.Lines | Set-Content -LiteralPath (
        Join-Path $runDirectory 'lifecycle-logcat.txt'
    ) -Encoding utf8
    $lifecycleEvents = @(
        Find-PrivacyStampFatalEvents `
            -Lines $lifecycleLogcat.Lines `
            -PackageName $PackageName `
            -MonitoredPids @($restartedPid)
    )
    Check 'Lifecycle relaunch' ($restartedPid -gt 0) `
        'App process restarted after deliberate force-stop.'

    $lifecycleConfirmed = Require-OperatorConfirmation `
        -Name 'Relaunch review' `
        -Expected 'LIFECYCLE_OK' `
        -Provided $LifecycleConfirmation `
        -Prompt 'Type LIFECYCLE_OK only after confirming clean relaunch without stale UI.'
    Check 'Relaunch reviewed' $lifecycleConfirmed `
        'Operator confirmed clean relaunch.'

    $allEvents = @($runtimeEvents + $lifecycleEvents | Sort-Object -Unique)
    $runtimeSummary = Get-PrivacyStampRuntimeSummary `
        -Samples @($memorySamples) `
        -Events $allEvents `
        -ProcessAliveAfterExport $processAliveAfterExport
    Check 'Runtime evidence' $runtimeSummary.Passed $(
        "samples=$($runtimeSummary.SampleCount) restarts=$($runtimeSummary.ProcessRestartCount) aliveAfterExport=$($runtimeSummary.ProcessAliveAfterExport) events=$($runtimeSummary.Events -join ',')"
    )

    $failed = @($checks | Where-Object { $_.status -eq 'FAIL' })
    $result = if ($failed.Count -eq 0) { 'PASS' } else { 'BLOCKER' }
    $git = Require-Command 'git'
    $head = (Run $git @('-C', $repo, 'rev-parse', 'HEAD')).Text.Trim()
    $report = [ordered]@{
        result = $result
        generatedAt = (Get-Date).ToString('o')
        repositoryHead = $head
        device = [ordered]@{
            serial = $Serial
            avd = $AvdName
            requestedRamMb = $RamMb
        }
        runtime = [ordered]@{
            sampleCount = $runtimeSummary.SampleCount
            peakTotalPssKb = $runtimeSummary.PeakTotalPssKb
            peakTotalRssKb = $runtimeSummary.PeakTotalRssKb
            peakJavaHeapKb = $runtimeSummary.PeakJavaHeapKb
            peakNativeHeapKb = $runtimeSummary.PeakNativeHeapKb
            processRestartCount = $runtimeSummary.ProcessRestartCount
            processAliveAfterExport = $runtimeSummary.ProcessAliveAfterExport
            eventTypes = @($runtimeSummary.Events)
            rawLogsIncluded = $false
        }
        input = [ordered]@{
            bytes = (Get-Item -LiteralPath $input).Length
            width = $inputInfo.width
            height = $inputInfo.height
            pixels = $inputPixels
            format = $inputInfo.format
            gpsPresent = $inputHasGps
            finalContract = $finalInputContract
            pathIncluded = $false
        }
        output = [ordered]@{
            width = $outputInfo.width
            height = $outputInfo.height
            pixels = $outputPixels
            format = $outputInfo.format
            gpsPresent = $outputHasGps
            sensitiveMetadataPresent = $outputHasSensitiveMetadata
            metadataContract = 'No eXIf, tEXt, iTXt, or zTXt chunks'
            devicePathIncluded = $false
        }
        checks = @($checks)
        humanEvidence = [ordered]@{
            orientationReviewed = $orientationConfirmed
            visibleMaskReviewed = $maskConfirmed
            pickerCancelReviewed = $pickerCancelConfirmed
            backDiscardReviewed = $backDiscardConfirmed
            relaunchReviewed = $lifecycleConfirmed
            temporaryFilesReviewed = $temporaryFilesConfirmed
            confirmationTokensIncluded = $false
        }
        privacy = [ordered]@{
            imageCommittedToRepository = $false
            exifValuesIncluded = $false
            sourcePathIncluded = $false
            devicePathsIncluded = $false
            deviceSnapshotPersisted = $false
        }
    }
    $report | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (
        Join-Path $runDirectory 'report.json'
    ) -Encoding utf8
    $markdown = @(
        '# Privacy Stamp high-resolution acceptance',
        '',
        "- Result: **$result**",
        "- Repository HEAD: $head",
        "- Device: $Serial / $AvdName / ${RamMb}MB",
        "- Input: $($inputInfo.width)x$($inputInfo.height) ($inputPixels pixels, GPS JPEG=$finalInputContract)",
        "- Output: $($outputInfo.width)x$($outputInfo.height) ($outputPixels pixels)",
        "- Runtime samples: $($runtimeSummary.SampleCount)",
        "- Peak TOTAL PSS/RSS: $($runtimeSummary.PeakTotalPssKb) / $($runtimeSummary.PeakTotalRssKb) kB",
        "- Process restarts during export: $($runtimeSummary.ProcessRestartCount)",
        "- Runtime events: $($runtimeSummary.Events -join ',')",
        "- Orientation reviewed: $orientationConfirmed",
        "- Visible mask reviewed: $maskConfirmed",
        "- Picker cancel reviewed: $pickerCancelConfirmed",
        "- Back/discard reviewed: $backDiscardConfirmed",
        "- Relaunch reviewed: $lifecycleConfirmed",
        "- Temporary files reviewed: $temporaryFilesConfirmed",
        '',
        '## Checks'
    ) + @(
        $checks | ForEach-Object {
            "- [$($_.status)] $($_.name): $($_.detail)"
        }
    )
    $markdown | Set-Content -LiteralPath (
        Join-Path $runDirectory 'report.md'
    ) -Encoding utf8
    Write-Host "Result: $result"
    Write-Host "Report: $(Join-Path $runDirectory 'report.md')"
} finally {
    if ($lock) { $lock.Dispose() }
    Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
}

if ($result -ne 'PASS') { exit 1 }
