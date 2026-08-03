# Privacy Stamp MVP status

## Implemented in this slice

- Flutter Android/Web project with local-only landing screen.
- Image file selection through `file_picker` on Android and Web.
- Shared normalized rectangle, detection, OCR region, and stamp contracts.
- Pure Dart rules for email, Japanese/international phone, postal code review candidates, coordinates, Luhn-valid card candidates, labelled values, and strong text-hiding mode.
- PNG re-encoding with EXIF orientation baked and fully opaque rectangular masks.
- Manual stamp addition, long-press removal, strong mode toggle, and separate-file export.
- Export count persisted in `shared_preferences`.

## Not implemented / not verified

- Android ML Kit face, OCR, and barcode adapters.
- Android share-intent receiver and system share-out.
- Web MediaPipe, Tesseract.js, and ZXing local bundled adapters.
- Automatic reinspection of the exported pixels.
- Google Play Billing purchase/restore; product ID and purchase state are not configured.
- Real Android device interaction, Chrome drag/drop, network panel audit, release APK, and merged manifest audit.
- `com.example.privacy_stamp` is a provisional package ID and must not be treated as the production ID.

The UI currently exposes only capabilities that are actually implemented; it does
not claim that the empty detector is a privacy guarantee.
