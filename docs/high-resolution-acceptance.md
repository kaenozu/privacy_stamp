# High-resolution and low-memory acceptance

This acceptance exercises the real Android export flow with a 40MP-or-larger image on a 1–2GB emulator. The private source image remains outside the repository.

## Prerequisites

- Flutter, `adb`, `emulator`, `avdmanager`, and Android API 35 Google APIs x86_64 system image;
- ExifTool on `PATH`;
- PowerShell 7;
- enough free disk for a clean low-memory AVD and PNG export.

## Run

```powershell
pwsh ./tools/local_acceptance/Invoke-PrivacyStampHighResolutionAcceptance.ps1 `
  -InputImage D:\private\camera-48mp.jpg `
  -Serial emulator-5556 `
  -RamMb 1536 `
  -RequireInputGps
```

The script:

1. validates that the source has at least 40 million pixels;
2. optionally requires real GPS metadata so stripping is proven rather than inferred;
3. creates or boots `PrivacyStamp_LowMem_API35` with the requested RAM;
4. builds, installs, and launches the exact debug APK;
5. pushes the private image to Android Download;
6. waits for a newly exported PNG in Download, Pictures, or DCIM;
7. pulls the output into ignored `.acceptance/` evidence;
8. verifies output format, pixel count, and GPS removal with ExifTool;
9. captures `dumpsys meminfo` and logcat;
10. fails on matching crash, ANR, OOM, or fatal signal.

The only manual device interaction is selecting the pushed image, placing a visible mask, and choosing Export. File-system detection and all post-export checks are automatic.

Use `-ExpectedOutputDevicePath` when the export destination is fixed. Use `-ApkPath` and `-SkipBuild` to verify an exact artifact. Use `-KeepAvdData` only when a clean emulator is not required.

## PASS contract

- low-memory AVD boots;
- APK installs and app launches;
- an exported PNG is produced;
- output pixel count equals the source pixel count;
- output contains no GPS latitude, longitude, or GPS position metadata;
- no matching crash, ANR, OOM, or fatal signal appears in logcat.

## Privacy contract

Reports include dimensions, pixel counts, byte counts, RAM configuration, repository HEAD, and PASS/BLOCKER only. They do not include the private path, image bytes, EXIF values, coordinates, timestamps, or Android output path.

## Production artifact gate

After the final application ID and signing identity are chosen, run the generic `Verify-AndroidReleaseArtifact.ps1` from the kokoitta repository against the exact Privacy Stamp APK or AAB. Do not distribute the current `com.example.privacy_stamp` debug-signed artifact.
