# Privacy audit procedure

This procedure is a release gate for the local-only image flow. It is a
procedure, not evidence that the current base or a future build has passed.
Record the exact commit SHA, build mode, artifact path, device/browser, and
date for every run. Do not put real personal data in fixtures, logs, or
screenshots.

## Android merged manifest

Run this against the exact release APK produced from the candidate commit.

```powershell
flutter build apk --release --no-pub
apkanalyzer manifest permissions build\app\outputs\flutter-apk\app-release.apk
aapt2 dump xmltree build\app\outputs\flutter-apk\app-release.apk AndroidManifest.xml > work\release-manifest.xml
```

Pass criteria for the local-only image flow:

- `android.permission.INTERNET` is absent.
- `android.permission.ACCESS_NETWORK_STATE` is absent unless a separately
  approved feature requires it.
- `android:usesCleartextTraffic` is absent or explicitly `false`.
- There are no unexpected providers, services, receivers, intent filters, or
  exported activities that introduce a data-sharing path.
- The output is from the candidate commit and not an older APK in the output
  directory.

If a future feature requires a permission, document the feature, the minimum
scope, and the approval before changing this gate. A static manifest pass does
not prove that runtime code never opens a socket.

## Web communication audit

Run a release-equivalent Web build locally, then inspect the visible flow in a
fresh Chrome profile or a clean incognito window.

1. Start the candidate build and open the local origin.
2. Open DevTools **Network**, enable **Preserve log**, clear the log, and
   filter for `Fetch/XHR`, `WS`, `beacon`, and `Other`.
3. Select an image, run detection/redaction, export the image, and repeat once
   with a transparent image and once with a malformed file.
4. Inspect every request's URL, initiator, request body, response body, and
   destination. Save the HAR only after removing local paths and any user data.

Pass criteria:

- No request is sent to an external origin during image selection, processing,
  or export.
- No image bytes, OCR text, coordinates, filenames, or metadata appear in a
  request body, query string, referrer, console message, or analytics payload.
- Any requests for the local app shell or explicitly approved local assets are
  listed separately and contain no user image data.
- Malformed input fails locally and does not trigger a retry to a remote
  service.

Record `PASS`, `FAIL`, or `NOT RUN` for each criterion. A clean Network panel
is runtime evidence for that browser session only; it is not a substitute for
the Android manifest check, dependency review, or source audit.

## Source and dependency review

Before release, review the candidate diff and dependency graph for new network,
telemetry, upload, or remote-inference code. Confirm that the exported bytes
are re-decoded locally and that the metadata/pixel tests in `test/` run on the
same commit. If an environment prevents a check, record the exact command and
reason as `NOT RUN`; do not infer a pass from a successful compile.
