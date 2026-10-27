# Release plan

**Status:** initial version from task P0-03, 27 October 2026, Claude Code (Opus 5.5). Derived from `docs/BUILD_GUIDE.md` sections 10.1, 10.3, 14 and 16, and ADR-001. Owner to review.

Nothing has been released. No build has been installed on a phone or a Surface yet.

---

## 1. Milestones

| Milestone | Version | Contents | Exit criteria |
|---|---|---|---|
| Phase 0: foundations and feasibility | `0.1.x` | Scaffold, docs, data model, platform spikes | Every P0 task done or blocked with a reason. Spike matrix in `PLATFORM_FEASIBILITY.md` filled from real devices |
| Phase 1: free core | `0.2.x` to `0.9.x` | Everything in build guide 5 on Android, iOS and Windows | All P1 tasks done. Storage and memory release gate (build guide 12) |
| v1.0 | `1.0.0` | Free offline core | Definition of done (build guide 13.4) passes and every AT in `TEST_PLAN.md` 4.1 passes on real devices, or the platform is listed as unverified in the release notes |
| Phase 1.5: cloud export | `1.1.x` | Google Drive and OneDrive, opt-in | AT-CLD-01 to 10 |
| Phase 2: pocket mode and offline voice | `1.2.x` | Build guide 6 and 8.1 | Phase 2 tests |
| Phase 3: opt-in AI | later | Build guide 8.2 | To be defined |

Version numbers after 1.0 are a starting suggestion, not a commitment.

---

## 2. Versioning

- Semantic versioning (build guide 14). `0.x` during development, `1.0.0` when build guide 13.4 passes.
- `pubspec.yaml` holds `version: <semver>+<build>`. Current: `0.1.0+1` (ADR-004).
- The build number increases with every build that leaves the developer's machine (store upload, GitHub Release).
- Releases are tagged `v<semver>` on `main`, for example `v0.2.0`.
- Every release has notes listing what changed, which platforms were tested on which devices, and which are unverified.

---

## 3. Continuous integration

Workflow: `.github/workflows/ci.yml` (P0-02). Dormant until the owner adds a GitHub remote (ADR-001).

| Trigger | Job | Status |
|---|---|---|
| Every push and pull request | Windows: codegen up to date, format, analyze, test, Windows debug build | written, never run |
| Every push and pull request | Ubuntu: Android debug APK, uploaded as an artefact | written, never run |
| Every push and pull request | macOS: unsigned iOS debug build (`--no-codesign`) | written, never run |
| Tag `v*` | Windows release artefacts attached to a GitHub Release | not written yet (P1-28) |

---

## 4. Distribution by platform

### 4.1 Windows (build guide 10.3)

- Channel: GitHub Releases.
- Artefacts per release: installer (MSIX or Inno Setup, decided in P1-28 with an ADR), portable ZIP, `SHA256SUMS.txt`, install steps.
- Architectures: x64. ARM64 where the Flutter toolchain supports it (check again in P1-28).
- Signing: none yet. Unsigned builds trigger Microsoft Defender SmartScreen. Release notes must say so and explain "More info, Run anyway". Code signing needs a certificate the owner buys or obtains later.
- MSIX, if chosen, declares the `microphone` and `webcam` capabilities.
- Status: `flutter build windows --debug` works on the build PC. No release build, installer or Surface test yet.

### 4.2 Android (build guide 10.2)

- Development: debug APK from CI or a local build, installed by hand on test phones.
- Testing: Google Play internal testing track once a Play developer account exists.
- Release: Google Play. An APK on GitHub Releases is also possible for people without Play.
- Signing: release builds need an upload keystore. It must never be committed. CI would read it from repository secrets, which do not exist yet.
- Play listing: data safety form stating no data collected, and a justification for the microphone foreground service.
- Status: `flutter build apk --debug` works on the build PC. Not installed on any phone.

### 4.3 iOS (build guide 10.1)

- **Blocked without a Mac.** The iOS project can be prepared and kept compiling in CI (unsigned debug build on a macOS runner), but agents on this Windows machine cannot build, sign, run on an iPhone or upload to TestFlight.
- To unblock, the owner needs: an Apple Developer Program membership, a Mac (or a macOS CI runner with signing certificates and provisioning profiles stored as secrets), and a registered bundle ID.
- Channel: TestFlight for testing, then the App Store.
- App Store listing: privacy nutrition label stating no data collected, and an honest explanation of background audio (`UIBackgroundModes: audio`).
- Status: not built. Every iOS result is unverified.

---

## 5. Identifiers

| Item | Value | Status |
|---|---|---|
| App name | Attenlume | decided (ADR-001) |
| Android application ID, iOS bundle ID | `com.samlytics.attenlume` | to be confirmed by the owner before the first store submission |
| Deep-link scheme | `attenlume://` | decided (ADR-001), used from Phase 2 |
| Publisher | Samlytics Data Services | to be confirmed |

---

## 6. Licence and notices

- Project licence: Apache 2.0 recommended in ADR-007 (P0-08), awaiting the owner's confirmation. Add `LICENSE` once confirmed.
- `THIRD_PARTY_NOTICES.md` is generated by `tool/licence_audit.dart` and checked by a test. Ship it with every release. In the app, the About screen opens Flutter's `showLicensePage`, and Montserrat's OFL is registered with `LicenseRegistry` (fonts are not in Flutter's automatic `NOTICES`).
- Brand assets (`assets/brand/`, `design/`) stay outside the open-source licence. Release blocker: confirm with the owner before publishing the repository.
- Re-run the audit for every new package, and before Phase 2 for model licences (Whisper, Vosk).
- Montserrat: SIL Open Font License 1.1 (`assets/fonts/OFL.txt`).

---

## 7. Release checklist (draft)

1. `main` is green: format, analyze, tests, codegen check.
2. Version bumped in `pubspec.yaml`. `docs/PROGRESS.md` updated.
3. Acceptance tests run on the devices available. Results logged in `TEST_PLAN.md` section 6. Untested platforms named as unverified in the notes.
4. App sizes recorded (APK or AAB, IPA, Windows installer, installed sizes) without invented figures (build guide 12).
5. `THIRD_PARTY_NOTICES.md` current.
6. Tag `v<semver>` and push. CI attaches Windows artefacts and checksums.
7. Release notes: changes, tested devices, known limits (for example the Windows 96 kbps floor, ADR-002), SmartScreen note.

---

## 8. Blockers and open questions for the owner

- GitHub remote, so CI can run (ADR-001).
- Apple Developer Program membership and a Mac or macOS signing set-up.
- Google Play developer account and an upload keystore.
- Windows code-signing certificate (optional, removes the SmartScreen warning).
- Confirm `com.samlytics.attenlume` and the publisher name.
- App icon exports (open question from P0-02, ADR-004 item 7).
