# Conference Companion: Product and Engineering Build Guide

**Version:** 3.0 (consolidated)
**Date:** 26 October 2026
**Supersedes:** "ConfCapture Build Guide" (v1) and "Conference Companion Claude Code Build Guide v2"
**Working tagline:** Be present in the moment. Take the knowledge home.
**Product owner:** Samlytics Data Service (working association, confirm final branding before release)
**Platforms:** Android, iOS, Windows (including Microsoft Surface)
**Licence intent:** free and open source (MIT or Apache 2.0, decided after the dependency licence review in task P0-08)
**Core promise:** a fully useful, offline-first, AI-optional conference memory assistant.

---

## 0. How to read this document

### 0.1 Who this is for

This guide is written for any AI coding agent (Claude Code, OpenAI Codex, Google Antigravity, Cursor or similar) and for human developers. It assumes no memory of earlier conversations. Everything needed to continue the work is in this file, `AGENTS.md` and the files in `docs/`.

### 0.2 Requirement language

- **MUST**: required for the phase it belongs to. A phase is not complete until every MUST in it passes its test.
- **SHOULD**: expected unless there is a documented reason not to (record the reason in `docs/DECISIONS.md`).
- **MAY**: optional, build only if time allows.

### 0.3 Identifier scheme

Every requirement and task has an ID so work can be traced across agents and commits.

| Prefix | Meaning | Example |
|---|---|---|
| `NFR-` | Non-negotiable or non-functional requirement | `NFR-04` single active recording |
| `FR-` | Functional requirement, grouped by feature | `FR-REC-03` rolling segments |
| `AT-` | Acceptance test | `AT-STO-02` low storage finalisation |
| `P0-` to `P3-` | Backlog task in a phase | `P1-12` export manifest writer |
| `ADR-` | Architecture decision record in `docs/DECISIONS.md` | `ADR-003` trimming approach |

Reference IDs in commit messages, test names and progress notes, for example `feat(recording): rolling segment writer [FR-REC-03, P1-07]`.

### 0.4 Change history

| Version | Summary |
|---|---|
| v1 | Flutter stack, one-active rule, rolling segments, bookmarks with recording offsets, gallery import by time window, Siri App Intents and Live Activity, Android tile and notification actions, Windows hotkeys and tray, split item, "Copy AI prompt", export variants for AI upload limits, whisper.cpp |
| v2 | Feasibility-first Phase 0, honesty rules, recording state machine, storage and low-RAM release blockers, per-session quality profiles with requested vs observed bitrate, privacy and consent UX, checksums, timeline CSV, evidence-grounded analysis prompt, Google Drive and OneDrive export (Phase 1.5), Windows in v1.0 |
| v3 | Merges v1 and v2, resolves conflicts (section 18), adds agent handover protocol, full data schema, permissions matrix, Windows path-length rules, task backlog with IDs, extra prompt templates and copy guidelines |

---

## 1. Agent operating rules (any tool)

### 1.1 Role

Act as a senior mobile engineer, desktop engineer, product designer, QA lead and privacy-aware architect. Build a working, testable application, not UI mock-ups or a marketing site.

### 1.2 Start of every session

1. Read `AGENTS.md`, then this file, then `docs/PROGRESS.md` and `docs/HANDOVER.md`.
2. Run the test suite and static analysis to confirm the repo is healthy before changing anything. Record the result in `docs/PROGRESS.md`.
3. Pick the next task from section 17 that is not marked done and whose dependencies are done. If `docs/HANDOVER.md` names a task in progress, finish that first.
4. Write a short plan for the task before coding.

### 1.3 While working

- Inspect existing code before writing new code. Extend a component if it already meets roughly 70 to 80% of the need. Do not replace working code without an ADR.
- Small, focused commits. One task per branch where practical (`phase-1/P1-07-rolling-segments`).
- Every new behaviour gets a test. Tests are named with the requirement ID they prove.
- Use the latest stable, mutually compatible dependencies. Record exact tested versions in `docs/ARCHITECTURE.md`. Before adopting any package, confirm it is maintained, supports the platforms needed and has a licence compatible with the project licence.
- Use official, current platform documentation for device features. Paste the source link into `docs/PLATFORM_FEASIBILITY.md`.

### 1.4 Honesty rules (strict)

- Never claim a feature works without a passing test or a recorded real-device check.
- Mark any platform not tested on a real device as **unverified**.
- If the OS blocks a feature, build the closest policy-compliant alternative and document the limitation in plain words.
- Never invent benchmark figures. Record measured values with device, OS version and date.
- No paid services or API keys in the free edition.

### 1.5 End of every session (handover protocol)

Before stopping, or when the context or token budget is running low, the agent MUST:

1. Commit all working code. Never leave uncommitted work. If a change is half done, commit it on the task branch with `WIP` in the message and make sure the default branch still builds.
2. Update `docs/PROGRESS.md`: tasks completed, tests added, test status, measured results.
3. Overwrite `docs/HANDOVER.md` with: current task ID, what is done, what is left, exact next step, files touched, known failing tests, open questions, commands to run.
4. Add any decision made to `docs/DECISIONS.md` as an ADR.

The next agent, of any brand, must be able to continue from `HANDOVER.md` alone.

### 1.6 Documents to create and keep updated

| File | Content |
|---|---|
| `AGENTS.md` | Short operating rules and read order (already provided) |
| `docs/BUILD_GUIDE.md` | This file. Change only with an ADR and a change-history entry |
| `docs/PRODUCT_SPEC.md` | User journeys, stories, edge cases, acceptance criteria detail |
| `docs/ARCHITECTURE.md` | Modules, audio lifecycle, storage, export design, dependency versions |
| `docs/PLATFORM_FEASIBILITY.md` | Verified OS capabilities, source links, limits, spike results matrix |
| `docs/PRIVACY_AND_SAFETY.md` | Consent, retention, local storage and sharing decisions |
| `docs/TEST_PLAN.md` | Automated and manual tests, device matrix, results |
| `docs/RELEASE_PLAN.md` | Milestones, versioning, distribution, signing |
| `docs/DECISIONS.md` | ADR log (context, decision, alternatives, consequences) |
| `docs/PROGRESS.md` | Running log of work done, dated |
| `docs/HANDOVER.md` | Current state for the next agent |
| `README.md` | Install, develop, export formats, caveats, Windows downloads |

### 1.7 When blocked

If a task cannot be completed (OS limit, missing signing credentials, hardware not available), mark it **blocked** in `PROGRESS.md` with the reason, write what was tried, and move to the next unblocked task. Do not fake a pass.

---

## 2. Product vision

### 2.1 Problem

At conferences people spend sessions typing notes so they have enough material for takeaways. They miss the moment, photos end up scattered in the camera roll, and short conversations with speakers are lost.

### 2.2 Solution

Before the event the user sets their role and learning goals. During each activity they record audio (where permitted), take photos and tap bookmarks. Then they put the phone away and listen. Afterwards they review, trim unwanted parts without destroying originals, and export a self-explaining package for manual use or for upload to the AI tool of their choice.

### 2.3 Audience

Conference attendees, researchers, architects, consultants, students, executives, exhibitors and anyone who attends several events a year.

### 2.4 Not this product

Not a covert recording tool, not a journalist's camera system, not a meeting bot, not a mandatory cloud transcription service.

### 2.5 Core user story

"I am a senior data architect at a health-security conference. My goals are to understand how data architecture supports programme replication, interoperability and responsible AI. I start a session, put my phone away and listen. When a useful slide appears, I take a photo and it attaches to the session at that point in the audio. I capture a short conversation with a speaker, with their permission. After the event I trim off the walk between rooms and export the whole event with my goals and timeline, ready for my own review or for an AI tool."

---

## 3. Non-negotiable requirements

| ID | Requirement |
|---|---|
| NFR-01 | **Free offline-first core.** No login, internet, cloud account, API key, subscription or AI model needed to create, record, organise, review, trim and export a conference. |
| NFR-02 | **Multiple conferences**, each with its own goals, activities and exports. Archived conferences stay accessible. |
| NFR-03 | **Multiple activity types**: session, keynote, panel, breakout, workshop, exhibit, business conversation, networking, personal reflection, plus user-defined types. |
| NFR-04 | **Single active recording.** Starting another activity while recording asks whether to keep, stop or switch. Never two unintended simultaneous recordings. |
| NFR-05 | **Reliable recording.** Audio continues with screen locked or app in background where the OS allows. A clear recording indicator is always visible. |
| NFR-06 | **Safe interruption handling** for calls, alarms, permission loss, Bluetooth route changes, OS termination, low storage and app lifecycle changes. Never silently discard written audio. |
| NFR-07 | **Non-destructive editing.** Originals are kept until the user explicitly deletes them. Trims are metadata with undo. |
| NFR-08 | **Portable export** as a structured folder or ZIP, with human-readable summary, machine-readable manifest and an analysis prompt. |
| NFR-09 | **Privacy and accessibility.** Clear consent guidance, user-controlled deletion, no tracking by default, screen reader support, large touch targets, high contrast. |
| NFR-10 | **Low resource use (release blocker).** Compressed audio, bounded memory, streaming I/O, works on modest phones. |
| NFR-11 | **Storage safety (release blocker).** Live storage estimates, staged warnings, safe stop before the disk fills, no automatic deletion of originals. |
| NFR-12 | **Session-level recording quality.** Conference default with per-activity override. Each segment records the quality actually used. |
| NFR-13 | **Optional cloud export** to Google Drive and OneDrive with explicit consent. The app stays fully usable with no account and no internet. Upload never triggers automatic local deletion. |
| NFR-14 | **Pocket mode.** After starting, the user should not need to look at the screen. Stop, bookmark and new-activity actions are reachable from notification, lock screen or OS assistant where the platform allows. |

---

## 4. Domain glossary

| Term | Meaning |
|---|---|
| Conference | An event the user attends, with role, goals and requested outputs |
| Activity | Anything captured within a conference: session, keynote, exhibit, conversation, reflection, etc. (v1 called this "capture item") |
| Recording | One continuous capture effort within an activity, made of one or more segments |
| Segment | One audio file. New segments start on pause, interruption, quality change, route change and every 10 minutes |
| Gap | Time between segments when nothing was recorded (pause, call, failure) |
| Offset | Seconds from the activity's first segment start, used to line up photos and bookmarks with audio |
| Recording profile | Economy, Balanced or Enhanced audio settings |
| Cut range | A non-destructive excluded time range on an activity's timeline |
| Export job | One local or cloud export run |
| Pocket mode | Controlling capture without looking at the app screen |

---

## 5. Feature specification for v1.0 (free core, no AI)

### 5.1 Conference set-up wizard

| ID | Requirement |
|---|---|
| FR-CONF-01 | MUST offer **quick start**: create a named conference in under 30 seconds, fill in the rest later. |
| FR-CONF-02 | MUST collect, with only the name required: name, start and end dates, location (manual), timezone (default device timezone), optional description. |
| FR-CONF-03 | MUST collect participant role: attendee, speaker, exhibitor, student, journalist or custom, plus free-text profession or organisational role (for example "Senior enterprise data architect"). |
| FR-CONF-04 | MUST collect goals: up to three priority goals shown by default, unlimited optional. Show examples such as "Where could enterprise data architecture improve reproducibility?" and "How is AI applied in public health response?" |
| FR-CONF-05 | MUST collect expected outputs (multi-select): personal notes, briefing, presentation, LinkedIn post, blog, research summary, follow-up list. |
| FR-CONF-06 | MUST show the recording policy notice and require acknowledgement: "Some events and speakers do not allow recording. Record only when permitted." |
| FR-CONF-07 | MUST set the conference default recording profile (Economy, Balanced or Enhanced), inheriting the global default (Balanced). |
| FR-CONF-08 | MUST allow editing all fields at any time, archiving and deleting (with confirmation and a summary of what will be deleted). |

### 5.2 Conference home and activities

| ID | Requirement |
|---|---|
| FR-ACT-01 | Conference home MUST show name, dates, activity count, total recorded time, local storage used and a single dominant "Start activity" action. |
| FR-ACT-02 | MUST offer quick-start buttons for the most used types: Session, Conversation, Exhibit, Reflection. |
| FR-ACT-03 | MUST list activities chronologically with type icon, title, start time, recording state, effective recording profile, photo count and bookmark count. |
| FR-ACT-04 | Activity fields: `title`, `type`, `speaker_names`, `organisation`, `room`, `notes`, `tags`, `planned_start`, `actual_start`, `actual_end`, `recording_permission_status`, `recording_profile_override`. |
| FR-ACT-05 | A blank title defaults to "{Type} {n}, {HH:mm}" (for example "Session 3, 14:05"). Rename any time. |
| FR-ACT-06 | Users MUST be able to create custom activity types. |
| FR-ACT-07 | For business conversations and networking, MUST show a consent check: "Does the other person know you are recording?" with Yes / Not recording audio options. |
| FR-ACT-08 | MUST allow optional manual contact details and a follow-up action for conversations. No facial recognition or automatic identity extraction. |
| FR-ACT-09 | SHOULD allow merging two activities and moving media between activities. |

### 5.3 Recording screen

| ID | Requirement |
|---|---|
| FR-UI-01 | Large Record, Pause and Stop controls. Elapsed time. Clear microphone indicator. |
| FR-UI-02 | Shows current conference and activity title. |
| FR-UI-03 | One-tap **Photo** button. The shutter stays ready for the next shot. |
| FR-UI-04 | One-tap **Bookmark** with optional label chips: Important moment, Question, Follow-up, Key slide, Quote. No typing needed. |
| FR-UI-05 | **Quick thought**: short text, or a separately marked voice memo only when the user explicitly starts one. Private reflections are never mixed into speaker audio. |
| FR-UI-06 | Input source indicator, live level meter and a 10-second microphone test. |
| FR-UI-07 | **Live storage budget**: free space, space used by this conference, estimated recording time left at the current profile, staged warnings. Works offline. |
| FR-UI-08 | **Quality selector** (Economy / Balanced / Enhanced) before recording, labelled with MB per hour and estimated safe time left. Kept separate from the Record button. While recording, shows the effective profile. Changes follow section 5.5. |

### 5.4 Recording engine

| ID | Requirement |
|---|---|
| FR-REC-01 | Start recording in one tap. Store metadata immediately in a transactional database before audio is written. |
| FR-REC-02 | Record directly to disk with small bounded buffers. Never hold session-length audio in memory. |
| FR-REC-03 | **Rolling segments.** Start a new segment on pause, interruption, quality change, input route change and at least every 10 minutes. A crash loses at most the current segment. Segments of one activity form one timeline with explicit gaps. |
| FR-REC-04 | **One active recording rule.** If a recording is running and the user starts another (from UI, notification, shortcut or voice), show: "'Data Mesh Keynote' is still recording (47 min). Stop it and start new / Keep it running / Cancel". From a non-visual trigger (shortcut, voice), the default is stop old and start new, then confirm by notification. |
| FR-REC-05 | **Calls and audio interruptions.** On interruption, finalise the current segment, log the interruption (reason, start, end) and never record the call. When it ends, resume through OS-supported mechanisms and notify "Recording resumed". If resume is not allowed, keep the partial recording and show a visible one-tap resume (notification where permitted, banner on return). |
| FR-REC-06 | **Safety prompts** (configurable): recording longer than 2 hours ("Still in 'Keynote'?"), near-silence for 10 minutes ("No sound detected. Still in the session?"), storage thresholds (section 5.9), battery below 15%. Prompts never stop recording on their own except the storage hard limit. |
| FR-REC-07 | **Input selection**: built-in, wired or Bluetooth mic. Show the input actually in use. Warn that Bluetooth headset mics are often call-quality. On route loss, fall back to an available mic with a timeline marker, or pause with a prompt if fallback is not possible. |
| FR-REC-08 | **Crash recovery.** On app start, reconcile the database with segment files. Offer recovery for orphaned or unfinalised segments. Never mark a damaged file as good. |
| FR-REC-09 | Start/stop operations are idempotent and mutex-protected. Rapid taps never create duplicate recordings. |
| FR-REC-10 | Android: persistent notification with Pause/Resume, Stop, Bookmark and (where allowed) Photo actions. |

**Recording state machine (per activity):**

```text
IDLE -> STARTING -> RECORDING
RECORDING -> PAUSED -> RECORDING
RECORDING -> SWITCHING_SEGMENT -> RECORDING        (10-min roll, quality or route change)
RECORDING -> INTERRUPTED -> RECOVERING -> RECORDING (only if OS permits)
INTERRUPTED -> USER_RESUME_REQUIRED -> RECORDING    (fallback)
RECORDING | PAUSED | INTERRUPTED -> STOPPING -> SAVED
RECORDING -> STORAGE_STOP -> SAVED                  (hard storage limit)
ANY -> ERROR_RECOVERABLE                            (partial files preserved)
```

### 5.5 Recording quality profiles (contract)

| Preset | Target (starting point) | Approx. MB per hour | Suggested use |
|---|---:|---:|---|
| Economy | 32 kbps AAC-LC mono | 14.4 | Reflections, quiet conversations |
| Balanced (default) | 48 kbps AAC-LC mono | 21.6 | Typical talks and breakouts |
| Enhanced | 64 kbps AAC-LC mono | 28.8 | Keynotes, noisy halls, far from speaker |

| ID | Requirement |
|---|---|
| FR-QUAL-01 | Targets are not guaranteed output. Query encoder support at runtime and verify actual bitrate and intelligibility on each OS and Bluetooth route. |
| FR-QUAL-02 | Precedence: global default (Balanced) → copied into `conference.default_recording_profile` at creation → each new activity inherits unless `activity.recording_profile_override` is set. |
| FR-QUAL-03 | Changing a conference default affects new activities only. Bulk changes to unrecorded activities need explicit confirmation. |
| FR-QUAL-04 | Changing quality mid-recording finalises the current segment and starts a new one with the new profile. Never change a running encoder or transcode an existing file. If the platform cannot switch cleanly, decline and say why. |
| FR-QUAL-05 | If a profile is unavailable on the device or route, show the effective settings before recording and record the difference in metadata. Never call a fallback equivalent without verification. |
| FR-QUAL-06 | Each segment stores requested profile, codec, container, channels, sample rate, requested and observed bitrate, input route and byte size. |
| FR-QUAL-07 | Uncompressed WAV is off by default and only offered as a specialist option. Never downsample or convert originals afterwards. |
| FR-QUAL-08 | Photos have their own quality settings, independent of audio profiles. |

### 5.6 Photos

| ID | Requirement |
|---|---|
| FR-PHO-01 | In-app camera saves to the active activity with timestamp and recording offset. |
| FR-PHO-02 | Space-saving default: long edge about 1600 to 2048 px, widely supported compressed format, quality tuned by legibility tests on slides, posters and whiteboards. "Keep highest quality" opt-in. |
| FR-PHO-03 | Generate small thumbnails once. Lazy-load them. Decode full images at display size only. |
| FR-PHO-04 | Do not save duplicate copies to both the camera roll and the app library. |
| FR-PHO-05 | **Gallery import by time window**: "Import photos taken during this activity" lists camera-roll photos between the activity's start and end (with a configurable margin, default 2 minutes). User confirms before import. Warn on large or duplicate files. |
| FR-PHO-06 | Manual gallery import with labels. Optional caption per photo. |
| FR-PHO-07 | Taking a photo during recording MUST NOT lose audio. If the platform's camera interrupts the audio session, treat it as an interruption (segment boundary, marker, auto-resume) and test this explicitly (P0-05). |

### 5.7 Bookmarks and notes

| ID | Requirement |
|---|---|
| FR-BMK-01 | Bookmarks store timestamp, offset and label. They appear on the review timeline and in exports. |
| FR-BMK-02 | Short text notes per activity in plain Markdown. |
| FR-BMK-03 | Bookmark is reachable from notification (Android), lock screen control (iOS, Phase 2) and hotkey (Windows). |

### 5.8 Review and trim

| ID | Requirement |
|---|---|
| FR-REV-01 | Player: play/pause, scrub, skip back and forward 15 seconds, speed control. |
| FR-REV-02 | Timeline shows segments, gaps, interruption markers, photos and bookmarks at their offsets. |
| FR-REV-03 | Waveform from decimated summaries, rendered page by page. Never decode a full session into memory. |
| FR-REV-04 | Trim start and end. Exclude middle ranges (multiple ranges SHOULD be in v1.0, MUST by v1.1). Trims are stored in `cut_ranges` with undo. |
| FR-REV-05 | **Split activity at playhead** into two activities, for when one recording covered two sessions. Media and bookmarks move by offset. |
| FR-REV-06 | "Apply trims permanently" is a separate, confirmed action that writes new files and only then offers to remove originals. |
| FR-REV-07 | Trimming implementation is decided in ADR-003: native passthrough cutting per platform (AVAssetExportSession on iOS, MediaExtractor and MediaMuxer on Android, Media Foundation on Windows) or a maintained media library. The original `ffmpeg_kit_flutter` was retired in 2025, so any FFmpeg route needs a maintained fork plus a licence and redistribution review. Export of cut ranges as instructions (`cuts.json`) is always available as a fallback. |

### 5.9 Storage manager and protection

| ID | Requirement |
|---|---|
| FR-STO-01 | Track free space and a rolling "minutes left" estimate from measured file growth, not only nominal bitrate. |
| FR-STO-02 | Default thresholds (adjust after device testing): warning below 1 GB free or under 60 minutes left. Urgent warning near 300 MB. Hard stop at a platform-safe reserve. |
| FR-STO-03 | Recheck before recording, every 30 seconds while recording, after each photo, before transcription, trim and export, and on OS low-space signals. |
| FR-STO-04 | At the hard limit: finalise the current segment, keep all earlier files, record stop reason `storage_low`, tell the user clearly. Never run the disk to zero or show "recording" when it is not. |
| FR-STO-05 | Storage Manager screen: size per conference and activity split into audio, photos, thumbnails, transcripts, temporary exports and models. Shows export status (not exported, exported locally, uploaded, verified). |
| FR-STO-06 | Actions: Export and archive, Delete local copies (only after verified export and separate confirmation, with a preview), Clear safe temporary files, Manage offline models. |
| FR-STO-07 | Optional lightweight archived index (metadata and thumbnails only) kept only if the user chooses it. "Delete" means delete. |

### 5.10 Local export

| ID | Requirement |
|---|---|
| FR-EXP-01 | Scopes: whole conference, selected activities, one day, audio only, photos only, text and metadata only. |
| FR-EXP-02 | Formats: structured folder (preferred when the destination allows) or ZIP. |
| FR-EXP-03 | Audio options: original files, or trimmed copies, or originals plus `cuts.json`. Optional "compressed for AI upload" copy at Economy if the original is larger. |
| FR-EXP-04 | Stream archive members to the output. Never load whole recordings or photo sets into RAM. |
| FR-EXP-05 | Preflight: estimate size and any temporary space, decline safely if not enough. Failure never deletes or corrupts sources. Clean up partial temp files only if they contain no unique source media. |
| FR-EXP-06 | Write `checksums.sha256` for every exported file. |
| FR-EXP-07 | Filenames and paths are safe on Windows, macOS and Linux: ASCII slug, no reserved characters or names (`CON`, `NUL`, etc.), no trailing dots or spaces, folder names capped at 60 characters, total relative path under 180 characters to stay well within Windows' 260-character limit after unzipping. |
| FR-EXP-08 | "Copy AI prompt" button copies `analysis_prompt.md` with role, goals and outputs filled in. |
| FR-EXP-09 | The README in the export explains that ZIP rarely shrinks compressed audio and photos, how to unzip, and that AI tools differ in which file types and sizes they accept and change these limits often. |
| FR-EXP-10 | Users can exclude private conversations or reflections from an export with one toggle. |
| FR-EXP-11 | SHOULD support re-import of an exported folder or ZIP (round trip), required for P0-09. |

**Export structure:**

```text
2026-11-04_samlytics-conference-2026/
  README_START_HERE.md
  conference.json
  participant_goals.md
  timeline.csv
  analysis_prompt.md
  prompts/
    presentation_outline.md
    linkedin_post.md
    blog_draft.md
    briefing_note.md
  activities/
    001_0930_keynote_data-mesh-in-practice/
      activity.json
      activity.md
      notes.md
      bookmarks.csv
      cuts.json
      audio/
        segment-001.m4a
        segment-002-after-call.m4a
      photos/
        2026-11-04T09-44-21Z_slide-01.jpg
      transcript.md            (only if Phase 2 transcription was run)
    002_1100_exhibit_acme-catalogue/
      ...
  checksums.sha256
```

**File contents:**

- `README_START_HERE.md`: what this package is, folder guide, how to use it with or without AI, consent and confidentiality warning.
- `conference.json`: `schema_version`, conference ID, title, dates, timezone, role, goals, requested outputs, activity IDs, privacy flags, app version, export timestamp.
- `participant_goals.md`: role and goals in plain English.
- `timeline.csv`: one row per segment, photo and bookmark: `activity_id, activity_title, kind, file, utc_time, local_time, offset_seconds, label, profile, observed_bitrate_bps`.
- `activity.json`: type, title, speakers, organisation, room, local and UTC times, segments (all quality fields), gaps and interruptions, photos with offsets and captions, bookmarks, cut ranges, consent status.
- `activity.md`: the same in readable form, bookmarks and photos listed against `mm:ss` offsets.
- `analysis_prompt.md` and `prompts/`: see section 15.

### 5.11 Settings

Default recording profile, space-saving mode (on), photo quality, safety prompt thresholds, default activity type, storage manager link, cloud connections (Phase 1.5), Wi-Fi-only uploads (Phase 1.5), offline models (Phase 2), app lock (optional), theme, text size, language (UK English first), about and licences.

### 5.12 Privacy and consent UX

| ID | Requirement |
|---|---|
| FR-PRI-01 | Before first recording in a conference, show the policy reminder. For conversations, require the awareness check (FR-ACT-07). |
| FR-PRI-02 | Always-visible recording banner and a quick stop. No stealth or hidden modes. |
| FR-PRI-03 | All data stays on device unless the user exports or uploads. No analytics, ads or trackers by default. |
| FR-PRI-04 | Permissions requested only when first needed, with a plain explanation. |
| FR-PRI-05 | Warn before exporting or uploading sensitive material: identifiable people, unpublished research, commercial, medical or financial content. The app does not replace the user's own legal obligations (for example UK GDPR) and must not claim to. |
| FR-PRI-06 | Optional app lock using device biometrics or PIN. |

---

## 6. Pocket mode and hands-free control (Phase 2, spiked in Phase 0)

The user chose OS assistant shortcuts as the voice route. iOS does not let third-party apps listen for a wake word in the background, so wake-word listening is out of scope.

| ID | Platform | Requirement |
|---|---|---|
| FR-HF-01 | iOS | App Intents exposed to Siri and Shortcuts: Start activity, Stop recording, New conversation, Bookmark, Take photo (opens camera). Example phrase: "Hey Siri, start session in Conference Companion". |
| FR-HF-02 | iOS | Live Activity on lock screen and Dynamic Island: title, elapsed time, Stop and Bookmark buttons. |
| FR-HF-03 | iOS | Control Centre and lock-screen controls for Start/Stop where supported. |
| FR-HF-04 | Android | App shortcuts (long-press icon), Quick Settings tile, notification actions. |
| FR-HF-05 | Android | Assistant or Gemini integration only if current documentation supports it. Fallback: deep links (`conferencecompanion://record/start`) a user can attach to an assistant routine. |
| FR-HF-06 | Windows | Global hotkeys (default Ctrl+Alt+R start/stop, Ctrl+Alt+B bookmark, configurable), tray icon showing state, taskbar indicator. |
| FR-HF-07 | All | Optional in-app push-to-talk commands while the app is open ("new session", "record", "stop", "bookmark") using on-device recognition only. Command recognition is separate from transcription. |
| FR-HF-08 | All | Experimental: headset button press to bookmark. Ship only if reliable on tested devices. |

Every non-visual trigger respects the one-active rule (FR-REC-04) and confirms its action by notification or haptic. Cold-starting a fresh microphone recording from the background is subject to OS rules (section 10). Where blocked, the shortcut opens the app to the recording screen instead and says why in the docs.

---

## 7. Optional Google Drive and OneDrive export (Phase 1.5)

Cloud is opt-in, never gates v1.0, and never interferes with capture reliability.

### 7.1 User journey

1. Export or Storage Manager → Back up to cloud.
2. Choose Device / external drive, Google Drive or OneDrive.
3. First use: show provider, permissions requested, privacy note and Connect account. Sign in through the provider's own flow. Multiple providers allowed, active account shown clearly.
4. Destination: user-chosen folder if supported, otherwise `Conference Companion/<Conference Name>/`. Use stored remote folder IDs to avoid duplicates.
5. Scope: whole conference, selected activities, photos only, audio only, metadata only. Format: **structured folder (recommended, no extra ZIP on the phone)** or ZIP. Show upload size and any local temp space needed.
6. Options: Wi-Fi only (on by default), upload now or queue for Wi-Fi, pause, resume, cancel, completed activities only (on by default), charging only (optional).
7. Progress panel: bytes, files done, remaining, failures, quota errors, retry.
8. Completion: show provider, masked account, folder link and status. Distinguish **uploaded (receipt and size confirmed)** from **integrity verified (checksum confirmed)**. Offer "View in Drive/OneDrive".
9. Only after verified backup, offer Free local space as a separate confirmed step with preview.
10. Disconnect provider: wipe local tokens, revoke where possible, never delete remote files without a separate instruction.

### 7.2 Auth and permissions

- OAuth 2.0 authorisation code with PKCE using provider-supported libraries and the system browser or secure native flow. No embedded password forms, no client secrets treated as secret on devices, no service accounts. Validate state, redirect and PKCE verifier. Register Android, iOS and Windows clients separately.
- **Google Drive:** scope `https://www.googleapis.com/auth/drive.file` (files the app creates or the user selects). Do not use `appDataFolder` for visible backups. Do not widen scopes. Google consent screen configuration and possible verification are needed before public release.
- **OneDrive:** Microsoft Graph delegated `Files.ReadWrite`, not `Files.ReadWrite.All`. Check personal and work/school account support, tenant admin consent and app registration. Work accounts may be blocked by their organisation.
- Tokens only in iOS Keychain, Android Keystore-backed storage or Windows credential protection. Never in SQLite, logs, manifests or the repo.
- No automatic background upload of new recordings. Default private access. Never create public share links automatically.
- Free app does not mean free storage: provider quotas, data charges and API limits apply. Say so.

### 7.3 Upload architecture

```text
Finalised local originals (immutable)
  -> CloudExportPlanner (folder plan, manifest, prompts)
  -> UploadQueue (durable, per-file state)
  -> GoogleDriveAdapter (resumable upload) | OneDriveAdapter (Graph createUploadSession)
  -> Remote verification -> optional user-approved local cleanup
```

- Provider-neutral `CloudExportService` with adapters. Local export remains independent.
- Stream each finalised file in bounded chunks. Never upload a file still being written.
- Durable record per file: local ID, SHA-256, size, provider, remote folder and file IDs, bytes acknowledged, upload session reference (protected), retries, backoff, state, last error.
- Conservative concurrency: one large media file at a time on phones. Back off on 429 and 5xx. Idempotent operations. Handle revoked auth, full quota, offline, metered networks, name conflicts and stale paths.
- Throttle or pause uploads before they affect an active recording.
- iOS: file-backed background `URLSession` where suitable, no promise after force quit. Android: user-initiated data transfer jobs or WorkManager per current guidance. Windows: in-app queue while running.

---

## 8. Offline transcription and AI (Phases 2 and 3)

### 8.1 Phase 2: offline transcription (free, no account)

- whisper.cpp (MIT) with Whisper models, or Vosk, or the platform's on-device speech APIs. Confirm model licences and device performance first.
- Models are separate downloads, never bundled. Each shows size, memory requirement, device support label and a delete button.
- Transcription runs after recording, with progress and cancel. Do not run large models during an active recording on low-resource devices unless measured safe.
- Output `transcript.md` with timestamps aligned to activity offsets, honouring cut ranges.

### 8.2 Phase 3: opt-in AI

- Bring-your-own key or provider account authorisation, stored in secure storage. Explicit consent before any upload, per job.
- Features: evidence-grounded per-activity key points against goals, overall takeaways, action lists, topic extraction, editable presentation outline, LinkedIn and blog drafts.
- Always grounded: separate what a speaker said, user observations, inferences and recommendations. Link to file and timestamp. No invented quotes.
- No automatic publishing anywhere.
- AI features can be fully switched off and the app behaves exactly as v1.0.

---

## 9. Architecture

### 9.1 Stack

| Area | Choice (verify versions in P0-01) | Notes |
|---|---|---|
| Framework | Flutter stable, Dart | Officially supports iOS, Android and Windows |
| State | Riverpod | |
| Local database | Drift (SQLite) | Transactional, migrations, works on Windows |
| Recording | `record` package, or native code where it falls short | Validate pause/resume, AAC on Windows, background behaviour, codec reporting |
| Audio session | `audio_session` | Interruptions and routing on iOS and Android |
| Playback | `just_audio` | |
| Camera | `camera` with `camera_windows` | Test audio session conflict (P0-05) |
| Gallery | `photo_manager` | Time-window queries, Android partial media access |
| Background (Android) | Foreground service, type `microphone` | |
| Background (iOS) | `UIBackgroundModes: audio` | |
| Archive | Streaming ZIP writer (for example `archive` with file streams) | Verify bounded memory |
| Hashing | `crypto` (SHA-256) in an isolate, streamed | |
| Sharing | `share_plus`, platform file pickers | |
| Secure storage | `flutter_secure_storage` | Phase 1.5 onwards |
| OAuth | Provider SDKs or `flutter_appauth` with PKCE | Phase 1.5 |
| Native bridges | Platform channels, kept thin | App Intents, Live Activity, tiles, trimming |

### 9.2 Module layout

```text
lib/
  app/                      routing, theme, localisation
  features/
    onboarding/
    conferences/
    activities/
    capture/                recording screen, camera, bookmarks
    playback_review/        player, timeline, trim, split
    storage_manager/
    export/
    cloud_export/           Phase 1.5
    transcription/          Phase 2
    settings/
  domain/
    models/
    services/
  data/
    local_database/         drift tables, migrations, DAOs
    repositories/
    filesystem/             paths, naming, atomic writes
  platform/
    audio_capture/
    permissions/
    media_devices/
    interruptions/
    shortcuts/              Phase 2
  shared/
    widgets/
    utilities/
    resource_budget/
    oauth_integrations/     Phase 1.5
ios/                        App Intents, Live Activity extension
android/                    foreground service, tile, shortcuts
windows/                    hotkeys, tray
docs/
test/
integration_test/
tool/                       scripts (fixtures, size reports)
```

### 9.3 Services

| Service | Responsibility |
|---|---|
| `ConferenceRepository` | Conference CRUD, archive, delete, import |
| `ActivityRepository` | Activity CRUD, types, ordering, split and merge |
| `RecordingService` | Start, pause, resume, stop, segment rolling, state stream |
| `InterruptionCoordinator` | Calls, alarms, route changes, camera conflicts, recovery |
| `RecordingProfileService` | Defaults, overrides, encoder capability mapping, measured estimates |
| `MediaAssetRepository` | Photos, segments, thumbnails, checksums, offsets |
| `GalleryImportService` | Time-window photo discovery and import |
| `RecordingReviewService` | Player, timeline model, bookmarks, cut ranges, undo |
| `TrimService` | Permanent trim per ADR-003 |
| `StorageBudgetService` | Free space probe, minutes left, thresholds, preflight |
| `ResourceBudgetService` | Buffer limits, image cache caps, temp file tracking, profiling hooks |
| `ConferenceExportService` | Streaming deterministic export, manifest, prompts, checksums |
| `ArchiveLifecycleService` | Export verification, cleanup, archived index |
| `CapabilitiesService` | Per-platform feature availability and user notices |
| `CloudConnectionRepository` | Provider accounts, scopes, token references (Phase 1.5) |
| `CloudExportService` + adapters | Planning, chunked upload, verification (Phase 1.5) |
| `UploadQueueRepository` | Durable queue, retries, expiry, de-duplication (Phase 1.5) |
| `ShortcutBridge` | App Intents, tiles, deep links, hotkeys (Phase 2) |
| `TranscriptionService` | Model management, jobs, transcripts (Phase 2) |

### 9.4 Data model (Drift tables)

All IDs are UUID v4 strings. All times stored as UTC ISO 8601 plus the conference timezone for display. Every table has `created_at` and `updated_at`. Use schema migrations for every change, with tests.

**conferences**: `id`, `name`, `description`, `venue`, `start_date`, `end_date`, `timezone`, `role_type`, `role_text`, `requested_outputs` (JSON list), `default_recording_profile`, `policy_acknowledged_at`, `archived_at`

**goals**: `id`, `conference_id`, `text`, `priority` (1 to 3 for priority goals, null for extras), `sort_order`

**activity_types**: `id`, `key`, `label`, `icon`, `is_builtin`, `sort_order`

**activities**: `id`, `conference_id`, `type_id`, `title`, `speaker_names` (JSON), `organisation`, `room`, `notes_md`, `tags` (JSON), `planned_start`, `actual_start`, `actual_end`, `status` (draft, active, completed), `recording_permission_status` (unknown, permitted, not_permitted, participant_aware), `recording_profile_override` (nullable), `is_private` (excluded from export by default when true), `contact_name`, `contact_details`, `follow_up_text`

**recording_segments**: `id`, `activity_id`, `sequence`, `file_path` (relative to app media root), `state` (writing, finalised, damaged, recovered), `requested_profile`, `codec`, `container`, `channel_count`, `sample_rate_hz`, `requested_bitrate_bps`, `observed_bitrate_bps`, `input_route`, `start_utc`, `end_utc`, `duration_ms`, `bytes`, `sha256`, `end_reason` (user_stop, pause, roll, interruption, quality_change, route_change, storage_low, error)

**interruptions**: `id`, `activity_id`, `reason` (call, alarm, other_app, camera, route_lost, permission_revoked, system), `start_utc`, `end_utc`, `auto_resumed` (bool)

**photos**: `id`, `activity_id`, `file_path`, `thumbnail_path`, `taken_utc`, `offset_ms` (nullable if no recording), `caption`, `label`, `source` (in_app, gallery_import, manual_import), `width`, `height`, `bytes`, `sha256`, `original_kept` (bool)

**bookmarks**: `id`, `activity_id`, `at_utc`, `offset_ms`, `label`, `note`, `source` (ui, notification, shortcut, hotkey, voice)

**cut_ranges**: `id`, `activity_id`, `start_offset_ms`, `end_offset_ms`, `reason`, `deleted_at` (soft delete for undo)

**export_jobs**: `id`, `conference_id`, `scope` (JSON), `destination` (local, google_drive, onedrive), `format` (folder, zip), `audio_mode`, `state`, `bytes_total`, `bytes_done`, `started_at`, `completed_at`, `verification_level` (none, receipt, size, checksum), `last_error`

**cloud_connections** (Phase 1.5): `id`, `provider`, `account_masked_id`, `granted_scopes`, `connected_at`, `token_secure_ref`, `last_auth_state`

**cloud_export_files** (Phase 1.5): `id`, `job_id`, `local_asset_id`, `local_size`, `local_sha256`, `remote_file_id`, `remote_size`, `upload_session_ref`, `bytes_acknowledged`, `retry_count`, `next_retry_at`, `remote_verification_level`

**transcripts** (Phase 2): `id`, `activity_id`, `model_id`, `language`, `file_path`, `state`, `created_at`

**app_settings**: key-value table.

**Offset rule:** `offset_ms` is measured from the `start_utc` of the activity's first segment, counting gaps as real time, so photos and bookmarks line up with wall-clock time even across interruptions. The review timeline shows gaps visibly.

### 9.5 On-device file layout

```text
<app documents>/media/
  conferences/<conference_id>/
    activities/<activity_id>/
      audio/segment-001.m4a
      photos/<photo_id>.jpg
      thumbs/<photo_id>.jpg
<app cache>/exports-temp/<job_id>/   (tracked, safe to clear)
<app support>/models/                (Phase 2, user-downloaded)
```

Write files atomically where possible (write to temp name, flush, rename). Store paths relative to the media root so the app survives container path changes on iOS.

---

## 10. Platform implementation notes

### 10.1 iOS

- AVAudioSession category `playAndRecord` (or `record`) with appropriate options, `UIBackgroundModes: audio` for legitimate continuous recording.
- Start recording while the app is in the foreground. Recording can continue after lock when configured correctly.
- Handle interruption began/ended notifications. Resume only when the system indicates it is allowed. Otherwise show the user-resume path.
- Do not claim guaranteed auto-restart or voice cold-start from a locked or background state.
- App Intents and Live Activity live in native Swift targets bridged to Flutter.
- Info.plist: `NSMicrophoneUsageDescription`, `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription` (for time-window import). Clear, honest wording.
- Without a Mac and Apple signing, agents can prepare the project and CI but cannot produce TestFlight builds. Say so in `RELEASE_PLAN.md`.

### 10.2 Android

- Permissions: `RECORD_AUDIO`, `CAMERA`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MICROPHONE`, `POST_NOTIFICATIONS` (13+), `READ_MEDIA_IMAGES` and `READ_MEDIA_VISUAL_USER_SELECTED` (14+ partial access) for gallery import.
- Foreground service with type `microphone`, started from a user action while the app is visible. Follow restrictions on starting microphone capture from the background.
- Audio focus and call-state changes drive interruptions.
- Test Android 13 to the current release, including a device with aggressive battery management (for example Samsung or Xiaomi).

### 10.3 Windows

- Respect microphone and camera privacy settings, with a helpful message if blocked.
- Record while minimised. Touch-friendly layout for Surface at 150 to 200% scaling.
- Export to user-chosen folders (Documents, Downloads, USB drive).
- Tray icon, taskbar recording indicator, global hotkeys (Phase 2, MAY be pulled into v1.0).
- Builds for x64 and, where the toolchain supports it, ARM64 (Surface Pro X and newer ARM devices).
- Distribution: GitHub Releases with an installer (MSIX or Inno Setup) and a portable ZIP, version number, SHA-256 checksums, install steps and a SmartScreen warning note if unsigned.
- MSIX manifest capabilities if MSIX is used: `microphone`, `webcam`.

### 10.4 Bluetooth microphones

- Enumerate and observe the input route. Show the actual active mic.
- 10-second mic test with playback.
- On disconnect: fall back with a timeline marker, or pause with a prompt. Never assume headset mics support high-quality capture.
- Test with AirPods or similar, a typical headset and an inexpensive Bluetooth lapel mic.

### 10.5 Calls and interruptions

Finalise or suspend the current segment safely, log the interval, never record the call, resume only through OS-supported means, keep partial audio if resume is refused, and tell the user visibly.

---

## 11. UX screens

1. **Welcome**: Create a conference / Open previous. No sign-in.
2. **Quick conference creation**: name, dates, role, goals. Skip anything optional.
3. **Conference home**: Start activity (dominant), quick type buttons, timeline, storage summary.
4. **Recording**: oversized Record/Pause/Stop, timer, mic route and level, Photo, Bookmark, Quick thought, quality chip, storage budget, consent banner.
5. **Activity detail**: segments and photos on a timeline, notes, contact fields, consent status.
6. **Review and edit**: player, waveform, photo and bookmark markers, gaps, trim, split, rename, reclassify, undo.
7. **Export**: scope, destination (Local, Google Drive, OneDrive), folder or ZIP, audio mode, include private items toggle, size and readiness check, Copy AI prompt.
8. **Storage Manager**: per-conference breakdown, export status, cleanup actions.
9. **Settings**: as section 5.11.

**Copy guidelines:** UK English. Short, plain sentences. Say what happened and what to do next. Examples:
- "Recording paused for a call. It will carry on when you hang up."
- "Couldn't resume after the call. Tap to carry on recording."
- "About 45 minutes of space left at Balanced quality."
- "Storage nearly full. Recording stopped and saved."
- "'Data Mesh Keynote' is still recording. Stop it and start a new one?"

A first-time user must find Record, Photo and Bookmark without a tutorial. Tap targets at least 48 by 48 dp. Full VoiceOver, TalkBack and Windows Narrator labels. Supports large text and dark mode.

---

## 12. Storage, memory and battery engineering (release blockers)

1. Record straight to disk with bounded encoder buffers. No session-length byte arrays.
2. Waveforms from decimated summaries, paged rendering, generated in the background after a segment finalises.
3. Image cache capped. Decode at display size. Dispose controllers, players and streams. Release the microphone on stop.
4. Hashing, compression, import, export and transcription run off the UI isolate. Pause heavy background work while recording is under stress.
5. Do not bundle models, demo media, unnecessary fonts or large icon packs. Record APK/AAB, IPA and Windows installer sizes and installed sizes separately from user data.
6. No universal RAM figure is promised. Establish a per-device baseline and budgets from measurement. Profile with Flutter DevTools (Memory and Performance) plus Android Studio, Instruments and Windows tools where available.
7. Expected size check: eight hours at Balanced should be about 173 MB plus overhead. Report real measured figures.

---

## 13. Testing and quality

### 13.1 Automated

- **Unit:** goals, activity types, profile precedence, state machine transitions, segment rolling, offset calculation across gaps, cut-range maths, split logic, storage estimates, filename sanitisation and path length, manifest generation, checksum streaming, preservation of originals.
- **Widget:** start/stop confirmation, starting an activity while recording (one-active prompt), permission denial flows, crash recovery prompt, deletion confirmation, quality selector estimates.
- **Integration (end to end):** conference with three activities at mixed profiles, photos, bookmarks, a simulated interruption, trim, export, then re-import and compare metadata, counts and checksums.
- **Migration tests** for every schema version.

### 13.2 Manual real-device tests

60 to 90-minute session, 8-hour conference day, under 1 GB free, near the hard reserve, airplane mode, screen lock, incoming call (answered and declined), alarm, Bluetooth connect and disconnect mid-recording, permission revoked mid-recording, low battery, app killed by OS, photo burst during recording, rapid start/stop taps.

### 13.3 Acceptance tests (v1.0 blockers)

| ID | Test |
|---|---|
| AT-REC-01 | 90 minutes recorded with screen locked and other apps in use. No gaps except logged interruptions. |
| AT-REC-02 | Incoming call pauses and resumes (or offers resume) on iOS and Android. Call audio is never recorded. |
| AT-REC-03 | Force-kill mid-recording loses at most the current segment. Recovery offered on next launch. |
| AT-REC-04 | Starting a second recording always triggers the one-active prompt or the documented default for non-visual triggers. |
| AT-PHO-01 | 20 photos taken during a recording cause no audio loss, or each causes a logged, auto-resumed interruption. |
| AT-QUAL-01 | Three activities at Economy, Balanced and Enhanced record, play and export correctly with correct metadata. |
| AT-QUAL-02 | Mid-recording quality change creates a new segment or declines safely. Earlier audio intact. |
| AT-QUAL-03 | Bluetooth route changes never mislabel codec or channels. |
| AT-STO-01 | 8-hour mixed-profile conference: measured disk use compared with shown estimates. |
| AT-STO-02 | Near-full storage: warnings shown, current segment finalised before exhaustion, reason shown, earlier files intact. |
| AT-STO-03 | Export larger than safe temp space aborts before any source is touched. |
| AT-STO-04 | Verified export then approved cleanup frees the announced space. No silent deletion. Failed export deletes nothing. |
| AT-MEM-01 | Low-RAM phone, locked-screen recording plus repeated photo workflow: no sustained memory growth, no OS kill. |
| AT-EXP-01 | Export ZIP opens on Windows and macOS. Paths within limits. `README_START_HERE.md` and `analysis_prompt.md` contain role, goals, outputs and every activity. Checksums validate. |
| AT-EXP-02 | Round trip: export then re-import reproduces metadata and media. |
| AT-OFF-01 | All core workflows work with no network, no account and no models. |
| AT-WIN-01 | Tagged release produces a downloadable Windows build that records, photographs and exports on a Surface (or recorded as unverified if no device). |

Phase 1.5 cloud tests (AT-CLD-01 to 10) and Phase 2 tests are listed in `docs/TEST_PLAN.md` following sections 6 to 8.

### 13.4 Definition of done for v1.0

A new user can create two conferences, set goals, record several sessions at chosen qualities while using the phone normally where permitted, add photos and bookmarks, survive interruptions without losing earlier audio, review and trim non-destructively, and export everything with an analysis-ready manifest to a Windows PC, without signing in or paying. Each platform's status is reported per device only after real testing.

---

## 14. Release and distribution

- Semantic versioning. `0.x` during development, `1.0.0` when section 13.4 passes.
- GitHub Actions: format check, static analysis, tests on every push. On tags: Windows build artefacts (installer, portable ZIP, checksums) attached to a GitHub Release. Android debug APK artefact. iOS build only when signing is available.
- Licence review of every dependency and model before choosing MIT or Apache 2.0 (P0-08). Include a `THIRD_PARTY_NOTICES.md`.
- Store listings later: privacy declarations stating no data collected, honest background audio and microphone service justification.

---

## 15. Analysis prompts bundled in every export

### 15.1 `analysis_prompt.md` (default)

> You are analysing a personal conference archive. The owner's role is {role}. Their key questions are: {goals}. They want these outputs: {outputs}.
>
> Organise the evidence by activity and timestamp. Use the session notes, recordings or transcripts, photographs and the owner's reflections that you can actually open. If a file cannot be opened or transcribed, say which one and ask for an accessible version.
>
> Keep four things separate: (a) what a speaker demonstrably said, (b) the owner's own observations, (c) your inferences, (d) suggested next steps. Do not invent quotations, speakers, outcomes or statistics. Link every key takeaway to a filename and timestamp where available. Bookmarked moments in `timeline.csv` were marked as important by the owner, so give them extra attention.
>
> For each activity, summarise the key points as they relate to the owner's goals. Then give overall takeaways, open questions and follow-up opportunities. Flag anything from private conversations before suggesting it is used publicly.

### 15.2 Extra templates in `prompts/`

- `presentation_outline.md`: build a 10 to 12 slide outline for {role}'s audience, one idea per slide, each with supporting evidence references and a suggested slide photo from the archive where relevant.
- `linkedin_post.md`: draft a LinkedIn post of 150 to 250 words in the owner's voice, built around two or three takeaways tied to {goals}, no invented claims, no confidential content.
- `blog_draft.md`: draft a 900 to 1,200 word blog post with a clear argument, sections linked to activities, and a sources list of activity titles and speakers.
- `briefing_note.md`: one-page briefing for colleagues: context, key findings, implications for the organisation, recommended actions.

All templates are filled with the conference's role, goals and outputs at export time.

---

## 16. Roadmap

| Phase | Name | Goal |
|---|---|---|
| 0 | Foundations and feasibility | Repo, CI, data model, and real-device proofs of the risky platform behaviour |
| 1 | Free core v1.0 | Everything in section 5 on Android, iOS and Windows. Storage and memory release gate |
| 1.5 | Cloud export | Google Drive and OneDrive, opt-in |
| 2 | Pocket mode and offline voice | Section 6, agenda import, offline transcription, push-to-talk commands |
| 3 | Opt-in AI and later ideas | Section 8.2, business card and badge QR capture, follow-up reminders, iPad and macOS layouts, optional sync without breaking the no-account path |

Video capture stays out of scope until after Phase 3, and only as short, opt-in clips with storage estimates.

---

## 17. Task backlog

Status values in `docs/PROGRESS.md`: todo, in progress, blocked, done (with test evidence).

### Phase 0: foundations and feasibility

| ID | Task | Depends on | Done when |
|---|---|---|---|
| P0-01 | Audit official platform docs and candidate packages. Record versions, support and licences | | `PLATFORM_FEASIBILITY.md` and `ARCHITECTURE.md` drafted |
| P0-02 | Scaffold Flutter workspace with iOS, Android, Windows targets, Riverpod, Drift, lint rules | P0-01 | Builds locally and in CI |
| P0-03 | Create all docs listed in 1.6 with initial content | P0-02 | Files exist and are linked from README |
| P0-04 | Spike: background recording with lock on Android and iOS, call interruption and resume | P0-02 | Pass/fail/blocked matrix with device, OS, logs |
| P0-05 | Spike: photo capture during recording on each platform | P0-04 | Result recorded, mitigation chosen (ADR) |
| P0-06 | Spike: Windows mic capture, AAC support, export to folder | P0-02 | Result recorded |
| P0-07 | Spike: Bluetooth mic routing and fallback | P0-04 | Result recorded |
| P0-08 | Dependency and model licence review, choose project licence | P0-01 | ADR and `THIRD_PARTY_NOTICES.md` |
| P0-09 | Data model, migrations, repositories and fixtures (section 9.4) | P0-02 | Unit and migration tests pass |
| P0-10 | Spike: 90-minute low-spec recording, memory trend, file size, battery | P0-04 | Measured figures recorded |
| P0-11 | Spike: low-storage simulation and streaming export with bounded RAM | P0-09 | Result recorded |
| P0-12 | Spike: per-segment profile switching and observed bitrate reporting | P0-04 | Result recorded |
| P0-13 | Spike: iOS App Intent and Android tile triggering a recording | P0-04 | Feasibility documented for Phase 2 |
| P0-14 | Spike: trimming approach per platform | P0-06 | ADR-003 written |

### Phase 1: free core v1.0

| ID | Task | Requirements |
|---|---|---|
| P1-01 | Conference wizard and quick start | FR-CONF-01 to 08 |
| P1-02 | Conference home and activity list | FR-ACT-01 to 03 |
| P1-03 | Activity CRUD, custom types, consent check, contact fields | FR-ACT-04 to 08 |
| P1-04 | RecordingService with state machine and mutex | FR-REC-01, 02, 09 |
| P1-05 | Rolling segment writer and atomic finalisation | FR-REC-03 |
| P1-06 | One-active rule across all triggers | FR-REC-04 |
| P1-07 | InterruptionCoordinator (calls, alarms, routes, camera) | FR-REC-05, FR-PHO-07 |
| P1-08 | Crash recovery and reconciliation | FR-REC-08 |
| P1-09 | Recording profiles and selector with estimates | FR-QUAL-01 to 08, FR-UI-08 |
| P1-10 | Recording screen UI with level meter and mic test | FR-UI-01 to 06 |
| P1-11 | Android foreground service and notification actions | FR-REC-10 |
| P1-12 | StorageBudgetService and live budget UI | FR-STO-01 to 04, FR-UI-07 |
| P1-13 | Safety prompts (duration, silence, battery) | FR-REC-06 |
| P1-14 | Photos: in-app capture, compression, thumbnails | FR-PHO-01 to 04, 06 |
| P1-15 | Gallery import by time window | FR-PHO-05 |
| P1-16 | Bookmarks and notes | FR-BMK-01 to 03 |
| P1-17 | Player, timeline, waveform summaries | FR-REV-01 to 03 |
| P1-18 | Non-destructive trim with undo, split activity | FR-REV-04, 05 |
| P1-19 | Permanent trim per ADR-003 | FR-REV-06, 07 |
| P1-20 | Storage Manager and cleanup | FR-STO-05 to 07 |
| P1-21 | Export service: scopes, streaming, preflight, checksums, safe paths | FR-EXP-01 to 07, 10 |
| P1-22 | Manifest, timeline CSV, README and prompt generation, Copy AI prompt | FR-EXP-08, 09, section 15 |
| P1-23 | Re-import of exports | FR-EXP-11 |
| P1-24 | Privacy UX and optional app lock | FR-PRI-01 to 06 |
| P1-25 | Settings screen | 5.11 |
| P1-26 | Accessibility pass | NFR-09, section 11 |
| P1-27 | Windows layout, minimised recording, export, tray indicator | 10.3 |
| P1-28 | GitHub Actions release pipeline for Windows | Section 14 |
| P1-29 | Full acceptance test run and QA report | Section 13 |

### Phase 1.5: cloud export

| ID | Task |
|---|---|
| P15-01 | Provider app registrations documented (Google Cloud, Microsoft Entra), no secrets in repo |
| P15-02 | CloudConnectionRepository with secure token storage, connect and disconnect |
| P15-03 | Google Drive adapter with resumable upload and `drive.file` scope |
| P15-04 | OneDrive adapter with Graph upload sessions and `Files.ReadWrite` |
| P15-05 | Durable upload queue, retries, expiry, de-duplication |
| P15-06 | Export UI destinations, Wi-Fi rules, progress, verification levels |
| P15-07 | Platform background transfer handling (iOS, Android, Windows) |
| P15-08 | Cloud acceptance tests AT-CLD-01 to 10 |

### Phase 2: pocket mode and offline voice

| ID | Task |
|---|---|
| P2-01 | iOS App Intents and Siri phrases |
| P2-02 | iOS Live Activity and lock-screen controls |
| P2-03 | Android shortcuts, Quick Settings tile, deep links, assistant check |
| P2-04 | Windows global hotkeys |
| P2-05 | In-app push-to-talk commands |
| P2-06 | Headset button bookmark experiment |
| P2-07 | Agenda import (CSV, ICS) and pick from planned sessions |
| P2-08 | Offline transcription model manager and jobs |
| P2-09 | Transcripts in export and prompts |

### Phase 3: opt-in AI and later ideas

| ID | Task |
|---|---|
| P3-01 | AI provider adapter interface with BYO key |
| P3-02 | Grounded summaries and takeaways per goal |
| P3-03 | Presentation outline, LinkedIn, blog and briefing generation in-app |
| P3-04 | Business card and badge QR capture for conversations |
| P3-05 | Follow-up reminders after conversations |
| P3-06 | iPad and macOS layouts |

---

## 18. Conflicts resolved between v1 and v2

| Topic | v1 | v2 | v3 decision |
|---|---|---|---|
| Name | ConfCapture | Conference Companion | Conference Companion |
| Audio presets | Speech 48 / High 96 kbps | Economy 32 / Balanced 48 / Enhanced 64, per session | v2 presets with per-session override |
| Segments | Roll every 10 min and on pause | On interruption | Both: roll on pause, interruption, quality or route change and every 10 min |
| Windows timing | Phase 3 | v1.0 | v1.0 core, hotkeys in Phase 2 |
| Voice control | Siri and assistant shortcuts in Phase 2 | Cautious, push-to-talk in Phase 2 | Shortcuts and push-to-talk in Phase 2, feasibility spike in Phase 0 |
| Gallery import | By time window | Manual import | Both |
| Export prompts | Several templates and Copy button | One evidence-grounded prompt | Evidence-grounded default plus four templates and Copy button |
| Export size for AI | Split by day, compressed copy | Folder vs ZIP, streaming | All of these |
| Cloud | Not covered | Phase 1.5 | Phase 1.5 as v2 |

---

## 19. References (check current versions during P0-01)

- Flutter supported platforms and desktop: https://docs.flutter.dev
- Flutter DevTools memory: https://docs.flutter.dev/tools/devtools/memory
- Flutter DevTools performance: https://docs.flutter.dev/tools/devtools/performance
- Apple AVAudioRecorder: https://developer.apple.com/documentation/avfaudio/avaudiorecorder
- Apple App Intents: https://developer.apple.com/documentation/appintents
- Apple ActivityKit (Live Activities): https://developer.apple.com/documentation/activitykit
- Android foreground service types: https://developer.android.com/develop/background-work/services/fgs/service-types
- Android background data transfer: https://developer.android.com/develop/background-work/background-tasks/data-transfer-options
- Google Drive scopes: https://developers.google.com/workspace/drive/api/guides/api-specific-auth
- Google Drive resumable uploads: https://developers.google.com/workspace/drive/api/guides/manage-uploads
- Google OAuth for installed apps: https://developers.google.com/identity/protocols/oauth2/
- Microsoft Graph upload sessions: https://learn.microsoft.com/graph/api/driveitem-createuploadsession
- MSAL flows: https://learn.microsoft.com/en-us/entra/identity-platform/msal-authentication-flows
- Microsoft mobile app registration: https://learn.microsoft.com/en-us/entra/identity-platform/scenario-mobile-app-configuration
- Apple background URLSession: https://developer.apple.com/documentation/foundation/urlsessionconfiguration/background(withidentifier:)
- whisper.cpp: https://github.com/ggml-org/whisper.cpp

**Start with Phase 0 and the real data model. Do not build transcription, AI, cloud, wake words, video or sync before the offline capture and export foundation passes its acceptance tests.**
