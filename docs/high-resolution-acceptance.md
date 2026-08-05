# High-resolution and low-memory acceptance

This acceptance exercises the real Android export flow with a 40MP-or-larger image on a 1–2GB emulator. The private source image remains outside the repository.

## Prerequisites

- Flutter and Android command-line tools (`adb`, `emulator`, `avdmanager`, `sdkmanager`) on `PATH`;
- PowerShell 7;
- enough free disk for an API 35 system image, a clean low-memory AVD, and PNG export;
- a private 40MP-or-larger JPEG that contains real GPS metadata for the final acceptance run.

The runner installs the configured Android system image automatically when the AVD does not exist. Image dimensions, format, EXIF/GPS presence, and PNG metadata-container absence are checked by the repository's Dart probe using the existing `image` dependency. ExifTool is not required.

## Final run

```powershell
pwsh ./tools/local_acceptance/Invoke-PrivacyStampHighResolutionAcceptance.ps1 `
  -InputImage D:\private\camera-48mp-with-gps.jpg `
  -Serial emulator-5556 `
  -RamMb 1536
```

A source without GPS is rejected by default because that run cannot prove GPS stripping. `-AllowInputWithoutGps` is available only for explicitly non-final exploratory runs and must not be reported as final acceptance.

For non-interactive orchestration, the operator must complete the same real-device checks and provide the exact confirmation tokens:

```powershell
pwsh ./tools/local_acceptance/Invoke-PrivacyStampHighResolutionAcceptance.ps1 `
  -InputImage D:\private\camera-48mp-with-gps.jpg `
  -NonInteractive `
  -OrientationConfirmation ORIENTATION_OK `
  -MaskConfirmation MASK_OK `
  -LifecycleConfirmation LIFECYCLE_OK
```

The confirmation values are validated but never written into the report.

## Required operator sequence

Before the final export is detected, perform all of the following on the clean low-memory AVD:

1. open the picker and cancel once;
2. open the picker again and select the pushed private image;
3. verify the displayed orientation is correct;
4. place at least one clearly visible mask, including an edge-adjacent case;
5. pan, zoom, move, and resize the mask;
6. leave the editor before export and return without a crash or stale update;
7. export the PNG into Download, Pictures, or DCIM;
8. after the automated force-stop/relaunch, confirm the app restarts and no stale UI or orphan temporary file was observed.

When prompted, type `ORIENTATION_OK`, `MASK_OK`, and `LIFECYCLE_OK` only after the corresponding checks are complete.

## Automated runner sequence

The script:

1. resolves Flutter dependencies and validates that the source has at least 40 million pixels;
2. requires real input GPS by default;
3. installs the API 35 Google APIs x86_64 system image when missing;
4. creates or boots `PrivacyStamp_LowMem_API35` with the requested RAM;
5. builds, installs, and launches the exact debug APK;
6. pushes the private image to a generic Android Download path;
7. snapshots file modification time, byte size, and path for candidate export directories;
8. samples process TOTAL PSS repeatedly while selection, editing, and export are in progress;
9. detects exactly one new or modified PNG, failing closed when multiple candidates exist;
10. pulls the output into ignored `.acceptance/` evidence;
11. verifies PNG format, unchanged pixel count, no GPS, and no PNG metadata container;
12. requires explicit orientation and visible-mask confirmations;
13. force-stops and relaunches the app, then verifies that its process is alive;
14. requires explicit cancel/back/lifecycle confirmation;
15. scans logcat with package-aware context for FATAL EXCEPTION, ANR, OutOfMemoryError, fatal signal, and forced activity finish;
16. produces a privacy-safe PASS/BLOCKER report and exits non-zero for BLOCKER.

Use `-ExpectedOutputDevicePath` when the export destination is fixed. Without it, ambiguous multiple PNG candidates are a BLOCKER rather than selecting one arbitrarily. Use `-ApkPath` and `-SkipBuild` to verify an exact artifact. Use `-KeepAvdData` only for a deliberate non-clean rerun. Use `-SkipAvdCreation` when the environment must not install or create Android components.

## PASS contract

All items are mandatory:

- source contains at least 40 million pixels;
- source contains GPS metadata unless the run is explicitly exploratory;
- low-memory AVD boots with the requested RAM;
- APK installs and app launches;
- picker cancel, back, and lifecycle scenarios were completed;
- displayed orientation was reviewed;
- at least one visible mask was reviewed in the exported image;
- exactly one exported PNG is identified;
- output pixel count equals the source pixel count;
- output contains no GPS metadata;
- output contains no PNG metadata container;
- multiple TOTAL PSS samples are captured and a peak value is reported;
- force-stop/relaunch succeeds;
- no package-matched FATAL EXCEPTION, ANR, OOM, fatal signal, or forced activity finish is detected;
- every check in `report.json` is `PASS`.

## Evidence files

The ignored run directory contains:

- `report.json` and `report.md`;
- build log when the runner builds the APK;
- pre-export device file snapshot;
- final `dumpsys meminfo` output;
- logcat;
- pulled exported PNG for local visual inspection only.

Reports contain dimensions, pixel counts, RAM configuration, peak TOTAL PSS, sample count, repository HEAD, boolean human-review evidence, and PASS/BLOCKER. They do not contain the private host path, source filename, image bytes, EXIF values, coordinates, confirmation tokens, or Android output path.

The private input and pulled output must never be attached to an Issue, PR, workflow artifact, or commit. The local `.acceptance/` directory remains ignored and is never staged automatically.

## Production artifact gate

After the final application ID and signing identity are chosen, run the generic `Verify-AndroidReleaseArtifact.ps1` from the kokoitta repository against the exact Privacy Stamp APK or AAB. Do not distribute the current `com.example.privacy_stamp` debug-signed artifact.
