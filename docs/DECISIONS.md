# Decisions (ADR log)

Format: context, decision, alternatives, consequences.

## ADR-001: Product name, repo location and agent workflow

- **Date:** 27 October 2026. **Decided by:** owner, recorded by Claude Code (Opus 5.5).
- **Context:** `docs/BUILD_GUIDE.md` uses the working name "Conference Companion". `docs/DESIGN_GUIDE.md` (v1.3, later) names the product Attenlume. The project sat in a OneDrive folder, which syncs Flutter build output badly. The owner wants work to continue overnight using Claude Code and Google Antigravity.
- **Decision:**
  1. The product is **Attenlume** (app name, About screen, store listing). IDs: `com.samlytics.attenlume`, deep-link scheme `attenlume://`. The build guide's "Conference Companion" and `conferencecompanion://` are read as Attenlume and `attenlume://`. Confirm the IDs with the owner before the first store submission.
  2. The repo lives at `C:\dev\attenlume` (not synced). The OneDrive folder keeps the original files untouched.
  3. Local git only, branch `main`. No remote until the owner provides one. CI workflows are written but run only once pushed.
  4. Agents run unattended through `tool/overnight.ps1` (Claude Code first, then Antigravity). Rules are in the "Unattended mode" section of `AGENTS.md`.
- **Alternatives:** keep the repo in OneDrive (rejected: sync storms and file locks); GitHub now (deferred by owner).
- **Consequences:** device-dependent spikes stay blocked until the owner tests on real devices. iOS can be prepared but not built (no Mac).

## ADR-002: Initial package stack and the Windows AAC bitrate floor

- **Date:** 27 October 2026. **Decided by:** Claude Code (Opus 5.5) in unattended mode, task P0-01. Owner to review.
- **Context:** P0-01 audited candidate packages on pub.dev and the official platform docs (`docs/PLATFORM_FEASIBILITY.md`, `docs/ARCHITECTURE.md` section 6). Three findings change the build guide's assumptions: (1) the Microsoft Media Foundation AAC encoder, which `record` uses on Windows, accepts only 96, 128, 160 or 192 kbps, so the 32/48/64 kbps profiles cannot be met on Windows; (2) `just_audio` has no Windows support; (3) `photo_manager` has no Windows support, and no maintained free-space package covers all three platforms.
- **Decision:**
  1. Adopt the "chosen" list in `docs/ARCHITECTURE.md` 6.1 as the starting stack for P0-02. Pin exact versions there once builds and tests pass.
  2. On Windows, every recording profile maps to AAC-LC mono, 48 kHz, 96 kbps (about 43.2 MB per hour). The quality selector shows this effective setting. Segments store the requested profile and the effective bitrate separately (FR-QUAL-05, FR-QUAL-06). Revisit after P0-06 and P0-12.
  3. Playback on Windows uses `just_audio_windows` behind a `PlaybackEngine` interface, with `audioplayers` as the fallback.
  4. Free space uses our own `FreeSpaceProbe` interface: `win32` `GetDiskFreeSpaceExW` on Windows, small method channels on Android and iOS.
  5. Gallery import on Windows is a folder pick filtered by EXIF capture time (file modified time as fallback).
  6. Do not use `sqlite3_flutter_libs` (end of life) or `ffmpeg_kit_flutter` (discontinued).
- **Alternatives:** FLAC on Windows (lossless, several times larger); bundling a separate low-bitrate encoder (extra native dependency and licence review); `just_audio_media_kit` (stale, Unlicense, bundles libmpv); `flutter_foreground_task` instead of a native service (kept as fallback).
- **Consequences:** Windows recordings are about twice the size of Balanced on phones. Storage estimates must use the effective profile per platform. All platform code stays behind interfaces so spikes can change it.

## ADR-004: Scaffold conventions (P0-02)

- **Date:** 27 October 2026. **Decided by:** Claude Code (Opus 5.5) in unattended mode, task P0-02. Owner to review. (ADR-003 is reserved for the trimming approach, P0-14.)
- **Context:** P0-02 needed choices the build guide leaves open: Riverpod codegen or not, how Drift stores times, where static Montserrat files come from, how tokens reach Dart, and when to generate app icons.
- **Decision:**
  1. Riverpod without code generation for now (plain `Provider`). `riverpod_generator` can be added later without changing call sites much.
  2. Drift stores `DateTime` as ISO 8601 text (`store_date_time_values_as_text` in `build.yaml`), always written as UTC, matching build guide 9.4. Foreign keys are switched on in `beforeOpen`.
  3. Schema dumps in `drift_schemas/` with `drift_dev make-migrations`, verified by `SchemaVerifier` tests for every version.
  4. Montserrat static TTFs from the upstream Montserrat Project repo (`JulietaUla/Montserrat`, `fonts/ttf`, SIL OFL 1.1). The Google Fonts repo only ships the variable font now. Keep the `.woff` files for web and design use.
  5. `lib/app/theme/tokens.dart` is generated from `design/tokens.json` by `tool/gen_tokens.dart` and checked by a test, so the JSON stays the single source.
  6. App version starts at `0.1.0+1` (build guide 14: `0.x` during development).
  7. Launcher icons are **not** generated yet. The supplied icon has a transparent margin around a rounded tile, while iOS needs a full-bleed square without transparency and Android needs an adaptive foreground layer. Making those exports needs either designer-supplied exports or a careful crop, which the design guide forbids doing loosely. Deferred to the owner (open question) or a later task.
  8. CI (`.github/workflows/ci.yml`): Windows job (codegen drift check, format, analyze, test, Windows debug build), Ubuntu job (debug APK), macOS job (unsigned iOS debug build). Dormant until a remote exists (ADR-001).
- **Alternatives:** integer Unix timestamps (Drift's default, smaller but unreadable in exports and debugging); variable Montserrat font (one file, but weight mapping in Flutter needs `FontVariation` everywhere); hand-written token constants (drift from the JSON).
- **Consequences:** P0-09 builds the full schema on this database class and bumps `schemaVersion` with a migration test per version.

## ADR-005: Data model conventions (P0-09)

- **Date:** 27 October 2026. **Decided by:** Claude Code (Opus 5.5) in unattended mode, task P0-09. Owner to review.
- **Context:** P0-09 builds the build guide 9.4 tables. The guide leaves storage formats, some nullability and the FR-QUAL-03 mechanics open.
- **Decision:**
  1. **Schema v2, not a redefined v1.** v1 (`app_settings`) stays as dumped, and v2 adds the Phase 1 tables through drift's `stepByStep` helper, so the real upgrade path is tested. Phase 1.5 and 2 tables (`cloud_connections`, `cloud_export_files`, `transcripts`) arrive with their phases as new versions.
  2. **Drift standard layout for migrations.** `dart run drift_dev make-migrations` owns `drift_schemas/`, `lib/data/local_database/app_database.steps.dart` and `test/drift/app_database/generated/`. The P0-02 copies under `test/data/local_database/generated/` were removed.
  3. **Rows are domain classes.** Tables use `@UseRowClass` with the plain classes in `lib/domain/models/`, so there is no mapping layer. Partial updates take Drift companions.
  4. **Stored values.** Enums are stored by a stable snake_case key spelled as in 9.4 (`KeyedEnum`), never by Dart name or index. JSON lists (speakers, tags, requested outputs) and the export scope are JSON text. Conference start and end dates are calendar days stored as `YYYY-MM-DD` (read as UTC midnight) so they never shift between timezones. Instants stay UTC ISO 8601 text (ADR-004).
  5. **Goal text.** Drift cannot have a column getter named `text`, so the SQL column is `text` and the Dart field is `goalText`.
  6. **Built-in activity types** have fixed UUID v4 IDs (`00000000-0000-4000-8000-00000000000n`) and are seeded with insert-or-ignore on every open, so later releases can add types. Labels are "Conversation" and "Reflection" to match the FR-ACT-02 quick-start buttons, while the keys keep `business_conversation` and `personal_reflection`. Built-in types and types in use cannot be deleted (`ON DELETE RESTRICT`).
  7. **Offsets.** `bookmarks.offset_ms` is nullable like `photos.offset_ms` (the guide does not say). An event before the first segment gets a negative offset. When the first segment starts, null offsets in that activity are filled in.
  8. **FR-QUAL-03.** Changing a conference default pins activities that inherited the old default by writing it into their override. With the user's confirmed bulk change, inheriting activities without segments follow the new default instead. Explicit overrides are never changed.
  9. **Privacy default.** Activities of type `personal_reflection` are created with `is_private = true` (FR-UI-05, FR-EXP-10). The caller can override.
  10. **Deletes.** Deleting a conference or activity cascades to its database rows only. Media files are not touched by repositories. Removing them is a separate, user-confirmed step in P1 (NFR-07, AGENTS rule on originals).
  11. **Timezones.** Added `timezone` 0.11.2 (Dart team, BSD-3, pure Dart) for conference-local default titles from the bundled IANA data, offline. An unknown timezone name falls back to UTC. Detecting the device's IANA timezone needs a plugin and is left to P1-01.
  12. **Export enums.** `audio_mode` is `original`, `trimmed`, `original_with_cuts` or `none` (for text or photo scopes). `state` is `pending`, `running`, `completed`, `failed` or `cancelled`. The scope JSON shape is set in P1-21.
- **Alternatives:** redefining v1 (simpler history, but no tested upgrade path); a separate mapping layer between Drift rows and domain models (more code, no gain yet); storing the effective profile on every activity at creation (needs a new column the guide does not list).
- **Consequences:** every schema change is a new version with a dump and a migration test. Renaming an enum key needs a data migration.
