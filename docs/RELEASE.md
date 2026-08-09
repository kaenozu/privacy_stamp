# Privacy Stamp — Release procedure

This document is the runbook for taking Privacy Stamp from this repository to
Google Play. It records the steps that must happen on a release machine (or in
the Play Console), in order, with the exact commands and the acceptance
criteria for each gate.

## 1. Release machine prerequisites

A machine that builds the release must have:

- Flutter stable (Dart 3.12+ per `pubspec.yaml`) with Android toolchain
  (`flutter doctor` should show Android toolchain OK).
- JDK 17 (used by the Gradle build and by `keytool`).
- `android/key.properties` present with the production upload key (see below).
  Without it, the Gradle build silently falls back to debug signing, and the
  output is NOT distributable.

Local quality gates (same as CI):

```bash
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test
```

## 2. Release signing (once per app)

The Android application ID is `com.privacy_stamp`. The release must be signed
with a dedicated upload key, never with the debug key.

```bash
cd android
keytool -genkeypair -v -keystore privacy-stamp-release.jks \
  -alias privacy_stamp -keyalg RSA -keysize 2048 -validity 10000 -storetype JKS
```

Create `android/key.properties` from `android/key.properties.example` and fill
in the real values. Keep `privacy-stamp-release.jks` and `key.properties` in a
safe place (backed up, not in git). Losing the upload key or its passwords
prevents future updates to the Play listing.

Recommended: after uploading the first AAB, use **Play App Signing** so the app
signing key is managed by Google and only the upload key stays local.

## 3. Build the release artifact

```bash
flutter build appbundle --release
```

Output: `build/app/outputs/bundle/release/app-release.aab`

Verify the artifact is signed with the upload key, not the debug key:

```bash
# Confirm the signer certificate DN (should match your keystore).
# The debug key DN contains "C=US, O=Android, CN=Android Debug".
jarsigner -verify -verbose -certs build/app/outputs/bundle/release/app-release.aab \
  | grep -A1 "Signed by"
```

Also check the merged manifest of the AAB contains the final application ID and
no unexpected permissions:

```bash
unzip -p build/app/outputs/bundle/release/app-release.aab \
  base/manifest/AndroidManifest.xml > /dev/null
# or use bundletool dump manifest on the AAB.
```

The release merged manifest should not contain `INTERNET`,
`READ_EXTERNAL_STORAGE`, or `WRITE_EXTERNAL_STORAGE`. Re-audit whenever
platform plugins change.

## 4. Google Play Console (first release)

1. Create the app in Play Console with application ID `com.privacy_stamp`.
2. Under App signing: enable Play App Signing and upload the upload-key
   certificate (public part) if requested.
3. Fill the store listing:
   - App name: **Privacy Stamp**
   - Short description and full description (see section 6).
   - Category: Photography (or Tools); content rating via the questionnaire.
   - Privacy policy URL: required by Play — host the privacy policy
     (e.g. on the LP site pattern used by other apps) and enter its URL.
4. Upload `app-release.aab` to the release track. Start with an internal test
   track, then closed testing, then production — matching the rollout used for
   the other published app in this organization.
5. Data safety form: this app does not collect or share user data; the image
   is processed locally and never uploaded. Declare accordingly, and only
   after the target audience question is answered (Play enforces declaration
   order).

## 5. Store listing copy (draft)

App name: **Privacy Stamp**

Short description (max 80 chars):
> 写真の名前・住所などの個人情報を、端末内でスタンプして隠せるアプリ

Full description (draft, expand before submission):
> Privacy Stamp は、画像の中の名前・住所・電話番号・カード番号などの
> 機密領域を、手動のスタンプで隠してから保存するためのアプリです。
> 画像は端末（アプリ）内で処理され、外部サーバーへアップロードされません。
> ・JPEG / PNG / WebP に対応
> ・スタンプの追加・移動・サイズ変更・削除
> ・別ファイルとして PNG 書き出し（元画像は変更されません）
>
> ※自動検出（顔・OCR・バーコード）は現在未実装です。公開前に必ず
> 目視で確認し、必要ならスタンプを追加してください。

## 6. Post-release checks

- Install the release build on a device (or Play internal test) and verify the
  full edit/export flow, not just a smoke launch.
- Open the app in a browser build (Flutter Web) and inspect the network panel
  to confirm no image bytes leave the device (local-only boundary).
- Confirm the store listing shows the final name, icon, and privacy policy.
- Keep `MVP_STATUS.md` and this document in sync with any change.

## 7. Definition of "release-ready" for this repository

The code is release-ready when:

- [x] Application ID is final: `com.privacy_stamp`
- [x] App label is final: "Privacy Stamp"
- [x] Release signing is wired (key.properties-based, git-ignored)
- [x] CI gates (format / analyze / test / web / android) are green
- [x] Release runbook exists (this document)
- [ ] Upload key generated and stored safely on a release machine
- [ ] AAB built with the upload key and verified (jarsigner)
- [ ] Play Console app created, App Signing enabled, listing filled
- [ ] Data safety form declared (local-only processing)
- [ ] Internal/closed test rollout passed

The unchecked items are intentional — they require the owner's credentials and
a machine with the Flutter Android toolchain, so they are executed at release
time, not committed to the repository.
