# Platform feasibility

**Status:** draft from task P0-01 (desk audit), 27 October 2026, Claude Code (Opus 5.5).
**Scope:** what the official platform documentation and candidate packages say Attenlume can do on Android, iOS and Windows. Nothing here has been tested on a real device yet. Every row in the spike matrix is **unverified** until a Phase 0 spike records a result with device, OS version, date and logs.

How to read this file:

- Section 1 is the spike results matrix. Spike tasks update it.
- Section 2 is the per-capability audit: what the docs say, the planned approach, the risk and the spike that proves it.
- Section 3 lists the official sources consulted. Every link returned HTTP 200 on 27 October 2026.
- Package versions, licences and maintenance data live in `docs/ARCHITECTURE.md` section 6.

---

## 1. Spike results matrix

Result values: **pass**, **fail**, **partial**, **blocked** (with reason), **unverified** (not run yet).

| Capability | Spike | Android | iOS | Windows | Notes |
|---|---|---|---|---|---|
| Background recording with screen locked | P0-04 | unverified | unverified | n/a (minimised: P0-06) | Needs real phone |
| Call interruption: segment finalised, call not recorded, resume | P0-04 | unverified | unverified | n/a | Needs real phone and a second phone to call it |
| Photo capture during recording, no audio loss | P0-05 | unverified | unverified | unverified | Camera may reconfigure the audio session |
| Microphone capture while minimised | P0-06 | n/a | n/a | **blocked** (no capture device in the build host's Remote Desktop session, see 2.6.1) | Harness ready: `integration_test/p0_06_windows_mic_test.dart`, manual steps MT-16 |
| AAC-LC at 32, 48, 64 kbps mono | P0-06, P0-12 | unverified | unverified | **not available per docs**, plugin source picks the nearest supported rate (2.6.1). On-device bitrate **blocked** | Windows encoder minimum is 96 kbps. AAC-LC encoder present on build host: `isEncoderSupported(aacLc)` true |
| Export to user-chosen folder | P0-06 | unverified | unverified | **partial**: streaming copy, SHA-256 verify and no-overwrite pass on the build host (unit tests). Folder picker not built yet (P1-21) | `lib/data/filesystem/folder_export.dart` |
| Bluetooth mic routing and fallback | P0-07 | unverified | unverified | unverified | Needs headset and lapel mic |
| 90-minute low-spec recording: memory, size, battery | P0-10 | unverified | unverified | unverified | No figures until measured |
| Low-storage stop and streaming export with bounded RAM | P0-11 | unverified | unverified | unverified | Export half can run in automated tests |
| Per-segment profile switch, observed bitrate | P0-12 | unverified | unverified | unverified | |
| Start recording from App Intent (iOS) or Quick Settings tile (Android) | P0-13 | unverified | unverified | n/a | Phase 2 feasibility only |
| Passthrough trimming without re-encoding | P0-14 | unverified | unverified | unverified | ADR-003 |

---

## 2. Capability audit

### 2.1 Framework

- Flutter stable supports Android, iOS and Windows as first-class targets. Installed here: Flutter 3.47.8, Dart 3.13.7 (see `docs/PROGRESS.md`).
- iOS cannot be built on this machine (no Mac, no Apple signing). The iOS project can be prepared and written, but no iOS result can be recorded until the owner has a Mac or a macOS CI runner with signing. Every iOS cell stays **blocked: needs Mac** until then.
- Windows ARM64: Flutter's Windows ARM64 support should be checked again when P1-28 builds release artefacts. Until then x64 only.

### 2.2 Audio recording (all platforms)

**Planned approach:** the `record` package (BSD-3-Clause, maintained, last release 9 October 2026) behind an `AudioCaptureEngine` interface in `lib/platform/audio_capture/`. One recorder instance per segment. Each segment is a new file. Rolling to a new segment is stop then start, never a change to a running encoder (FR-QUAL-04).

What the package documents (README, version 7.1.2):

| Feature | Android | iOS | Windows |
|---|---|---|---|
| Native back end | AudioRecord + MediaCodec, or MediaRecorder | AVFoundation | Media Foundation |
| AAC-LC to file | yes | yes | yes |
| Opus to file | yes (API 29+) | yes, but CAF container (Apple-only playback) | no |
| WAV, FLAC to file | yes (not on legacy recorder) | yes | yes |
| Pause and resume | yes | yes | yes |
| Amplitude (dBFS) for level meter and silence detection | yes | yes | yes |
| Permission check | yes | yes | **no** (handle privacy settings ourselves) |
| Input device selection | yes | automatic (BT or built-in) | yes |
| Background recording | not handled by the plugin | not handled by the plugin | n/a |

Consequences:

- The plugin does not do background recording or audio focus. That is ours: Android foreground service (2.4), iOS audio session (2.5).
- iOS has no explicit device picker in the plugin. Route is chosen by the OS. We read and show the route through `audio_session` or a thin native call (FR-REC-07).
- The plugin does not report the encoder's actual output bitrate. "Observed bitrate" (FR-QUAL-06) is computed by us after finalisation: `bytes * 8 / duration`, with the container overhead noted. Spike P0-12 checks this against a media inspector.
- Pause and resume within one file is supported, but we do not use it for a user pause: the spec rolls a new segment on pause (FR-REC-03). This keeps each file one continuous take and makes gaps explicit.

**Risk:** medium. The package is widely used, but low-bitrate AAC behaviour per device is unknown until P0-06 and P0-12.

### 2.3 Audio quality profiles and the Windows AAC limit

The build guide's profiles are AAC-LC mono at 32, 48 and 64 kbps (section 5.5).

**Windows finding (from documentation, not yet tested):** the Microsoft Media Foundation AAC encoder accepts only these output bitrates: 12 000, 16 000, 20 000 or 24 000 bytes per second, which is **96, 128, 160 or 192 kbps**. The default is 96 kbps. Input must be 16-bit PCM at 44.1 or 48 kHz, 1, 2 or 6 channels. The `record` package uses this encoder on Windows, so none of the three profiles can be met as specified.

Planned handling (FR-QUAL-05, recorded in ADR-002):

- On Windows, all three profiles map to AAC-LC mono at 96 kbps, 48 kHz (about 43.2 MB per hour). The quality selector shows the effective setting and the larger MB per hour. Segment metadata stores the requested profile and the effective bitrate separately.
- Alternatives to evaluate in P0-06 if 96 kbps is a problem: FLAC (lossless, much larger), or a bundled low-bitrate encoder (adds a dependency and a licence review). Windows devices usually have far more free storage than phones, so 96 kbps is the documented default.

Android and iOS: no documented hard floor was found at 32 to 64 kbps mono AAC-LC, but encoder support varies by device. P0-12 must query and record the observed bitrate per device.

### 2.4 Android background recording

Official rules (Android developer docs, foreground service types and background start restrictions):

- A long-running microphone capture needs a **foreground service of type `microphone`**, declared in the manifest with `android:foregroundServiceType="microphone"`.
- Permissions: `RECORD_AUDIO` (runtime), `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MICROPHONE` (Android 14+), `POST_NOTIFICATIONS` (runtime, Android 13+).
- Microphone is a "while-in-use" permission. A microphone foreground service **must be started while the app is visible** (or from one of the documented exemptions). Starting microphone capture from the background is blocked. This shapes Phase 2: a Quick Settings tile or notification action counts as a user interaction, but whether it is enough to start a new microphone service from cold must be proved in P0-13.
- Audio focus: request focus for recording, and treat focus loss (calls, other recording apps) as an interruption. Call state can also be observed, but audio focus is the documented signal for most apps.

**Planned approach:** a thin native Kotlin foreground service in `android/` started through a platform channel, owning the notification and its actions (Pause/Resume, Stop, Bookmark, Photo where allowed, FR-REC-10). `flutter_foreground_task` (MIT, active) is the fallback if writing our own service costs too much. The record package's own docs recommend it, and it has a recording example. Decision in P1-11 with an ADR.

**Risk:** medium-high. OEM battery managers (Samsung, Xiaomi) can still kill services. Must be tested on at least one such device (build guide 10.2).

### 2.5 iOS background recording and interruptions

Official rules (AVAudioSession, handling audio interruptions, UIBackgroundModes):

- `UIBackgroundModes` must include `audio`. The session category must be `playAndRecord` or `record`, activated while the app is in the foreground. Recording then continues when the screen locks.
- Interruptions (phone call, Siri, alarm) arrive as `AVAudioSession.interruptionNotification` with began and ended phases. On "ended", the app may resume only if the `shouldResume` option is set. Otherwise it must wait for the user. This matches FR-REC-05 exactly: finalise the segment on "began", resume on "ended" with `shouldResume`, otherwise show a one-tap resume.
- A phone call never gets recorded by a third-party app. iOS stops input during the call.
- The record package's background doc warns that its pause-and-resume interruption mode needs the `mixWithOthers` option. We do not rely on the plugin's mode: our `InterruptionCoordinator` listens through `audio_session` and rolls segments itself.
- Info.plist strings needed: `NSMicrophoneUsageDescription`, `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`.

**Risk:** medium. Unverifiable here: no Mac. **blocked: needs Mac and iPhone** for P0-04 on iOS.

### 2.6 Windows microphone, minimised recording and privacy

- Windows has a per-app microphone and camera privacy switch (Settings, Privacy and security). Desktop apps fall under "Let desktop apps access your microphone". If it is off, capture fails or returns silence. The `record` plugin has no permission check on Windows, so `PermissionsService` on Windows probes by starting a short capture and checking for an error or a flat signal, then shows a plain message with a link to `ms-settings:privacy-microphone`.
- Recording while minimised is normal for a Win32 app. The app keeps running. No special API needed. Sleep and hibernation stop capture: we hold a wake lock (`wakelock_plus` supports Windows) while recording and log any gap after resume.
- Free space: `GetDiskFreeSpaceExW` via the `win32` package (BSD-3-Clause).

**Risk:** low to medium. P0-06 can run its automated parts on this development PC.

### 2.6.1 Spike P0-06 results (27 October 2026)

**Host:** GMKtec NucBox M6 Ultra (AMD), Windows 11 Pro 10.0.26200, Flutter 3.47.8, `record` 7.1.2 with `record_windows` 2.3.0. This is the build PC, not a Surface. Run by Claude Code (Opus 5.5), unattended.

**What ran:** `flutter test integration_test/p0_06_windows_mic_test.dart -d windows`. The harness (`lib/spikes/windows_mic_spike.dart`) asks for four 3-second AAC-LC mono 48 kHz segments at 32, 48, 64 and 96 kbps, rolling by stop then start, then inspects each file with our own MP4 reader (`lib/data/filesystem/m4a_inspector.dart`), exports the folder and verifies `checksums.sha256`.

**Observed:**

| Check | Result |
|---|---|
| `isEncoderSupported(aacLc)` | true |
| Microphone permission (`hasPermission`) | true (the plugin always answers true on Windows) |
| `listInputDevices()` | empty list |
| `start()` at 32, 48, 64 and 96 kbps | each threw `PlatformException(Record, null, No audio recording device was found., null)` |
| Files written | none |
| Export of the (empty) segment folder and checksum verify | passed (0 files) |

**Why:** the agent runs inside Remote Desktop session 2 (`RDP-Tcp#0`, state Disconnected). The registry lists an active capture endpoint ("Microphone Array", Senary Audio), but Remote Desktop sessions only see microphones that the RDP client redirects, so Media Foundation finds no capture device. Fixing this needs someone at the PC (sign in at the console, or connect with RDP audio recording redirection on). That is outside unattended mode, so on-device capture is **blocked: needs real device session**.

**Findings that stand without a microphone:**

1. With no capture device, `record` on Windows returns an empty input list and `start()` throws a `PlatformException`. It does not hang or write a file. The app must check `listInputs()` first and show a plain "No microphone found" message (P1-10), separately from the privacy-switch case.
2. From the `record_windows` 2.3.0 source (`encoder/codec_caps.cpp`, `record/record.cpp`): when the requested channels, sample rate or bitrate are not in the encoder's capability list, the plugin picks the nearest supported entry and records with that. A 32, 48 or 64 kbps request is therefore expected to come out at 96 kbps, without an error. Source reading only: **unverified** until MT-16 is run. This is why segments must store the bitrate read back from the file (FR-QUAL-06), not the request.
3. Observed bitrate is read from the finished file: the `esds` descriptor's declared average bitrate, the `mdat` payload bitrate and the whole-file bitrate (`AudioFileInfo`). A file without a `moov` box (recording cut off before finalisation) is rejected as not finalised, never reported as good (FR-REC-08).
4. Folder export streams each file through SHA-256 in one pass with bounded memory, writes to `<name>.partial` then renames, never overwrites an existing folder and re-hashes every copy. A failure part way removes only the partial copy (unit tests, FR-EXP-04 to 06).

**Manual steps (MT-16 in `docs/TEST_PLAN.md`):** sign in at the PC's own console (or a Surface), check Settings > Privacy and security > Microphone > "Let desktop apps access your microphone" is on, then run the integration test above. Copy `report.md` from the printed folder into this section, listen to each segment, and record whether 32/48/64 kbps came out at 96 kbps. Then minimise the app during a longer recording (Phase 1 harness) and check for gaps. Repeat once with the privacy switch off and record what `record` does (error or silence).

### 2.7 Camera and the audio session (FR-PHO-07)

- `camera` 0.12.1 (flutter.dev) covers Android (CameraX implementation) and iOS. Windows needs `camera_windows` 0.3.0+1 added explicitly. `camera` does not endorse it automatically.
- Create camera controllers with `enableAudio: false`. Photos only, no video audio.
- **iOS risk:** an `AVCaptureSession` can reconfigure the shared `AVAudioSession` when it starts. If it does, recording may stop or change route. P0-05 must test 20 photos during a recording (AT-PHO-01). Mitigation options: keep audio session ownership in our code and treat any camera-caused change as an interruption with a segment boundary and auto-resume (FR-PHO-07).
- **Android:** CameraX without audio should not take audio focus. Unverified.
- **Windows:** `camera_windows` uses Media Foundation capture. Unverified whether it contends with the microphone.

### 2.8 Gallery import by time window (FR-PHO-05)

- Android and iOS: `photo_manager` 3.12.0 (Apache-2.0) supports date-range queries and Android 14+ partial access (`READ_MEDIA_VISUAL_USER_SELECTED`). If the user grants only selected photos, the time-window list shows only those, and the UI must say so.
- **Windows: `photo_manager` has no Windows support.** Planned alternative: let the user pick a folder (default: Pictures\Camera Roll), then filter files by EXIF `DateTimeOriginal`, falling back to file modified time. Document this difference.

### 2.9 Storage free-space probe (FR-STO-01 to 04)

No single maintained package covers Android, iOS and Windows:

- `storage_space` 1.4.0 (BSD-3-Clause, active) covers Android and iOS only.
- `disk_space_plus` covers Android and iOS, no verified publisher, few users. Not chosen.

**Planned approach:** `FreeSpaceProbe` interface in `lib/platform/`. Windows: `GetDiskFreeSpaceExW` through `win32`. Android: `StatFs` through a small method channel (we already need a native channel for the foreground service). iOS: `volumeAvailableCapacityForImportantUsage` through a small method channel. `storage_space` stays a fallback. On iOS the "important usage" figure is the documented one to use for user-initiated content.

### 2.10 Playback (FR-REV-01)

- `just_audio` 0.10.6 (MIT and Apache-2.0) covers Android and iOS but **not Windows**.
- Windows options: `just_audio_windows` 0.2.3 (MIT, community, last release April 2026), or `just_audio_media_kit` (Unlicense, no release since April 2025, bundles libmpv, which is large).
- Fallback: `audioplayers` 6.8.1 (MIT, covers all three).
- Decision: `just_audio` plus `just_audio_windows`, behind a `PlaybackEngine` interface so it can be swapped. Verify seeking accuracy in M4A on Windows: not done in P0-06 (no recording could be made on the build host), moved to P1-17.

### 2.11 Trimming (FR-REV-07, ADR-003 in P0-14)

- `ffmpeg_kit_flutter` is **discontinued** on pub.dev (last release September 2023). Do not use.
- `ffmpeg_kit_flutter_new` 4.6.7 is an active community fork, LGPL-3.0. LGPL needs dynamic linking and redistribution notices, and adds a large binary. Treat as a last resort, subject to the P0-08 licence review.
- Native passthrough is preferred: Android `MediaExtractor` plus `MediaMuxer`, iOS `AVAssetExportSession` with passthrough preset, Windows Media Foundation source reader plus sink writer. AAC frames are about 21 ms at 48 kHz, so passthrough cuts land on frame boundaries, close enough for speech.
- `cuts.json` export is always the fallback.

### 2.12 Export, archive and hashing

- `archive` 4.5.2 (MIT) has file-backed `InputFileStream` and `OutputFileStream`, and its ZIP encoder writes ZIP64 extra fields for entries past 4 GB (checked in the 4.5.2 source). Bounded memory still has to be measured in P0-11.
- Use the "store" method (no compression) for audio and photos. They are already compressed, and storing saves CPU and battery (FR-EXP-09).
- SHA-256 with `crypto` 3.0.8 using chunked conversion, in an isolate.
- Windows path limits: classic `MAX_PATH` is 260 characters. Reserved names (`CON`, `PRN`, `AUX`, `NUL`, `COM1` to `COM9`, `LPT1` to `LPT9`) and trailing dots or spaces are not allowed. FR-EXP-07's 180-character cap keeps exports safe when unzipped into a deep folder.

### 2.13 Pocket mode (Phase 2, spiked in P0-13)

- iOS App Intents can open the app and run an intent. Starting a microphone recording from an intent while the app is in the background is not documented as allowed. Expect to open the app to the recording screen. Live Activities (ActivityKit) need a widget extension target, which needs Xcode. **blocked: needs Mac.**
- Android Quick Settings tiles and app shortcuts can start an activity. Whether a tile tap may start a microphone foreground service directly from the background must be tested on Android 14 and later.
- Windows global hotkeys: `hotkey_manager` (MIT) has not had a release since May 2024. Re-check in Phase 2 or use `RegisterHotKey` through `win32`. Tray: `tray_manager` 0.8.0 (MIT, active).

### 2.14 Cloud (Phase 1.5, noted only)

- `flutter_appauth` covers Android, iOS and macOS, **not Windows**. Windows needs a loopback-redirect PKCE flow with the system browser. Plan this in P15-02.
- `flutter_secure_storage` 11.2.0 covers all three, using Windows credential protection on Windows.

---

## 3. Sources consulted (27 October 2026)

Flutter:
- Supported platforms: https://docs.flutter.dev/reference/supported-platforms

Android:
- Foreground service types: https://developer.android.com/develop/background-work/services/fgs/service-types
- Background start restrictions: https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start
- Partial photo and video access (Android 14): https://developer.android.com/about/versions/14/changes/partial-photo-video-access
- Audio focus: https://developer.android.com/media/optimize/audio-focus
- MediaMuxer: https://developer.android.com/reference/android/media/MediaMuxer
- Quick Settings tiles: https://developer.android.com/develop/ui/views/quicksettings-tiles

Apple:
- AVAudioSession: https://developer.apple.com/documentation/avfaudio/avaudiosession
- Handling audio interruptions: https://developer.apple.com/documentation/avfaudio/handling-audio-interruptions
- UIBackgroundModes: https://developer.apple.com/documentation/bundleresources/information-property-list/uibackgroundmodes
- AVAssetExportSession: https://developer.apple.com/documentation/avfoundation/avassetexportsession
- App Intents: https://developer.apple.com/documentation/appintents
- ActivityKit: https://developer.apple.com/documentation/activitykit

Microsoft:
- Media Foundation AAC encoder (bitrate limits): https://learn.microsoft.com/en-us/windows/win32/medfound/aac-encoder
- GetDiskFreeSpaceExW: https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-getdiskfreespaceexw
- Naming files, paths and namespaces: https://learn.microsoft.com/en-us/windows/win32/fileio/naming-a-file
- Maximum path length: https://learn.microsoft.com/en-us/windows/win32/fileio/maximum-file-path-limitation
- Camera and microphone privacy: https://support.microsoft.com/en-us/windows/windows-camera-microphone-and-privacy-a83257bc-e990-d54a-d212-b5e41beba857

Packages:
- record README (feature matrix): https://github.com/llfbandit/record/blob/main/record/README.md
- record background recording note: https://github.com/llfbandit/record/blob/main/doc/bg_recording.md
- record_windows source (capability matching): https://github.com/llfbandit/record/tree/main/record_windows/windows
- ffmpeg-kit (retired): https://github.com/arthenica/ffmpeg-kit
- pub.dev package data: queried with `tool/pub_audit.py` (see `docs/ARCHITECTURE.md` section 6)
