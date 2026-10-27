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

As of P0-08 (27 October 2026, Windows 11 build host): 117 unit and widget tests, all passing. One Windows integration test (`integration_test/`) is a device test: see MT-16.

| File | Proves |
|---|---|
| `test/app/app_test.dart` | P0-02 app shell starts on the welcome screen, NFR-01 no sign-in offered, P0-02 system theme with Montserrat |
| `test/app/theme/contrast_test.dart` | NFR-09 contrast of token pairs in light and dark, button label size, navy recording theme |
| `test/app/theme/tokens_sync_test.dart` | P0-02 generated tokens match `design/tokens.json` |
| `test/docs/third_party_notices_test.dart` | P0-08 every package in `pubspec.lock` is in `THIRD_PARTY_NOTICES.md`, the file matches `tool/licence_audit.dart` output, no package in the app is copyleft or unrecognised, fonts and brand assets covered, licence classifier cases |
| `test/data/local_database/app_database_test.dart` | P0-02 settings round trip, UTC ISO 8601 text dates, foreign keys on |
| `test/drift/app_database/migration_test.dart` | P0-09 current schema matches the latest dump, every version migrates to every later one, v1 to v2 keeps settings and seeds built-in types |
| `test/domain/domain_rules_test.dart` | FR-QUAL-02 precedence, FR-ACT-05 title format and conference timezone (with summer time), offset rule (gaps, negative, null), stored enum keys |
| `test/data/repositories/conference_repository_test.dart` | FR-CONF-01, 02, 03, 05 create and round trip, FR-QUAL-02 copy of global default, FR-QUAL-03 new-activities-only and confirmed bulk change, FR-CONF-08 edit, archive (NFR-02), deletion summary, cascade delete, FR-CONF-06 acknowledgement, FR-CONF-04 goals |
| `test/data/repositories/activity_repository_test.dart` | NFR-03 built-in types, FR-ACT-02 quick-start labels, FR-ACT-06 custom types, FR-ACT-05 numbering per type and timezone, FR-ACT-04 fields, FR-EXP-10 private reflections, FR-ACT-03 order, cascade delete |
| `test/data/repositories/media_repositories_test.dart` | FR-REC-03 sequence, FR-REC-01 row before audio, FR-QUAL-06 quality fields, FR-REC-08 states, offset rule across a call and backfill, FR-REV-04 cut ranges with undo, export job lifecycle, UTC storage in every table |
| `test/docs/docs_index_test.dart` | P0-03 every document in build guide 1.6 exists and is linked from `README.md` |
| `test/domain/capture_settings_test.dart` | FR-QUAL-05 effective encoder request per platform, Windows 96 kbps floor (ADR-002), MB per hour |
| `test/data/filesystem/m4a_inspector_test.dart` | FR-QUAL-06 codec, channels, sample rate, duration and bitrates read from M4A (moov first or last, mdhd v1, long descriptor lengths, HE-AAC, video track first). FR-REC-08 unfinalised, truncated and non-MP4 files rejected |
| `test/data/filesystem/folder_export_test.dart` | FR-EXP-06 checksums written and verified, tamper detected. FR-EXP-04 no temp files left. FR-EXP-05 sources unchanged, no overwrite, failure part way removes only the partial copy |
| `test/spikes/windows_mic_spike_test.dart` | P0-06 harness with a fake engine: FR-REC-03 stop-then-start rolling, FR-QUAL-01 reports file contents not the request, refused start recorded, FR-REC-08 unfinalised file, flat signal flag, export verified |
| `test/spikes/background_recording_spike_test.dart` | P0-04 harness with fakes: NFR-05 foreground and background level split and flat-signal flag, FR-REC-05 interruption ends the segment and logs a row, system resume and resume on return, duck ignored, open interruption closed at the end, denied mic, audio session error |
| `test/domain/recording_service_test.dart` (FR-QUAL-04 group) | P0-12 mid-recording profile change: segment ends with `quality_change`, new segment with the new profile, earlier file untouched, change kept for resume, change while paused, refused profile declined with a reason, both refused leaves `errorRecoverable` with earlier audio kept, same profile and idle are no-ops, rapid changes serialised |
| `test/spikes/profile_switch_spike_test.dart` | P0-12 harness with a fake engine: one segment per profile, observed against requested bitrate read from the file, gap per switch, declined switch reported, Windows 96 kbps floor, denied mic, JSON and Markdown |
| `test/spikes/long_run_spike_test.dart` | P0-10 harness with fakes: FR-REC-02 one sample a minute with on-disk file size, last wait shortened, AT-MEM-01 flat and rising RSS trends with warm-up excluded, too few samples, FR-QUAL-06 whole-file rate and MB per hour, stalled file, flat signal, not-recording samples, FR-REC-06 battery drain and the charging and unknown cases, refused start, JSON, CSV and Markdown, Windows battery mapping, process RSS probe |
| `integration_test/p0_10_long_run_test.dart` | P0-10 on a real low-spec phone or Windows PC (MT-19). Fails when no microphone is available |
| `test/domain/recording_service_route_test.dart` | P0-07: FR-QUAL-06 input route stored per segment, left empty when unknown or the probe fails; FR-REC-03 route change ends the segment with `route_change`, same input leaves it, `force` cuts a boundary without an active input, nothing while paused or idle; FR-REC-07 no mic left waits in `userResumeRequired`, resume after reconnect, stop still saves |
| `test/platform/audio_route_probe_test.dart` | P0-07: Android device types and iOS ports to route kinds, Windows name classification, route key, engine probe never claims an active input |
| `test/spikes/bluetooth_routing_spike_test.dart` | P0-07 harness with fakes: connect and disconnect by event, loss seen only by polling with a `route_lost` marker, no mic left then resume on reconnect, forced boundaries without an active input, events with no change, AT-QUAL-03 rows match files, other channels and rate reported, damaged segment not claimed as checked, probe failure, JSON and Markdown |
| `integration_test/p0_07_bluetooth_routing_test.dart` | P0-07 on a real phone, iPhone or Windows laptop with a Bluetooth mic (MT-20). Fails when nothing records or a row's format differs from its file |
| `test/spikes/photo_during_recording_spike_test.dart` | P0-05 harness with fakes: AT-PHO-01 photos with no audio event keep one segment, FR-PHO-01 photos at `photos/<photo_id>.jpg` with offsets, FR-PHO-07 camera interruption cuts a segment and resumes after the shot, FR-REC-05 interruption away from the camera waits for the system or resumes when allowed, camera that will not open, cameras listed when start fails, failed shot, level drop flag, gaps between segments matched to interruption rows, photo move never overwrites, JSON and Markdown |
| `integration_test/p0_05_photo_during_recording_test.dart` | P0-05 on a real phone, iPhone or Windows laptop with a camera (MT-21). Fails when nothing records, a photo is not saved, a gap has no interruption row or a camera interruption did not resume |
| `integration_test/p0_04_background_recording_test.dart` | P0-04 on a real Android phone or iPhone (MT-17). Skipped on other platforms |
| `integration_test/p0_12_profile_switch_test.dart` | P0-12 on a real phone or Windows PC (MT-18). Fails when no microphone is available |
| `integration_test/p0_06_windows_mic_test.dart` | P0-06 on real Windows hardware (MT-16). Fails when no microphone is available |

Fixtures: `test/fixtures/m4a_builder.dart` (synthetic M4A files, zero audio payload) and `test/fixtures/fixtures.dart` (fake clock, sequential IDs, `TestData` with every repository, `SampleConference` with a keynote recorded around a call).

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
| MT-17 | Background and call spike (P0-04), Android and iPhone: (1) connect the phone, run `flutter test integration_test/p0_04_background_recording_test.dart -d DEVICE_ID --dart-define=P0_04_SECONDS=300`, allow the microphone; (2) talk for 30 s with the app visible; (3) lock the screen for 60 s while talking; (4) unlock, then call the phone from a second phone and decline it; (5) call again, answer, speak for 20 s, hang up; (6) set a 1-minute alarm and let it ring; (7) wait for the run to end. Copy the printed Markdown and JSON into `PLATFORM_FEASIBILITY.md` 2.4.1, pull the audio from the report folder and listen | Test passes, locked-screen audio is audible (Android: expected silent until P1-11), the call is not in any segment, each call or alarm produced an interruption row and a new segment, resume path recorded (system or app visible) |
| MT-18 | Profile switch spike (P0-12), Android, iPhone and Windows (console session or Surface): (1) run `flutter test integration_test/p0_12_profile_switch_test.dart -d DEVICE_ID --dart-define=P0_12_SECONDS=20`, allow the microphone; (2) read a text aloud, or play a speech recording near the mic, for the whole run (about 80 s); (3) copy the printed Markdown and JSON into `PLATFORM_FEASIBILITY.md` 2.3.1; (4) pull the four segments from the report folder and listen across each switch; (5) repeat once with a Bluetooth headset connected (feeds P0-07) | Test passes. Four segments (or a declined switch with a reason), each with the requested profile stored. Observed payload kbps per profile recorded per device. Gap per switch recorded, and whether words were lost at each switch. Windows: every request is 96 kbps (ADR-002) |
| MT-19 | 90-minute low-spec run (P0-10), the lowest-RAM Android phone available, an iPhone and a Windows laptop or Surface on battery: (1) charge to at least 80%, unplug, note the battery percentage, device model, RAM and OS version; (2) run `flutter test integration_test/p0_10_long_run_test.dart -d DEVICE_ID --dart-define=P0_10_MINUTES=90`, allow the microphone; (3) keep speech playing near the mic; (4) after 5 minutes lock the screen (Windows: minimise) for 30 minutes, then unlock and use other apps (browser, camera, messages) for 30 minutes, then leave the app visible; (5) at the end note the battery percentage; (6) copy the printed Markdown into `PLATFORM_FEASIBILITY.md` 2.4.2 and keep `report.csv`; (7) listen to the start, middle and end of the file. Optional: watch memory in Android Studio Profiler, Instruments or Task Manager for comparison | Test passes, about 90 minutes recorded with no gaps except logged states, RSS trend after warm-up and peak recorded, measured MB per hour compared with the estimate, battery drop recorded with device and OS. Android locked part expected silent until P1-11 |
| MT-20 | Bluetooth routing spike (P0-07), Android, iPhone and Windows, with AirPods or similar, a typical headset and an inexpensive Bluetooth lapel mic in turn: (1) start with the headset off, run `flutter test integration_test/p0_07_bluetooth_routing_test.dart -d DEVICE_ID --dart-define=P0_07_SECONDS=180`, allow the microphone; (2) keep speech playing near the phone and the headset for the whole run; (3) at about 30 s switch the headset on and let it connect; (4) at about 70 s switch it off; (5) at about 110 s switch it on again, and at about 150 s walk out of range (around 15 m) until it drops; (6) copy the printed Markdown and JSON into `PLATFORM_FEASIBILITY.md` 2.4.3; (7) pull the segments and listen to each: note which mic each one really used, whether audio was lost at each boundary and whether the Bluetooth segments sound narrowband | Test passes (every row's codec, channels and sample rate match its file, AT-QUAL-03). Each connect and disconnect produced a `route_change` boundary, a lost mic left a `route_lost` marker and recording carried on from the built-in mic, or the recorder waited for the user. Record which changes came from device events and which only from polling, and whether the platform reported the active input |
| MT-21 | Photo during recording spike (P0-05), Android, iPhone and Windows laptop or Surface: (1) run `flutter test integration_test/p0_05_photo_during_recording_test.dart -d DEVICE_ID --dart-define=P0_05_PHOTOS=20`, allow the microphone and the camera; (2) keep steady speech playing near the device for the whole run (a podcast from another device); (3) point the camera at a printed slide or a screen; (4) copy the printed Markdown and JSON into `PLATFORM_FEASIBILITY.md` 2.7.1; (5) pull the segments and photos, listen around every shot offset for dropouts, clicks or the shutter sound, and open a few photos; (6) on iOS, repeat once with AirPods connected | Test passes (20 photos saved, no gap between segments without an interruption row, every camera interruption resumed on its own, AT-PHO-01) and no dropout is heard around any shot. Record shot times, whether any audio session event came near a shot, and whether the shutter sound is in the recording |
| MT-16 | Windows mic spike (P0-06): signed in at the console or on a Surface, run `flutter test integration_test/p0_06_windows_mic_test.dart -d windows`, listen to each segment, repeat with the microphone privacy switch off | Test passes, segments are audible AAC-LC mono, actual bitrate per request recorded in `PLATFORM_FEASIBILITY.md` 2.6.1, privacy-off behaviour recorded |

---

## 4. Acceptance tests

### 4.1 v1.0 blockers (build guide 13.3)

| ID | Test | Android | iOS | Windows |
|---|---|---|---|---|
| AT-REC-01 | 90 minutes recorded with screen locked and other apps in use. No gaps except logged interruptions. | unverified | unverified | n/a (minimised instead) |
| AT-REC-02 | Incoming call pauses and resumes (or offers resume). Call audio is never recorded. | unverified | unverified | n/a |
| AT-REC-03 | Force-kill mid-recording loses at most the current segment. Recovery offered on next launch. | unverified | unverified | unverified |
| AT-REC-04 | Starting a second recording always triggers the one-active prompt or the documented default for non-visual triggers. | unverified | unverified | unverified |
| AT-PHO-01 | 20 photos taken during a recording cause no audio loss, or each causes a logged, auto-resumed interruption. | unverified (P0-05 harness ready, MT-21) | unverified (P0-05 harness ready, MT-21) | unverified (P0-05 harness ready, MT-21) |
| AT-QUAL-01 | Three activities at Economy, Balanced and Enhanced record, play and export correctly with correct metadata. | unverified | unverified | unverified (all map to 96 kbps, ADR-002) |
| AT-QUAL-02 | Mid-recording quality change creates a new segment or declines safely. Earlier audio intact. | unverified | unverified | unverified |
| AT-QUAL-03 | Bluetooth route changes never mislabel codec or channels. | unverified (P0-07 harness ready, MT-20) | unverified (P0-07 harness ready, MT-20) | unverified (P0-07 harness ready, MT-20) |
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
| 2026-10-27 | Claude Code (unattended) | Build PC (NucBox M6 Ultra), Windows 11 Pro 26200, Remote Desktop session | 0.1.0+1 | MT-21 (automated part only, 2 photos, nobody listening) | blocked: no capture device in RDP session, start failed with "No audio recording device was found.", `camera_windows` listed no camera, no photos, one damaged row | `docs/PLATFORM_FEASIBILITY.md` 2.7.1 |
| 2026-10-27 | Claude Code (unattended) | Build PC (NucBox M6 Ultra), Windows 11 Pro 26200, Remote Desktop session | 0.1.0+1 | MT-20 (automated part only, 10 s, no headset, nobody listening) | blocked: no capture device in RDP session, start failed with "No audio recording device was found.", one damaged row, no route changes | `docs/PLATFORM_FEASIBILITY.md` 2.4.3 |
| 2026-10-27 | Claude Code (unattended) | Build PC (NucBox M6 Ultra), Windows 11 Pro 26200, Remote Desktop session | 0.1.0+1 | MT-19 (automated part only, 1 minute, nobody listening) | blocked: no capture device in RDP session, start failed with "No audio recording device was found.", no samples, battery unknown (no system battery) | `docs/PLATFORM_FEASIBILITY.md` 2.4.2 |
| 2026-10-27 | Claude Code (unattended) | Build PC (NucBox M6 Ultra), Windows 11 Pro 26200, Remote Desktop session | 0.1.0+1 | MT-18 (automated part only, nobody listening) | blocked: no capture device in RDP session, start failed with "No audio recording device was found.", no switches ran | `docs/PLATFORM_FEASIBILITY.md` 2.3.1 |
| 2026-10-27 | Claude Code (unattended) | Build PC (NucBox M6 Ultra), Windows 11 Pro 26200, Remote Desktop session | 0.1.0+1 | MT-16 | blocked: no capture device in RDP session, `start()` threw "No audio recording device was found." | `docs/PLATFORM_FEASIBILITY.md` 2.6.1 |

---

## 7. Resource budgets (build guide 12)

No figures are recorded yet. Each needs a device, OS version, date and method.

| Measure | Target | Measured |
|---|---|---|
| Disk use, 8 hours at Balanced | About 173 MB plus overhead (nominal 48 kbps) | not measured |
| Disk use, 1 hour on Windows | About 43 MB (96 kbps, ADR-002) | not measured |
| Memory during a 90-minute locked recording | No sustained growth | not measured (P0-10 harness ready, MT-19) |
| Battery during a 90-minute recording | Record what is measured | not measured |
| APK, AAB, IPA and Windows installer sizes | Record what is measured | not measured |
