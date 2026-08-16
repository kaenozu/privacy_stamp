# High-resolution and low-memory acceptance

This acceptance exercises the real Android export flow with a private GPS-bearing 40MP-or-larger JPEG on a clean 1–2GB emulator. The private source image remains outside the repository.

## Prerequisites

- Flutter and Android command-line tools (`adb`, `emulator`, `avdmanager`, `sdkmanager`) on `PATH`;
- PowerShell 7;
- enough free disk for an API 35 system image, a clean low-memory AVD, and PNG export;
- a private GPS-bearing JPEG with at least 40 million pixels.

The runner installs the configured Android system image automatically when the AVD does not exist. Image dimensions, format, EXIF/GPS presence, and sensitive PNG metadata are checked by repository probes. ExifTool is not required.

## Final run

```powershell
pwsh ./tools/local_acceptance/Invoke-PrivacyStampHighResolutionAcceptance.ps1 `
  -InputImage D:\private\camera-48mp-with-gps.jpg `
  -Serial emulator-5556 `
  -RamMb 1536
```

Final acceptance requires a GPS-bearing JPEG. `-AllowInputWithoutGps` is exploratory only: the runner records a failed final-input check and cannot return `PASS`.

For non-interactive orchestration, the operator must complete the same Android UI checks and provide all exact confirmation tokens:

```powershell
pwsh ./tools/local_acceptance/Invoke-PrivacyStampHighResolutionAcceptance.ps1 `
  -InputImage D:\private\camera-48mp-with-gps.jpg `
  -NonInteractive `
  -OrientationConfirmation ORIENTATION_OK `
  -MaskConfirmation MASK_OK `
  -PickerCancelConfirmation PICKER_CANCEL_OK `
  -BackDiscardConfirmation BACK_DISCARD_OK `
  -LifecycleConfirmation LIFECYCLE_OK `
  -TemporaryFilesConfirmation TEMP_FILES_OK
```

Confirmation values are validated but never written into the report.

## Required operator sequence

Perform all of the following on a clean low-memory AVD:

1. open the picker and cancel once;
2. open the picker again and select the pushed private image;
3. verify the displayed orientation is correct;
4. place at least one clearly visible mask, including an edge-adjacent case;
5. pan, zoom, move, and resize the mask;
6. leave the editor with back/discard and return without a crash or stale update;
7. select the image again, recreate the mask, and export the PNG into Download, Pictures, or DCIM;
8. inspect the locally pulled PNG and confirm that the mask is visibly burned in;
9. confirm no orphan temporary file was observed;
10. after the automated force-stop/relaunch, confirm clean startup without stale UI.

Only type a confirmation token after its scenario has been completed.

## Automated runner sequence

The script:

1. resolves Flutter dependencies and validates a GPS-bearing JPEG with at least 40 million pixels;
2. installs the API 35 Google APIs x86_64 system image when missing;
3. creates or boots `PrivacyStamp_LowMem_API35` with the requested RAM;
4. builds, installs, and launches the exact debug APK;
5. pushes the private image to a generic Android Download path;
6. keeps the candidate-file baseline in memory and never persists device paths or filenames;
7. records the exact app PID and samples PSS, RSS, Java heap, and native heap before and throughout export;
8. fails immediately if the process disappears or its PID changes before export completes;
9. detects exactly one new or modified PNG and fails closed for zero or multiple candidates;
10. captures and evaluates pre-relaunch runtime logcat before the deliberate force-stop;
11. pulls the output into ignored `.acceptance/` evidence;
12. verifies PNG format, unchanged pixel count, GPS removal, and absence of `eXIf`, `tEXt`, `iTXt`, and `zTXt` chunks;
13. requires separate orientation, mask, picker-cancel, back/discard, temporary-file, and relaunch confirmations;
14. clears logcat after the deliberate force-stop, relaunches the app, and evaluates the new process separately;
15. detects FATAL EXCEPTION, ANR, OutOfMemoryError, fatal signal, process death, low-memory kill, and forced activity finish by package or monitored PID;
16. aggregates at least two memory samples, peak PSS/RSS/heaps, PID restart count, process liveness, and event types;
17. produces a privacy-safe PASS/BLOCKER report and exits non-zero for BLOCKER.

Use `-ExpectedOutputDevicePath` only when the export destination is known in advance. Without it, ambiguous multiple PNG candidates are a BLOCKER. Use `-ApkPath` and `-SkipBuild` to verify an exact artifact. Use `-KeepAvdData` only for a deliberate non-clean exploratory rerun. Use `-SkipAvdCreation` when the environment must not install or create Android components.

## PASS contract

All items are mandatory:

- source is a GPS-bearing JPEG with at least 40 million pixels;
- low-memory AVD boots with the requested RAM;
- APK installs and app launches;
- picker cancel, back/discard, and clean relaunch are separately confirmed;
- displayed orientation is confirmed;
- at least one visible burned-in mask is confirmed in the pulled output;
- absence of orphan temporary files is confirmed;
- exactly one exported PNG is identified;
- output pixel count equals source pixel count;
- output contains no GPS metadata;
- output contains no `eXIf`, `tEXt`, `iTXt`, or `zTXt` chunk;
- at least two process memory samples are captured;
- PID remains stable until export completes;
- process remains alive after export;
- peak PSS/RSS/Java heap/native heap are aggregated when available;
- no package- or PID-matched fatal, ANR, OOM, process-death, or low-memory-kill event is detected;
- every check in `report.json` is `PASS`.

## Metadata contract

The PNG probe enforces a sensitive-metadata contract rather than claiming that all ancillary chunks are absent. A final output must contain no:

- `eXIf` chunk;
- `tEXt` chunk;
- `iTXt` chunk;
- `zTXt` chunk;
- GPS evidence detected inside those containers.

Structural and rendering chunks such as `IHDR`, `IDAT`, and `IEND` are expected. The report must use the wording “sensitive metadata absent,” not “all metadata absent.”

## Evidence files

The ignored local run directory contains:

- `report.json` and `report.md`;
- build log when the runner builds the APK;
- pre-relaunch runtime logcat;
- post-relaunch lifecycle logcat;
- pulled exported PNG for local visual inspection only.

The candidate-file baseline is not written to disk. Reports contain dimensions, pixel counts, RAM configuration, memory peaks, sample count, restart count, event types, repository HEAD, boolean human-review evidence, and PASS/BLOCKER. They do not contain the private host path, source filename, image bytes, EXIF values, coordinates, confirmation tokens, Android output path, or raw log lines.

The private input, pulled output, and local logs must never be attached to an Issue, PR, workflow artifact, or commit. The local `.acceptance/` directory remains ignored and is never staged automatically.

## Production artifact gate

The final application ID is `com.privacy_stamp`. Verify the exact Privacy Stamp APK or AAB with the repository release runner, and never distribute a debug-signed artifact.
