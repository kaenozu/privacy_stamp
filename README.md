# Privacy Stamp

Privacy Stamp is a privacy-preserving image redaction stamp MVP. Its purpose is
to help a user cover sensitive areas of one image before publishing or sharing
it, while keeping the image-processing path local to the app or browser.

## What works today

The current flow is intentionally small:

1. Choose one JPEG, PNG, or WebP image with `file_picker`.
2. Preview the image locally and add a manual black or white stamp.
3. Select a manual stamp and move, resize, or remove it with visible controls.
4. Export a separate PNG with opaque rectangular masks and baked orientation.

The exporter does not overwrite the selected source file. Export counts are
stored locally with `shared_preferences`; there is no configured billing or
enforced free-tier limit yet.

The shared model and pure-Dart rule engine define contracts for faces, OCR text,
barcodes, email, phone, postal code, card, coordinates, and labelled values.
The current platform text detector is an empty adapter, however, so selecting an
image does not currently produce automatic face/OCR/barcode masks. The strong
text-hiding mode is also only effective when a real OCR adapter supplies text
regions. Manual review is therefore required for the current MVP.

## Privacy boundary and threat model

The current application code passes selected image bytes to local Dart code and
the `image` package for decoding, masking, and PNG encoding. It contains no
application server, upload API, analytics SDK, or remote detector integration.
That supports the product statement that the image-processing path is local;
it is not a complete security or privacy certification.

The MVP is designed to reduce accidental publication of visible sensitive areas
when the user reviews and places masks. It does not protect against:

- false negatives, OCR errors, unsupported image content, or a user missing an
  unmasked area;
- screenshots, copied exports, OS/browser compromise, malicious files, or
  compromised third-party dependencies;
- metadata, hosting/CDN logs, browser extensions, or deployment configuration
  outside this repository;
- automatic detection, because face/OCR/barcode adapters are not implemented;
- release integrity, because the Android application ID is provisional and the
  current release build uses the debug signing configuration.

The source image is kept separate from the exported PNG by the current export
API. Tests re-decode exported PNGs and inspect mask/non-mask pixels and
metadata. A release merged-manifest audit found no INTERNET or external-storage
permission. Browser DevTools network inspection and deployed-host behavior are
still unverified, so do not describe the MVP as providing guaranteed redaction.

## Android and Web status

- Android has the Flutter launcher and local image/export flow. ML Kit adapters,
  share-intent receiving, system share-out, a production application ID, and
  production signing are not configured.
- Web has the Flutter web shell and local file-picker flow. MediaPipe,
  Tesseract.js, and ZXing adapters are not bundled. Chrome drag/drop, browser
  storage behavior, network-panel inspection, and deployed-host behavior are
  not verified.
- The release merged manifest has no `INTERNET`, `READ_EXTERNAL_STORAGE`, or
  `WRITE_EXTERNAL_STORAGE` permission. Re-audit if platform plugins change.

See [MVP_STATUS.md](MVP_STATUS.md) for the implementation and release checklist.

## Development

The repository requires Dart 3.12 or newer within the Flutter SDK constraint.

```bash
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test --reporter expanded
flutter build web --release
flutter build apk --debug
```

The tests cover sensitive-value rules, coordinate mapping, opaque PNG masking,
metadata stripping, controller races, and exported-pixel reinspection. They are
not privacy proof: full image editing on a real device, browser interaction,
browser network-panel inspection, and detector integration remain unverified.

The GitHub Actions workflow runs on every pull request and push to `main`:

- Flutter stable setup, Java 17 setup, and `flutter pub get`;
- format check, analyzer, and tests;
- Web release build and Android debug build;
- Android release smoke build when the current toolchain permits it;
- a step summary with gate/test/skip/warning counts, failure commands, and
  uploaded logs/build artifacts.

The release smoke APK is an inspection artifact only. It uses the repository's
current debug signing setup and provisional `com.example.privacy_stamp` ID; it
must not be distributed as a production APK.

## Direct dependencies

Runtime dependencies are `file_picker`, `image`, and `shared_preferences`, in
addition to the Flutter SDK. Development dependencies are `flutter_test` and
`flutter_lints`. The list
is kept aligned with the direct entries in `pubspec.yaml`; transitive packages
remain governed by `pubspec.lock`. License notes are in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Work required before production

Production work includes implementing and validating platform detector adapters;
making every automatic result reviewable with clear confidence and coverage
states; re-inspecting exported pixels; adding real Android and browser tests;
auditing network egress, storage, permissions, metadata, manifests, and
dependency licenses; configuring the final application ID and release signing;
and deciding the billing, share, update, rollback, support, and incident
response policies. None of those steps is implied by a passing CI build.
