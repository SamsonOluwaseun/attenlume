# Preparing direct-download test releases

Publication requires owner approval. These commands create local artefacts only.
Keep signing configuration private; never commit keys or android/key.properties.

1. Update both pubspec.yaml and lib/app/app_version.dart, incrementing the
   version and build number. Run analysis, tests and the licence audit.
2. Android, using the existing JDK17/Android SDK/signing configuration:

   flutter build apk --release --dart-define=ATTENLUME_SUPPORT_DISTRIBUTION=android-direct

   Use normal Flutter setup, without --no-pub: running tests or Dart build hooks
   can leave a development plugin registrant, and release generation must remove
   integration_test. Do not hand-edit generated registrants or remove test deps.
3. Windows (Flutter, Visual Studio C++ toolchain and Inno Setup6 required):

   powershell -File tool/build_windows_installer.ps1 -DirectSupport -OutDir C:/dev/attenlume-release/v0.1.6

   DirectSupport is only for the reviewed directly distributed Windows build.
   Omit it for default builds. Do not enable direct flags for store/iOS packages.
4. Copy build/app/outputs/flutter-apk/app-release.apk to the release directory as
   attenlume-android.apk. Keep attenlume-windows-setup.exe alongside it.
5. Use Android SDK apksigner verify --print-certs on old and new APKs. The SHA256
   certificate must match for an in-place update. Confirm package/versionCode.
   Inspect Windows file/product version and packaged native runtime libraries.
6. Write release notes with implemented functions and explicit unverified limits.
   Generate and verify the canonical checksum manifest:

   python tool/verify_release_assets.py generate C:/dev/attenlume-release/v0.1.6
   python tool/verify_release_assets.py verify C:/dev/attenlume-release/v0.1.6

7. Commit source, refresh/check the cumulative iOS update pack and record its path
   in local handover. Mac signing/native changes must be preserved during merge.
8. Obtain owner approval for the concrete source commit and release assets before
   any remote push/tag/release creation. Upload only APK, installer and checksums,
   using release notes as the description. Verify downloaded published assets.

Local private audio, transcripts, downloaded model weights, logs, credentials and
Mac handoffs are not GitHub release assets. Device/resource/payment-receipt checks
must never be recorded as passed unless actually observed.
