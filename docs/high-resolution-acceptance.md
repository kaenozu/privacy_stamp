# High-resolution and low-memory acceptance

This acceptance exercises the real Android export flow with a 40MP-or-larger image on a 1–2GB emulator. The private source image remains outside the repository.

## Prerequisites

- Flutter and Android command-line tools (`adb`, `emulator`, `avdmanager`, `sdkmanager`) on `PATH`;
- PowerShell 7;
- enough free disk for an API 35 system image, a clean low-memory AVD, and PNG export.

The runner installs the configured Android system image automatically when the AVD does not exist. Image dimensions, format, EXIF/GPS presence, and PNG metadata-container absence are checked by the repository's Dart probe using the existing `image` dependency. ExifTool is not required.

## Run

```powershell
pwsh ./tools/local_acceptance/Invoke-PrivacyStampHighResolutionAcceptance.ps1 `
  -InputImage D:\private\camera-48mp.jpg `
  -Serial emulator-5556 `
  -RamMb 1536 `
  -RequireInputGps
```

The script:

1. resolves Flutter dependencies and validates that the source has at least 40 million pixels;
2. optionally requires real GPS metadata so stripping is proven rather than inferred;
3. installs the API 35 Google APIs x86_64 system image when missing;
4. creates or boots `PrivacyStamp_LowMem_API35` with the requested RAM;
5. builds, installs, and launches the exact debug APK;
6. pushes the private image to Android Download;
7. waits for a newly exported PNG in Download, Pictures, or DCIM;
8. pulls the output into ignored `.acceptance/` evidence;
9. verifies PNG format, unchanged pixel count, no GPS, and no PNG metadata container;
10. captures `dumpsys meminfo` and logcat;
11. fails on matching crash, ANR, OOM, or fatal signal.

The only manual device interaction is selecting the pushed image, placing a visible mask, and choosing Export. File-system detection and all post-export checks are automatic.

Use `-ExpectedOutputDevicePath` when the export destination is fixed. Use `-ApkPath` and `-SkipBuild` to verify an exact artifact. Use `-KeepAvdData` only when a clean emulator is not required. Use `-SkipAvdCreation` when the environment must not install or create Android components.

## PASS contract

- low-memory AVD boots;
- APK installs and app launches;
- an exported PNG is produced;
- output pixel count equals the source pixel count;
- output contains no GPS latitude, longitude, or GPS position metadata;
- output contains no PNG metadata container;
- no matching crash, ANR, OOM, or fatal signal appears in logcat.

## Privacy contract

Reports include dimensions, pixel counts, byte counts, RAM configuration, repository HEAD, and PASS/BLOCKER only. They do not include the private path, image bytes, EXIF values, coordinates, timestamps, or Android output path.

The pulled output remains under ignored `.acceptance/` evidence for local inspection and is never staged automatically.

## Production artifact gate

After the final application ID and signing identity are chosen, run the generic `Verify-AndroidReleaseArtifact.ps1` from the kokoitta repository against the exact Privacy Stamp APK or AAB. Do not distribute the current `com.example.privacy_stamp` debug-signed artifact.
