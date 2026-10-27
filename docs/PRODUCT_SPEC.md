# Product specification

**Status:** initial version from task P0-03, 27 October 2026, Claude Code (Opus 5.5). Derived from `docs/BUILD_GUIDE.md` sections 2, 5 and 11 and `docs/DESIGN_GUIDE.md`. The build guide stays the source of truth: if the two disagree, the build guide wins and this file is corrected.

**Product name:** Attenlume (ADR-001). Where the build guide says "Conference Companion", read Attenlume.

**Scope:** v1.0, the free offline core (Phase 1). Cloud export (Phase 1.5), pocket mode and transcription (Phase 2) and opt-in AI (Phase 3) are listed only where they change a v1.0 journey.

Nothing in this file is implemented yet. Status of each requirement lives in `docs/PROGRESS.md` and `docs/TEST_PLAN.md`.

---

## 1. Who it is for

Conference attendees, researchers, architects, consultants, students, executives and exhibitors who go to several events a year (build guide 2.3).

It is **not** a covert recording tool, a journalist's camera system, a meeting bot or a cloud transcription service (build guide 2.4). Anything that makes recording less visible to the people around the user is out of scope.

### 1.1 Reference persona

Build guide 2.5: a senior data architect at a health-security conference. Goals: how data architecture supports programme replication, interoperability and responsible AI. They start a session, put the phone away and listen, photograph useful slides, have a short recorded conversation with a speaker who agreed, trim the walk between rooms afterwards and export the whole event for their own review or an AI tool.

---

## 2. User journeys

Each journey lists its steps, the requirements it exercises and the acceptance tests that prove it. Screen numbers refer to build guide 11.

### J1. Set up a conference in under 30 seconds

1. Open the app. Welcome screen offers "Create a conference" and "Open previous". No sign-in (NFR-01).
2. Type a name and tap create. Everything else is optional (FR-CONF-01).
3. Acknowledge the recording policy notice: "Some events and speakers don't allow recording. Record only when permitted." (FR-CONF-06).
4. Land on the conference home with "Start activity" as the dominant action (FR-ACT-01).
5. Later: add dates, location, timezone, role, goals, expected outputs and the default recording profile (FR-CONF-02 to 05, 07). Edit any field at any time (FR-CONF-08).

Requirements: FR-CONF-01 to 08, FR-ACT-01, NFR-01, NFR-02.
Tests: FR-CONF widget and unit tests (P1-01), AT-OFF-01.

### J2. Capture a session

1. On conference home, tap "Start activity" or a quick-type button (Session, Conversation, Exhibit, Reflection) (FR-ACT-02).
2. Optionally pick the quality before recording. The selector shows MB per hour and estimated safe time left (FR-UI-08).
3. Tap Record. Metadata is stored before audio is written (FR-REC-01). The recording screen shows the title, timer, mic route, level meter, storage budget and the always-visible recording banner (FR-UI-01, 02, 06, 07, FR-PRI-02).
4. Lock the phone and listen. Audio continues where the OS allows (NFR-05). On Android a persistent notification offers Pause, Stop and Bookmark (FR-REC-10).
5. Tap Photo when a useful slide appears. The photo is stored with timestamp and offset, and the shutter stays ready (FR-UI-03, FR-PHO-01). Audio is not lost (FR-PHO-07).
6. Tap Bookmark, optionally with a label chip (FR-UI-04, FR-BMK-01).
7. Tap Stop. The activity is saved with its segments.

Requirements: FR-ACT-02 to 05, FR-UI-01 to 08, FR-REC-01 to 03, 09, 10, FR-PHO-01 to 03, 07, FR-BMK-01, FR-QUAL-02, 06.
Tests: AT-REC-01, AT-PHO-01, AT-QUAL-01.

### J3. Record a conversation with consent

1. Start an activity of type Business conversation or Networking.
2. Before recording, the app asks: "Does the other person know you are recording?" with "Yes" and "Not recording audio" (FR-ACT-07, FR-PRI-01).
3. "Not recording audio" keeps the activity for notes, photos and contact details only.
4. Optionally add the contact's details by hand and a follow-up action (FR-ACT-08). No facial recognition or automatic identity extraction.
5. The activity can be marked private, which excludes it from exports by default (FR-EXP-10).

Requirements: FR-ACT-07, 08, FR-PRI-01, FR-EXP-10.

### J4. Switching activities while recording

1. A recording is running in "Data mesh in practice".
2. The user starts another activity from the UI, notification or (Phase 2) a shortcut.
3. From the UI the app asks: "'Data mesh in practice' is still recording (47 min). Stop it and start a new one?" with Stop and start new / Keep it running / Cancel (FR-REC-04).
4. From a non-visual trigger the default is stop old, start new, then confirm by notification.
5. There is never more than one active recording (NFR-04).

Requirements: FR-REC-04, FR-REC-09, NFR-04. Tests: AT-REC-04.

### J5. Interruptions

1. A call arrives while recording. The current segment is finalised, the interruption is logged and the call is never recorded (FR-REC-05).
2. The user sees "Recording paused for a call. It will carry on when you hang up."
3. When the call ends, recording resumes through OS-supported means and the user is told "Recording resumed". If the OS does not allow it: "Couldn't resume after the call. Tap to carry on recording."
4. Same pattern for alarms, other apps taking audio focus, camera conflicts, Bluetooth route loss (fall back with a timeline marker or pause with a prompt, FR-REC-07) and permission revocation.

Requirements: FR-REC-05, 07, FR-PHO-07, NFR-06. Tests: AT-REC-02, AT-QUAL-03.

### J6. Running out of space

1. Storage budget is checked before recording, every 30 seconds while recording, after each photo and before trim and export (FR-STO-03).
2. Warning below 1 GB or under 60 minutes left, urgent warning near 300 MB (FR-STO-02). Example: "About 45 minutes of space left at Balanced quality."
3. At the hard reserve the current segment is finalised, earlier files are kept, stop reason `storage_low` is stored and the user sees "Storage nearly full. Recording stopped and saved." (FR-STO-04).

Requirements: FR-STO-01 to 04, FR-UI-07, NFR-11. Tests: AT-STO-01, AT-STO-02.

### J7. Crash or force-kill

1. The OS kills the app mid-recording.
2. On next launch the app reconciles the database with segment files and offers recovery for orphaned or unfinalised segments (FR-REC-08).
3. At most the current segment is lost. Damaged files are never marked good.

Requirements: FR-REC-03, 08. Tests: AT-REC-03.

### J8. Review and trim

1. Open an activity. Player with play/pause, scrub, 15-second skips and speed (FR-REV-01).
2. Timeline shows segments, gaps, interruption markers, photos and bookmarks at their offsets (FR-REV-02), with a waveform built from summaries (FR-REV-03).
3. Trim start and end, exclude middle ranges. Trims are metadata with undo (FR-REV-04, NFR-07).
4. Split at the playhead if one recording covered two sessions (FR-REV-05).
5. "Apply trims permanently" is a separate confirmed action that writes new files and only then offers to remove originals (FR-REV-06).

Requirements: FR-REV-01 to 07, NFR-07.

### J9. Export the conference

1. Open Export. Choose scope, folder or ZIP, audio mode and whether to include private items (FR-EXP-01 to 03, 10).
2. Preflight shows size and temp space and declines safely if there is not enough (FR-EXP-05).
3. Before exporting sensitive material, the app warns (FR-PRI-05).
4. Export streams to the chosen destination and writes `checksums.sha256`, `README_START_HERE.md`, `conference.json`, `timeline.csv`, `analysis_prompt.md` and `prompts/` (FR-EXP-04, 06, 08, 09, build guide 5.10 and 15).
5. "Copy AI prompt" copies the filled-in analysis prompt.
6. Paths are safe on Windows, macOS and Linux (FR-EXP-07).

Requirements: FR-EXP-01 to 11, FR-PRI-05, NFR-08. Tests: AT-EXP-01, AT-EXP-02, AT-STO-03.

### J10. Free space after the event

1. Storage Manager shows size per conference and activity, split by kind, with export status (FR-STO-05).
2. "Delete local copies" is offered only after a verified export, with a preview and a separate confirmation (FR-STO-06). No silent deletion.

Requirements: FR-STO-05 to 07, NFR-11. Tests: AT-STO-04.

### J11. Windows and Surface

Same journeys on Windows, with a left sidebar layout, recording while minimised, export to a user-chosen folder or USB drive, and a clear message if Windows privacy settings block the microphone or camera (build guide 10.3).

Tests: AT-WIN-01.

---

## 3. User stories

Format: as a user, I want..., so that... Each story names the requirements that satisfy it.

| ID | Story | Requirements |
|---|---|---|
| US-01 | I want to create a conference with just a name, so that I can start recording when a session is about to begin. | FR-CONF-01 |
| US-02 | I want to record my role and up to three priority goals, so that the export and prompts focus on what I came to learn. | FR-CONF-03, 04, 05 |
| US-03 | I want to start recording in one tap and put my phone away, so that I can listen instead of typing notes. | FR-REC-01, NFR-05 |
| US-04 | I want photos of slides to land at the right moment in the audio, so that I can find what the speaker said about them. | FR-PHO-01, offset rule (9.4) |
| US-05 | I want to bookmark a moment without typing, so that I can come back to it later. | FR-UI-04, FR-BMK-01 |
| US-06 | I want a reminder to ask permission before recording a conversation, so that I respect the people I talk to. | FR-ACT-07, FR-PRI-01 |
| US-07 | I want the app to stop me recording two things at once by accident, so that I don't end up with overlapping or lost audio. | FR-REC-04, NFR-04 |
| US-08 | I want a call not to destroy my recording, so that I keep everything said before and after it. | FR-REC-05, NFR-06 |
| US-09 | I want to see how much recording time I have left, so that I never run out mid-keynote. | FR-UI-07, FR-STO-01 to 04 |
| US-10 | I want to choose recording quality per session, so that I can save space on quiet talks and get clarity in noisy halls. | FR-QUAL-01 to 06, FR-UI-08 |
| US-11 | I want to cut the walk between rooms without losing the original, so that I can change my mind. | FR-REV-04, NFR-07 |
| US-12 | I want to split a recording that covered two sessions, so that each session has its own notes and photos. | FR-REV-05 |
| US-13 | I want to export the whole conference as a folder or ZIP that explains itself, so that I or an AI tool can use it without the app. | FR-EXP-01 to 09, NFR-08 |
| US-14 | I want to leave private conversations out of an export with one toggle, so that I don't share them by mistake. | FR-EXP-10, FR-PRI-05 |
| US-15 | I want to delete local copies only after the export is verified, so that I never lose a recording. | FR-STO-06, NFR-11 |
| US-16 | I want everything to work without an account or internet, so that I can use the app anywhere. | NFR-01, AT-OFF-01 |
| US-17 | I want to use the app with a screen reader, large text and dark mode, so that it works for me. | NFR-09, build guide 11 |
| US-18 | I want to use the same app on my Surface, so that I can record from a laptop at a workshop. | build guide 10.3 |

---

## 4. Edge cases

Each edge case has an expected behaviour. Where a behaviour depends on what the OS allows, the spike that finds out is named.

### 4.1 Recording

| Case | Expected behaviour | Requirements, spike |
|---|---|---|
| Rapid double tap on Record or Stop | Exactly one recording is started or stopped. | FR-REC-09 |
| Record tapped with microphone permission denied | Plain explanation and a link to settings. No activity left in a recording state. | FR-PRI-04 |
| Permission revoked mid-recording | Segment finalised, interruption `permission_revoked` logged, user told. | NFR-06 |
| Windows privacy setting blocks the mic | Helpful message pointing to Windows privacy settings. `record` cannot check this on Windows, so the app detects the failure itself. | 10.3, P0-06 |
| Call answered, call declined | Segment finalised either way. Call never recorded. Resume or one-tap resume. | FR-REC-05, P0-04 |
| Alarm or another app takes audio focus | Treated as an interruption with reason `alarm` or `other_app`. | FR-REC-05 |
| Camera opens and the OS reconfigures audio | Treated as an interruption with reason `camera`, auto-resumed, marker on timeline. | FR-PHO-07, P0-05 |
| Bluetooth mic disconnects | Fall back to built-in mic with a timeline marker, or pause with a prompt. New segment on route change. Never mislabel codec or channels. | FR-REC-07, AT-QUAL-03, P0-07 |
| Quality changed while recording | New segment with the new profile, or a safe refusal with a reason. | FR-QUAL-04, P0-12 |
| Requested profile not supported (for example 48 kbps on Windows) | Effective settings shown before recording. Requested and effective values both stored. | FR-QUAL-05, ADR-002 |
| 10 minutes pass | Segment rolls. No audible gap beyond what the platform imposes (measured in P0-12). | FR-REC-03 |
| Recording runs past 2 hours | Prompt "Still in 'Keynote'?". Recording continues. | FR-REC-06 |
| Near-silence for 10 minutes | Prompt "No sound detected. Still in the session?". Recording continues. | FR-REC-06 |
| Battery below 15% | Prompt. Recording continues. | FR-REC-06 |
| Storage hits the hard reserve | Segment finalised, stop reason `storage_low`, message shown. Earlier files untouched. | FR-STO-04 |
| App killed by the OS or force-quit | At most the current segment lost. Recovery offered on next launch. | FR-REC-08, AT-REC-03 |
| Device clock or timezone changes mid-conference | All times stored as UTC. Display uses the conference timezone. Offsets come from segment `start_utc`. | 9.4 |
| Recording from a non-visual trigger while another runs | Stop old, start new, confirm by notification. | FR-REC-04 |

### 4.2 Photos and bookmarks

| Case | Expected behaviour | Requirements |
|---|---|---|
| Photo or bookmark with no recording running | Stored with timestamp. `offset_ms` is null. | 9.4 |
| Burst of 20 photos during recording | No audio loss, or each loss is a logged auto-resumed interruption. | AT-PHO-01 |
| Gallery import finds duplicates or very large files | Warn before import. User confirms. | FR-PHO-05 |
| Gallery import with Android partial media access | Only the photos the user granted are listed. Explain how to grant more. | 10.2 |
| Gallery import on Windows | Folder pick filtered by EXIF capture time, file time as fallback. | ADR-002 |

### 4.3 Review, trim and storage

| Case | Expected behaviour | Requirements |
|---|---|---|
| Cut ranges overlap | Merged for playback and export. Each stays separately undoable. | FR-REV-04 |
| Split at a point inside a gap | Split at the gap. Media and bookmarks move by offset. | FR-REV-05 |
| Permanent trim fails half way | Originals untouched. Partial output removed. | FR-REV-06, NFR-07 |
| Delete conference | Confirmation with a summary of what will be deleted. | FR-CONF-08 |
| Delete local copies without a verified export | Not offered. | FR-STO-06 |

### 4.4 Export

| Case | Expected behaviour | Requirements |
|---|---|---|
| Not enough space for the export or its temp files | Declined before any file is written. Sources untouched. | FR-EXP-05, AT-STO-03 |
| Export cancelled or fails | Sources untouched. Partial temp output removed only if it holds no unique media. Nothing is deleted. | FR-EXP-05, AT-STO-04 |
| Titles with emoji, accents, slashes, reserved names (`CON`, `NUL`), trailing dots | ASCII slug, reserved names avoided, folder names up to 60 characters, relative paths under 180. | FR-EXP-07 |
| Two activities with the same title and time | Unique folder names (sequence prefix). | FR-EXP-07 |
| Export larger than 4 GB | ZIP64. Streamed, bounded memory. | FR-EXP-04, ADR-002 |
| Private activities | Excluded by default. One toggle includes them, with a warning. | FR-EXP-10, FR-PRI-05 |
| Re-importing an export | Metadata, counts and checksums match the original. | FR-EXP-11, AT-EXP-02 |

---

## 5. Acceptance criteria detail

The v1.0 acceptance tests are listed in `docs/TEST_PLAN.md` section 4. This section adds testable detail for requirements whose wording leaves room for interpretation.

- **FR-CONF-01 (quick start):** from the welcome screen, a conference can be created with one text field and one button. Widget test counts the required interactions.
- **FR-ACT-05 (default title):** "{Type} {n}, {HH:mm}" where n is the count of that type in the conference including the new one, and HH:mm is local time in the conference timezone. Example: "Session 3, 14:05".
- **FR-QUAL-02 (precedence):** effective profile = `activity.recording_profile_override` if set, else `conference.default_recording_profile`, which was copied from the global default at creation. Changing the global default never changes an existing conference.
- **FR-REC-03 (segments):** a new segment starts on pause, interruption, quality change, route change and at most 10 minutes after the current segment started. Segment `end_reason` records why.
- **Offset rule (9.4):** `offset_ms` = event UTC minus the activity's first segment `start_utc`, counting gaps as real time.
- **FR-STO-02 (thresholds):** defaults are 1 GB or 60 minutes (warning), 300 MB (urgent) and a platform-safe hard reserve to be set after P0-11. All configurable.
- **FR-EXP-07 (paths):** checked by a unit test over a fixture of hostile titles, asserting every relative path is under 180 characters and every folder name is 60 or fewer.
- **Definition of done (build guide 13.4):** a new user can create two conferences, set goals, record several sessions at chosen qualities, add photos and bookmarks, survive interruptions without losing earlier audio, review and trim non-destructively and export everything to a Windows PC, without signing in or paying. Each platform's status is reported per device only after real testing.

---

## 6. Copy

UK English, sentence case, no exclamation marks or emoji, never blame the user. Full rules and reusable lines are in `docs/DESIGN_GUIDE.md` ("Voice and copy") and build guide 11.
