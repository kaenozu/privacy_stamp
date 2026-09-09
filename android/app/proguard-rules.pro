# Privacy Stamp release keep rules.
# The Flutter Gradle plugin enables R8 for release builds and picks up this
# file automatically when present.

# ML Kit ships obfuscated and combines JNI with Task callbacks. A second R8
# pass over it breaks face detection with an NPE inside the vision internals
# (verified on-device: debug works, release without these rules fails).
# Keep the SDK, its GMS internals, and the Flutter bridge classes whole.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision** { *; }
-keep class com.google_mlkit_face_detection.** { *; }
-keep class com.google_mlkit_commons.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.internal.mlkit_vision**
-dontwarn com.google_mlkit_face_detection.**
-dontwarn com.google_mlkit_commons.**
