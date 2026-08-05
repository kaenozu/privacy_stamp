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
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Require-Command([string]$Name) {
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $command) { throw "Required command not found: $Name" }
    $command.Source
}

function Run([string]$File, [string[]]$Args, [switch]$AllowFailure) {
    $lines = @(& $File @Args 2>&1 | ForEach-Object { "$_" })
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "${File} exited with code ${exitCode}: $($lines -join ' ')"
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

function DeviceFiles {
    $script = 'for d in /sdcard/Download /sdcard/Pictures /sdcard/DCIM; do [ -d "$d" ] && find "$d" -type f 2>/dev/null; done | sort'
    (Adb @('shell', 'sh', '-c', $script) -AllowFailure).Lines |
        Where-Object { $_ -match '^/sdcard/' }
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
        throw "Another local acceptance run appears active: $lockPath"
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
                throw "AVD creation failed: $create"
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
        throw "APK not found: $ApkPath"
    }
    Adb @('install', '-r', '-t', $ApkPath) | Out-Null
    Check 'APK install' $true 'APK installed successfully.'

    $extension = [System.IO.Path]::GetExtension($input).ToLowerInvariant()
    $deviceInput = "/sdcard/Download/privacy-stamp-input$extension"
    Adb @('push', $input, $deviceInput) | Out-Null
    $baseline = @(DeviceFiles)
    $baseline | Set-Content -LiteralPath (
        Join-Path $runDirectory 'device-files-before.txt'
    ) -Encoding utf8

    Adb @('shell', 'am', 'force-stop', $PackageName) | Out-Null
    Adb @(
        'shell', 'monkey', '-p', $PackageName,
        '-c', 'android.intent.category.LAUNCHER', '1'
    ) | Out-Null
    Start-Sleep -Seconds 2

    if (-not $NonInteractive) {
        Write-Host ''
        Write-Host `
            "Select $deviceInput in Privacy Stamp, add a visible mask, and export the PNG." `
            -ForegroundColor Cyan
        Write-Host `
            'Save into Download, Pictures, or DCIM. The script detects and verifies the new file.' `
            -ForegroundColor Cyan
    }

    $outputDevicePath = $ExpectedOutputDevicePath
    $deadline = (Get-Date).AddSeconds($OutputWaitSeconds)
    do {
        if ($outputDevicePath) {
            $exists = (
                Adb @('shell', 'test', '-f', $outputDevicePath) -AllowFailure
            ).ExitCode -eq 0
            if ($exists) { break }
        } else {
            $current = @(DeviceFiles)
            $candidate = $current |
                Where-Object {
                    $_ -notin $baseline -and
                    $_ -ne $deviceInput -and
                    $_ -match '(?i)\.png$'
                } |
                Select-Object -Last 1
            if ($candidate) {
                $outputDevicePath = $candidate
                break
            }
        }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)

    if (-not $outputDevicePath) {
        throw "No exported PNG was detected within $OutputWaitSeconds seconds."
    }

    $pulled = Join-Path $runDirectory 'exported-output.png'
    Adb @('pull', $outputDevicePath, $pulled) | Out-Null
    $outputInfo = Get-ImageMetadata $pulled
    $outputPixels = [long]$outputInfo.pixels
    $outputHasGps = [bool]$outputInfo.gpsPresent
    $outputHasMetadata = [bool]$outputInfo.metadataContainerPresent

    Check 'Output format' ($outputInfo.format -eq 'PNG') `
        "format=$($outputInfo.format)"
    Check 'Resolution preserved' ($outputPixels -eq $inputPixels) `
        "inputPixels=$inputPixels outputPixels=$outputPixels"
    Check 'GPS removed' (-not $outputHasGps) `
        "inputHadGps=$inputHasGps outputHasGps=$outputHasGps"
    Check 'Metadata container removed' (-not $outputHasMetadata) `
        "outputMetadataContainerPresent=$outputHasMetadata"

    $meminfo = Adb @('shell', 'dumpsys', 'meminfo', $PackageName) `
        -AllowFailure
    $meminfo.Lines | Set-Content -LiteralPath (
        Join-Path $runDirectory 'meminfo.txt'
    ) -Encoding utf8
    $logcat = Adb @('logcat', '-d', '-v', 'threadtime') -AllowFailure
    $logcat.Lines | Set-Content -LiteralPath (
        Join-Path $runDirectory 'logcat.txt'
    ) -Encoding utf8
    $fatal = @(
        $logcat.Lines |
            Where-Object {
                $_ -match [regex]::Escape($PackageName) -and
                $_ -match 'FATAL EXCEPTION|ANR in|OutOfMemoryError|Fatal signal'
            }
    )
    Check 'Crash/ANR/OOM' ($fatal.Count -eq 0) $(
        if ($fatal.Count -eq 0) {
            'No matching fatal event.'
        } else {
            $fatal -join ' | '
        }
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
        input = [ordered]@{
            bytes = (Get-Item -LiteralPath $input).Length
            width = $inputInfo.width
            height = $inputInfo.height
            pixels = $inputPixels
            format = $inputInfo.format
            gpsPresent = $inputHasGps
            pathIncluded = $false
        }
        output = [ordered]@{
            width = $outputInfo.width
            height = $outputInfo.height
            pixels = $outputPixels
            format = $outputInfo.format
            gpsPresent = $outputHasGps
            metadataContainerPresent = $outputHasMetadata
            devicePathIncluded = $false
        }
        checks = @($checks)
        privacy = [ordered]@{
            imageCommittedToRepository = $false
            exifValuesIncluded = $false
            sourcePathIncluded = $false
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
        "- Input: $($inputInfo.width)x$($inputInfo.height) ($inputPixels pixels)",
        "- Output: $($outputInfo.width)x$($outputInfo.height) ($outputPixels pixels)",
        "- Input GPS present: $inputHasGps",
        "- Output GPS present: $outputHasGps",
        "- Output metadata container present: $outputHasMetadata",
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
