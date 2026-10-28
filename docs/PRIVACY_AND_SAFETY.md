# Privacy and safety

**Status:** initial version from task P0-03, 27 October 2026, Claude Code (Opus 5.5). Derived from `docs/BUILD_GUIDE.md` sections 2.4, 3 (NFR-01, NFR-09, NFR-13), 5.12, 7.2 and 10. Owner to review. Nothing here is implemented yet unless marked otherwise.

This file records how Attenlume handles consent, personal data, local storage, retention and sharing. It is a design record, not legal advice. The app does not replace the user's own legal obligations (for example UK GDPR) and must not claim to (FR-PRI-05).

---

## 1. Principles

1. **On device by default.** All data stays on the device unless the user exports or uploads it (FR-PRI-03).
2. **No account needed.** No login, internet, API key, subscription or AI model is needed for the core app (NFR-01).
3. **No tracking.** No analytics, ads, crash reporters or trackers by default (FR-PRI-03, NFR-09). Adding any of these later needs an ADR, an off-by-default setting and an update to this file.
4. **Visible recording.** Always-visible recording banner and quick stop. No stealth or hidden modes (FR-PRI-02). The product is not a covert recording tool (build guide 2.4).
5. **The user decides about deletion.** Originals are never deleted automatically (NFR-07, NFR-11). "Delete" means delete (FR-STO-07).
6. **Least privilege.** Permissions are asked for only when first needed, with a plain explanation (FR-PRI-04). Cloud scopes are the narrowest that work (7.2).

---

## 2. Consent and recording etiquette

| ID | What the app does |
|---|---|
| FR-CONF-06 | Conference set-up shows "Some events and speakers don't allow recording. Record only when permitted." and requires acknowledgement. The time is stored in `conferences.policy_acknowledged_at`. |
| FR-PRI-01 | Before the first recording in a conference, the policy reminder is shown again if it has not been acknowledged. |
| FR-ACT-07 | For business conversations and networking: "Does the other person know you are recording?" with "Yes" and "Not recording audio". The answer is stored in `activities.recording_permission_status` (unknown, permitted, not_permitted, participant_aware) and appears in exports. |
| FR-ACT-08 | Contact details are typed by the user. No facial recognition and no automatic identity extraction from photos or audio. |
| FR-UI-05 | Private reflections (quick thoughts, voice memos) are stored separately and never mixed into speaker audio. |
| FR-PRI-02 | Recording indicator always visible: in-app banner, Android foreground notification, iOS system microphone indicator, Windows taskbar indicator (10.3). |

Pocket mode (Phase 2) must keep the same visibility: every non-visual trigger confirms by notification or haptic, and the system recording indicators stay on (build guide 6).

---

## 3. Data the app stores

All on the device, in the app's private storage (build guide 9.5).

| Data | Where | Notes |
|---|---|---|
| Conferences, goals, activities, bookmarks, cut ranges, notes, contact fields | SQLite database (Drift) | Times in UTC ISO 8601. |
| Audio segments | `<app data>/media/conferences/<id>/activities/<id>/audio/` | Original files kept until the user deletes them. |
| Photos and thumbnails | Same tree, `photos/` and `thumbs/` | In-app photos are not also saved to the camera roll (FR-PHO-04). Imported photos are copied, the camera roll original is left alone. |
| Temporary export files | `<app cache>/exports-temp/<job_id>/` | Tracked and safe to clear. Never the only copy of any media. |
| Settings | `app_settings` table | No personal data needed. |
| Cloud tokens (Phase 1.5) | iOS Keychain, Android Keystore-backed storage, Windows credential protection | Never in SQLite, logs, manifests or the repo (7.2). The database stores only `token_secure_ref`. |
| Offline models (Phase 2) | `<app support>/models/` | User-downloaded, deletable. |

**Not stored:** location from GPS (venue is typed by hand), device identifiers, advertising IDs, contacts from the address book, biometric data (app lock uses the OS prompt and receives only pass or fail).

**Sensitive categories the user may capture:** identifiable people (voices, faces in photos), unpublished research, commercial, medical or financial content. The app cannot tell what is sensitive, so it warns before export or upload (FR-PRI-05) and lets the user exclude private items (FR-EXP-10).

---

## 4. Retention and deletion

- Nothing expires automatically. Data stays until the user deletes it.
- Deleting a conference shows a summary of what will be deleted (activities, recordings, photos, total size) and needs confirmation (FR-CONF-08).
- "Delete local copies" in Storage Manager is offered only after a verified export, with a preview and a separate confirmation (FR-STO-06). A failed export deletes nothing (AT-STO-04).
- Permanent trim writes new files first and only then offers to remove originals (FR-REV-06).
- Archived index (FR-STO-07) keeps metadata and thumbnails only, and only if the user chooses it.
- Uninstalling the app removes its private storage (OS behaviour). Exports the user saved elsewhere are not touched.
- Cloud (Phase 1.5): uploading never deletes local files automatically (NFR-13). Disconnecting a provider wipes local tokens and revokes where possible, but never deletes remote files without a separate instruction (7.1).

---

## 5. Sharing and export

- Data leaves the device only through an action the user starts: local export, share sheet, or (Phase 1.5) cloud upload.
- Private activities (`is_private`) are excluded from exports by default (FR-EXP-10).
- Before export or upload, a warning covers identifiable people, unpublished research and commercial, medical or financial content (FR-PRI-05).
- Every export includes a consent and confidentiality note in `README_START_HERE.md` (build guide 5.10).
- The analysis prompt tells any AI tool to flag material from private conversations before suggesting public use (build guide 15.1).
- Exports contain no tokens, no device identifiers and no app-internal absolute paths. Manifests use relative paths.
- No public share links are created automatically (7.2).

---

## 6. Permissions

Asked only when first needed, each with a plain explanation (FR-PRI-04). Wording below is the starting point for the platform strings. Status: not yet added to the projects (P0-02 scaffold has none).

| Permission | Platform | When asked | Why (user-facing draft) |
|---|---|---|---|
| Microphone (`RECORD_AUDIO`, `NSMicrophoneUsageDescription`) | Android, iOS | First Record tap | "Attenlume records audio of sessions you choose to capture. Recordings stay on this device unless you export them." |
| Camera (`CAMERA`, `NSCameraUsageDescription`) | Android, iOS | First Photo tap | "Attenlume takes photos of slides and posters and links them to your recording." |
| Photo library (`READ_MEDIA_IMAGES`, `READ_MEDIA_VISUAL_USER_SELECTED`, `NSPhotoLibraryUsageDescription`) | Android 13+, iOS | First gallery import | "Attenlume can import photos you took during a session. Only the photos you pick are copied." |
| Notifications (`POST_NOTIFICATIONS`) | Android 13+ | First recording | "Shows that recording is on and lets you pause, stop or bookmark from the notification." |
| Foreground service, type microphone | Android | Declared, not prompted | Needed for recording with the screen locked. Started only from a user action while the app is visible (10.2). |
| Background audio (`UIBackgroundModes: audio`) | iOS | Declared, not prompted | Needed to continue a recording the user started after the screen locks (10.1). |
| Microphone, webcam (Windows privacy settings, MSIX capabilities if used) | Windows | First Record or Photo | If blocked, explain how to allow it in Windows privacy settings (10.3). |

Store listings (build guide 14) must state that no data is collected and give an honest justification for background audio and the microphone service.

---

## 7. Cloud export (Phase 1.5, summary of build guide 7.2)

- Opt-in only. The app stays fully usable with no account and no internet (NFR-13).
- OAuth 2.0 authorisation code with PKCE through the provider's own flow or system browser. No embedded password forms, no client secrets treated as secret on devices, no service accounts.
- Google Drive: `drive.file` scope only. OneDrive: Microsoft Graph delegated `Files.ReadWrite`, not `.All`.
- Tokens only in platform secure storage (section 3).
- No automatic background upload of new recordings. Default private access on the remote side.
- Provider quotas, data charges and API limits apply. The app says so.
- Upload never deletes local files. Local cleanup is a separate step after verified backup.

---

## 8. AI (Phase 3, summary of build guide 8.2)

- Off unless the user turns it on. Bring-your-own key or provider account in secure storage.
- Explicit consent before any upload, per job.
- No automatic publishing anywhere.
- With AI switched off the app behaves exactly as v1.0.

---

## 9. App lock

Optional lock using device biometrics or PIN through the OS (FR-PRI-06). Off by default. The app never sees or stores biometric data.

Implemented in P1-24 (ADR-041): `local_auth` (Android BiometricPrompt with device credential, iOS Face ID, Touch ID or passcode, Windows Hello). Turning it on needs one successful OS prompt. It locks on start and after the app has been in the background for the chosen grace period (Immediately, 1 minute by default, or 5 minutes). Recording, the notification and its actions keep running while locked, and the lock screen shows that a recording is on with a Stop button but not its title. If the device can no longer check (for example the PIN was removed), the lock screen explains this and offers to turn the lock off rather than keep the person from their recordings. Unverified on real devices.

---

## 10. Safety of the user's data

These protect recordings from loss rather than from other people, but they are promises to the user, so they are listed here.

- Metadata is written to the database before audio (FR-REC-01).
- Rolling segments: a crash loses at most the current segment (FR-REC-03).
- Atomic file writes where possible (temp name, flush, rename) (9.5).
- Storage hard stop finalises the current segment before the disk fills (FR-STO-04).
- Damaged files are never marked good (FR-REC-08).
- Export preflight declines safely, and a failed export never corrupts or deletes sources (FR-EXP-05).

---

## 11. Repository and logs

- No secrets, tokens or personal data in the repo, logs or exports (`AGENTS.md`).
- Logs, if added, must not contain titles, notes, contact details, speaker names or file contents. Log IDs and states only.
- Test fixtures use invented data.

---

## 12. Open questions

- Hard storage reserve per platform: to be set from P0-11 measurements.
- Store privacy declarations: to be written when store submission is planned (RELEASE_PLAN.md).
- Whether an opt-in crash reporter is wanted at all. Default answer: no.
