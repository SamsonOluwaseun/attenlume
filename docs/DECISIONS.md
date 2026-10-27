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
