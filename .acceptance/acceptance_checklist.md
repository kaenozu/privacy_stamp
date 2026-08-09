# Acceptance Test Checklist

## Device/Emulator
- **Device**: Android Emulator (API 34/35, x86_64)
- **App**: privacy_stamp (debug build)
- **Fixture**: `.acceptance/synthetic-high-res-avd.jpg` pushed to `/sdcard/Download/`

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
