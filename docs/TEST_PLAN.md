# Test plan

**Status:** initial version from task P0-03, 27 October 2026, Claude Code (Opus 5.5). Derived from `docs/BUILD_GUIDE.md` sections 1.4, 6, 7, 12 and 13.

**Honesty rule (build guide 1.4):** nothing is claimed to work without a passing automated test or a recorded real-device check. Every device cell below is **unverified** until someone records a result with device, OS version, date, tester and evidence. No benchmark figure is entered unless it was measured.

---

## 1. How tests are named and run

- Every test name starts with the requirement or task ID it proves, for example `FR-REC-03 rolls a new segment after 10 minutes` (`AGENTS.md`).
- Unit and widget tests: `test/`, mirroring `lib/`. Integration tests: `integration_test/` (none yet).
- Commands (from the repo root):

```powershell
flutter analyze
flutter test
dart format --output=none --set-exit-if-changed lib test tool
```

- CI (`.github/workflows/ci.yml`) runs the same on Windows, plus an Android debug APK build on Ubuntu and an unsigned iOS debug build on macOS. CI has not run yet because there is no remote (ADR-001).

---

## 2. Automated tests

### 2.1 Current suite

As of P0-09 (27 October 2026, Windows 11 build host): 76 tests, all passing.

| File | Proves |
|---|---|
| `test/app/app_test.dart` | P0-02 app shell starts on the welcome screen, NFR-01 no sign-in offered, P0-02 system theme with Montserrat |
| `test/app/theme/contrast_test.dart` | NFR-09 contrast of token pairs in light and dark, button label size, navy recording theme |
| `test/app/theme/tokens_sync_test.dart` | P0-02 generated tokens match `design/tokens.json` |
| `test/data/local_database/app_database_test.dart` | P0-02 settings round trip, UTC ISO 8601 text dates, foreign keys on |
| `test/drift/app_database/migration_test.dart` | P0-09 current schema matches the latest dump, every version migrates to every later one, v1 to v2 keeps settings and seeds built-in types |
| `test/domain/domain_rules_test.dart` | FR-QUAL-02 precedence, FR-ACT-05 title format and conference timezone (with summer time), offset rule (gaps, negative, null), stored enum keys |
| `test/data/repositories/conference_repository_test.dart` | FR-CONF-01, 02, 03, 05 create and round trip, FR-QUAL-02 copy of global default, FR-QUAL-03 new-activities-only and confirmed bulk change, FR-CONF-08 edit, archive (NFR-02), deletion summary, cascade delete, FR-CONF-06 acknowledgement, FR-CONF-04 goals |
| `test/data/repositories/activity_repository_test.dart` | NFR-03 built-in types, FR-ACT-02 quick-start labels, FR-ACT-06 custom types, FR-ACT-05 numbering per type and timezone, FR-ACT-04 fields, FR-EXP-10 private reflections, FR-ACT-03 order, cascade delete |
| `test/data/repositories/media_repositories_test.dart` | FR-REC-03 sequence, FR-REC-01 row before audio, FR-QUAL-06 quality fields, FR-REC-08 states, offset rule across a call and backfill, FR-REV-04 cut ranges with undo, export job lifecycle, UTC storage in every table |
| `test/docs/docs_index_test.dart` | P0-03 every document in build guide 1.6 exists and is linked from `README.md` |

Fixtures: `test/fixtures/fixtures.dart` (fake clock, sequential IDs, `TestData` with every repository, `SampleConference` with a keynote recorded around a call).

### 2.2 Planned unit tests (build guide 13.1)

| Area | Requirement IDs | Task |
|---|---|---|
| Goals: up to three priority goals, unlimited extras, ordering | FR-CONF-04 | P0-09, P1-01 |
| Activity types: built-ins, custom types, default titles | NFR-03, FR-ACT-05, FR-ACT-06 | P0-09, P1-03 |
| Profile precedence | FR-QUAL-02, FR-QUAL-03 | P0-09, P1-09 |
| Recording state machine transitions (every edge in build guide 5.4) | FR-REC-01 to 05, 09 | P1-04 |
| Segment rolling (pause, interruption, quality, route, 10 minutes) | FR-REC-03 | P1-05 |
| Offset calculation across gaps | 9.4 offset rule | P0-09, P1-16 |
| Cut-range maths (overlap, merge, undo) | FR-REV-04 | P1-18 |
| Split logic (media and bookmarks move by offset) | FR-REV-05 | P1-18 |
| Storage estimates and thresholds | FR-STO-01, FR-STO-02 | P1-12 |
| Filename sanitisation and path length | FR-EXP-07 | P1-21 |
| Manifest, `timeline.csv`, README and prompt generation | FR-EXP-08, FR-EXP-09, section 15 | P1-22 |
| Streaming checksums with bounded memory | FR-EXP-04, FR-EXP-06 | P0-11, P1-21 |
| Preservation of originals (no code path deletes without confirmation) | NFR-07, NFR-11 | P1-19, P1-20 |
| Crash recovery reconciliation | FR-REC-08 | P1-08 |

### 2.3 Planned widget tests (build guide 13.1)

| Behaviour | Requirement IDs | Task |
|---|---|---|
| Start and stop confirmation | FR-UI-01 | P1-10 |
| One-active prompt when starting a second activity | FR-REC-04 | P1-06 |
| Permission denial flows | FR-PRI-04 | P1-10, P1-14 |
| Crash recovery prompt | FR-REC-08 | P1-08 |
| Deletion confirmation with summary | FR-CONF-08, FR-STO-06 | P1-01, P1-20 |
| Quality selector shows MB per hour and safe time left | FR-UI-08 | P1-09 |
| Consent check for conversations | FR-ACT-07 | P1-03 |
| Accessibility: semantics labels, 48 dp targets, large text | NFR-09 | P1-26 |

### 2.4 Planned integration test (build guide 13.1)

One end-to-end run on fakes for audio and camera: conference with three activities at mixed profiles, photos, bookmarks, a simulated interruption, trim, export, then re-import and compare metadata, counts and checksums. Task P1-29, depends on P1-21 and P1-23.

### 2.5 Migration tests

Every schema version gets a `SchemaVerifier` test and a data-preserving migration test from every earlier version (ADR-004). Current schema: v1.

---

## 3. Manual real-device tests (build guide 13.2)

Run on each device in section 5. Record results in section 6 with device, OS, date, tester, app version and evidence (logs, screenshots, file listings).

| ID | Scenario | Pass when |
|---|---|---|
| MT-01 | 60 to 90-minute session | One continuous timeline, segments every 10 minutes, no unlogged gaps |
| MT-02 | 8-hour conference day | Disk use measured and compared with estimates |
| MT-03 | Under 1 GB free | Warning shown |
| MT-04 | Near the hard reserve | Segment finalised, stop reason `storage_low`, earlier files intact |
| MT-05 | Airplane mode | All core workflows work |
| MT-06 | Screen lock during recording | Audio continues where the OS allows |
| MT-07 | Incoming call, answered | Segment finalised, call not recorded, resume or one-tap resume |
| MT-08 | Incoming call, declined | Same as MT-07 |
| MT-09 | Alarm | Logged interruption, resume |
| MT-10 | Bluetooth connect and disconnect mid-recording | New segment, correct route label, fallback or prompt |
| MT-11 | Permission revoked mid-recording | Segment finalised, interruption logged, user told |
| MT-12 | Low battery | Prompt at 15%, recording continues |
| MT-13 | App killed by the OS | Recovery offered on next launch, at most one segment lost |
| MT-14 | Photo burst during recording | No audio loss, or logged auto-resumed interruptions |
| MT-15 | Rapid start and stop taps | No duplicate recordings |

---

## 4. Acceptance tests

### 4.1 v1.0 blockers (build guide 13.3)

| ID | Test | Android | iOS | Windows |
|---|---|---|---|---|
| AT-REC-01 | 90 minutes recorded with screen locked and other apps in use. No gaps except logged interruptions. | unverified | unverified | n/a (minimised instead) |
| AT-REC-02 | Incoming call pauses and resumes (or offers resume). Call audio is never recorded. | unverified | unverified | n/a |
| AT-REC-03 | Force-kill mid-recording loses at most the current segment. Recovery offered on next launch. | unverified | unverified | unverified |
| AT-REC-04 | Starting a second recording always triggers the one-active prompt or the documented default for non-visual triggers. | unverified | unverified | unverified |
| AT-PHO-01 | 20 photos taken during a recording cause no audio loss, or each causes a logged, auto-resumed interruption. | unverified | unverified | unverified |
| AT-QUAL-01 | Three activities at Economy, Balanced and Enhanced record, play and export correctly with correct metadata. | unverified | unverified | unverified (all map to 96 kbps, ADR-002) |
| AT-QUAL-02 | Mid-recording quality change creates a new segment or declines safely. Earlier audio intact. | unverified | unverified | unverified |
| AT-QUAL-03 | Bluetooth route changes never mislabel codec or channels. | unverified | unverified | unverified |
| AT-STO-01 | 8-hour mixed-profile conference: measured disk use compared with shown estimates. | unverified | unverified | unverified |
| AT-STO-02 | Near-full storage: warnings shown, current segment finalised before exhaustion, reason shown, earlier files intact. | unverified | unverified | unverified |
| AT-STO-03 | Export larger than safe temp space aborts before any source is touched. | unverified | unverified | unverified |
| AT-STO-04 | Verified export then approved cleanup frees the announced space. No silent deletion. Failed export deletes nothing. | unverified | unverified | unverified |
| AT-MEM-01 | Low-RAM phone, locked-screen recording plus repeated photo workflow: no sustained memory growth, no OS kill. | unverified | unverified | n/a |
| AT-EXP-01 | Export ZIP opens on Windows and macOS. Paths within limits. README and prompt contain role, goals, outputs and every activity. Checksums validate. | unverified | unverified | unverified |
| AT-EXP-02 | Round trip: export then re-import reproduces metadata and media. | unverified | unverified | unverified |
| AT-OFF-01 | All core workflows work with no network, no account and no models. | unverified | unverified | unverified |
| AT-WIN-01 | Tagged release produces a downloadable Windows build that records, photographs and exports on a Surface. | n/a | n/a | unverified |

iOS cells cannot change from unverified until a Mac or macOS CI with signing is available (ADR-001, `RELEASE_PLAN.md`).

### 4.2 Phase 1.5 cloud tests (placeholders)

Derived from build guide 7. Detail to be written in P15-08. Not run before Phase 1.5.

| ID | Test (draft) | Status |
|---|---|---|
| AT-CLD-01 | Connect Google Drive with PKCE in the system browser. Only `drive.file` is granted. Token stored in secure storage, not in SQLite or logs. | placeholder |
| AT-CLD-02 | Connect OneDrive (personal and work or school account) with `Files.ReadWrite`, not `.All`. Blocked tenant shows a clear message. | placeholder |
| AT-CLD-03 | Structured-folder upload of a whole conference creates `Attenlume/<Conference Name>/` with no duplicate folders on repeat runs. | placeholder |
| AT-CLD-04 | Upload interrupted by losing network resumes from bytes acknowledged, without restarting the file. | placeholder |
| AT-CLD-05 | Wi-Fi only (default) queues on mobile data and starts on Wi-Fi. | placeholder |
| AT-CLD-06 | Quota full, revoked auth, 429 and 5xx responses back off and report the error without corrupting the queue. | placeholder |
| AT-CLD-07 | Completion distinguishes "uploaded" (receipt and size) from "integrity verified" (checksum). | placeholder |
| AT-CLD-08 | Upload never deletes local files. "Free local space" appears only after verified backup, with preview and confirmation. | placeholder |
| AT-CLD-09 | Disconnect wipes local tokens, revokes where possible and leaves remote files untouched. | placeholder |
| AT-CLD-10 | Uploads are throttled or paused during an active recording, and recording is never affected. | placeholder |

### 4.3 Phase 2 tests (placeholders)

Derived from build guide 6 and 8.1. Detail to be written when Phase 2 starts.

| ID | Test (draft) | Status |
|---|---|---|
| AT-HF-01 | Siri App Intent and Android tile start, stop and bookmark, respecting the one-active rule, with confirmation. Where cold start is blocked, the app opens to the recording screen instead. | placeholder |
| AT-HF-02 | Windows global hotkeys start, stop and bookmark while minimised. | placeholder |
| AT-HF-03 | Push-to-talk commands use on-device recognition only. | placeholder |
| AT-TRN-01 | Offline transcription produces `transcript.md` aligned to offsets and honouring cut ranges, with progress and cancel. | placeholder |

---

## 5. Device matrix

Every cell is **unverified**. Fill in the model, OS version and date when a device is actually tested.

| Platform | Target device | Why | Status |
|---|---|---|---|
| Android | Recent mid-range phone, Android 15 or 16 | Main Android baseline | unverified (no device yet) |
| Android | Low-RAM phone (3 to 4 GB), Android 13 | AT-MEM-01, NFR-10 | unverified (no device yet) |
| Android | Samsung or Xiaomi with aggressive battery management | 10.2 | unverified (no device yet) |
| iOS | Recent iPhone, current iOS | Main iOS baseline | unverified (needs a Mac to build) |
| iOS | Older supported iPhone | Low-spec check | unverified (needs a Mac to build) |
| Windows | Microsoft Surface (x64), touch, 150 to 200% scaling | AT-WIN-01 | unverified (no device yet) |
| Windows | Surface or other Windows on ARM | ARM64 build | unverified (no ARM64 build yet) |
| Windows | Build PC (Windows 11, x64) | Development only, not a substitute for a Surface | debug build launched, no feature tests |
| Bluetooth | AirPods or similar, typical headset, inexpensive lapel mic | AT-QUAL-03, P0-07 | unverified (no devices yet) |

---

## 6. Results log

Add one row per real-device run. Never add a row for a run that was not observed.

| Date | Tester | Device and OS | App version | Test IDs | Result | Evidence |
|---|---|---|---|---|---|---|
| | | | | | | |

---

## 7. Resource budgets (build guide 12)

No figures are recorded yet. Each needs a device, OS version, date and method.

| Measure | Target | Measured |
|---|---|---|
| Disk use, 8 hours at Balanced | About 173 MB plus overhead (nominal 48 kbps) | not measured |
| Disk use, 1 hour on Windows | About 43 MB (96 kbps, ADR-002) | not measured |
| Memory during a 90-minute locked recording | No sustained growth | not measured |
| Battery during a 90-minute recording | Record what is measured | not measured |
| APK, AAB, IPA and Windows installer sizes | Record what is measured | not measured |
