# Acceptance Test Checklist

## Device/Emulator
- **Device**: GitHub Actions Android Emulator (API 35 Google APIs, x86_64, 1536 MB RAM)
- **App**: privacy_stamp (debug build)
- **Fixture**: `test/fixtures/synthetic-high-res-avd.jpg` (generated deterministically by `tool/acceptance/generate_synthetic_fixture.dart`)

## Automated low-memory gate
The device gate runs on every pull request that changes acceptance tooling, the
fixture, harness, or integration tests:

```bash
flutter build apk --debug
flutter test -d emulator-5554 integration_test/synthetic_low_memory_acceptance_test.dart -r expanded
```

The test decodes the bundled 6000x8000 (48 MP) JPEG, requires GPS metadata on
input, drives the editor and mask action, captures the saved PNG through a test
saver, and checks equal pixel count plus absence of GPS and PNG metadata. It
uses bounded pumps rather than `pumpAndSettle()` so a continuously scheduled
frame cannot make the acceptance job hang. The emulator job reports an
automated synthetic gate; physical/private-image/Play signing acceptance is
not claimed by this test.

## Run A: Happy Path - Load & Display
- [x] A1. App launches to picker screen
- [x] A2. Synthetic fixture is pushed to Downloads
- [x] A3. Integration test harness bypasses picker and loads fixture
- [x] A4. Editor screen displays with image
- [x] A5. Image orientation/display is correct (contained within canvas)
- **Status**: Automated (unit + integration tests)

## Run B: Mask Placement & Export
- [x] B1. Tap on canvas places a manual mask
- [x] B2. Mask count increments (0 → 1)
- [x] B3. Mask is selectable and movable
- [x] B4. Export button is enabled
- [x] B5. Export completes successfully
- [x] B6. Export count increments
- **Status**: Automated (unit + integration tests)

## Run C: Error Handling
- [x] C1. Picker cancellation returns to picker without crash
- [x] C2. Decode failure shows snackbar
- [x] C3. Detection failure shows snackbar (editing still enabled)
- [x] C4. Export with no masks shows "unavailable" notice
- **Status**: Automated (unit + widget tests)
- **Boundary**: Android platform picker UI (system picker cancel/back) remains human-operator-gated in integration tests; controller-level cancellation is fully automated.

## Run D: Metadata / Export Integrity
- [x] D1. Exported PNG does not contain original JPEG metadata
- [x] D2. Exif GPS data is stripped
- [x] D3. XMP / tEXt / iTXt metadata is stripped
- [x] D4. Original filename is not inherited in output content
- [x] D5. Output decodes as valid PNG with preserved dimensions
- [x] D6. Mask pixels are burned into output at correct locations
- [x] D7. Unmasked pixels remain unchanged (alpha preserved for PNG)
- [x] D8. Source bytes are not modified by export
- [x] D9. Filename follows `privacy-stamped-<original>.png` rule
- **Status**: Automated (unit tests with synthetic 48MP JPEG fixture)
- **Boundary**: Pixel-level visual confirmation by human operator; OEM-specific metadata variants on physical devices remain exploratory.

## Test Execution
```bash
# Install app
flutter install

# Run all unit/widget tests
flutter test --reporter expanded

# Run integration tests (modern)
flutter test integration_test/editor_test.dart

# Or with flutter drive (legacy)
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/editor_test.dart \
  -d emulator-5556
```

## Evidence
- Screenshots: `.acceptance/screen_*.png`
- UI dumps: `.acceptance/ui_dump_*.xml`
- Logs: `adb -s emulator-5556 logcat -d`
