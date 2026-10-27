# Attenlume

Be present. Bring ideas to light.

Attenlume (a-TEN-loom) by Samlytics Data Services is an offline-first conference capture app for Android, iOS and Windows. It records sessions, links your slide photos to the moment they were shown and bookmarks key points, so you can listen instead of typing notes. No account, network or AI model is needed for the core app.

**Status:** early development (Phase 0). Nothing here has been tested on a real phone or Surface yet. See `docs/PROGRESS.md`.

## Develop

Requires Flutter 3.47.8 stable (Dart 3.13.7). Android builds need JDK 17 and the Android SDK. iOS builds need a Mac.

```powershell
flutter pub get
dart run build_runner build     # Drift code generation
flutter analyze
flutter test
flutter run -d windows
```

Design tokens: edit `design/tokens.json`, then run `dart run tool/gen_tokens.dart` to regenerate `lib/app/theme/tokens.dart`. A test fails if you forget.

Database schema: after changing tables and bumping `schemaVersion`, run `dart run drift_dev make-migrations` and add a migration test (see `test/data/local_database/migration_test.dart`).

## Docs

- `AGENTS.md`: rules for coding agents
- `docs/BUILD_GUIDE.md`: full specification
- `docs/DESIGN_GUIDE.md`: brand, screens and tokens
- `docs/ARCHITECTURE.md`, `docs/PLATFORM_FEASIBILITY.md`, `docs/DECISIONS.md`
- `docs/PROGRESS.md`, `docs/HANDOVER.md`

## Licences

Montserrat is under the SIL Open Font License 1.1 (`assets/fonts/OFL.txt`). The project licence (MIT or Apache 2.0) is chosen in task P0-08.
