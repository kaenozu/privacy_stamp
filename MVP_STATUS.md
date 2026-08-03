# Privacy Stamp MVP status

This document records the repository state, not a production readiness claim.

## Implemented

- Flutter Android/Web project with a local-only landing screen and one-image
  `file_picker` selection flow.
- In-memory image bytes passed through a shared normalized rectangle, detection,
  OCR-region, and stamp contract.
- Pure Dart rules for email, Japanese/international phone, postal-code review
  candidates, Luhn-valid card candidates, coordinates, labelled values, and an
  all-OCR-region strong mode contract.
- PNG re-encoding with EXIF orientation baked and opaque rectangular masks.
- Manual stamp addition and long-press removal.
- Separate-file export and locally persisted export count.
- Unit/widget tests for the rule engine, opaque mask export, and local-only
  landing screen.
- GitHub Actions quality gates for format, analyze, test, Web build, Android
  debug build, and a non-distributable Android release smoke build.

## Not implemented

- Android ML Kit face, OCR, and barcode adapters.
- Web MediaPipe, Tesseract.js, and ZXing local bundled adapters.
- Automatic detector execution: `DetectionService._localTextDetector` currently
  returns no recognized text regions.
- Automatic face/barcode/OCR coverage, exported-pixel reinspection, or a
  guarantee that all sensitive content is hidden.
- Android share-intent receiver and system share-out.
- Google Play Billing purchase/restore, product ID, entitlement state, or an
  enforced free-tier limit.

## Privacy and security boundary

The current application path decodes, masks, and encodes selected image bytes
locally. No server, upload API, analytics SDK, or remote detector is configured
in this repository. This is a code-level boundary, not an independently audited
privacy guarantee.

The MVP threat model covers accidental exposure of visible sensitive regions
before a user publishes an image. It does not cover false negatives, OCR or
detector errors, unsupported content, screenshots/copies, malicious files,
compromised devices or browsers, browser extensions, hosting/CDN behavior,
third-party dependency compromise, or unreviewed metadata and permission
behavior.

Manual review remains mandatory while automatic detectors are absent. The
exporter creates a separate PNG and does not overwrite the selected source, but
there is no independent output reinspection or network-egress test yet.

## Verification status

| Area | Current evidence | Status |
| --- | --- | --- |
| Formatting | `dart format --output=none --set-exit-if-changed .` | CI gate |
| Static analysis | `flutter analyze --fatal-infos` | CI gate |
| Pure Dart/widget tests | `flutter test` | CI gate |
| Web artifact | `flutter build web --release` | CI gate; browser use unverified |
| Android debug artifact | `flutter build apk --debug` | CI gate; device use unverified |
| Android release smoke | `flutter build apk --release` | CI gate when toolchain permits; not distributable |
| Privacy behavior | Rules/exporter tests only | No egress, device, browser, or reinspection test |

The workflow records command exit codes, test and skip counts, analyzer
warning/info lines, failure commands, logs, and available build artifacts in the
GitHub Actions summary and artifact bundle.

## Android/Web and release blockers

- `com.example.privacy_stamp` remains a provisional Android namespace and
  application ID.
- Release signing is still the Flutter template's debug signing configuration;
  no production keystore or release credential is configured.
- Real Android device interaction, merged manifest/permission audit, Web Chrome
  interaction, drag/drop, browser storage, deployed-host behavior, and network
  panel audit are unverified.
- Full direct and transitive third-party license texts are not bundled for a
  distribution release.
- Production work also needs detector adapters, review/coverage UX, exported
  pixel reinspection, privacy/network tests, billing/share decisions, and a
  rollback/support plan.
