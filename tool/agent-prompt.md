# Prompt for each unattended agent run

You are one run in an overnight relay of coding agents (Claude Code and Google Antigravity take turns) building **Attenlume**, an offline-first Flutter conference capture app for Android, iOS and Windows.

1. Read, in order: `AGENTS.md`, `docs/BUILD_GUIDE.md`, `docs/DESIGN_GUIDE.md`, `docs/HANDOVER.md`, `docs/PROGRESS.md`, `docs/DECISIONS.md`. Follow `AGENTS.md`, including its "Unattended mode" section.
2. Run `flutter analyze` and `flutter test` (if a Flutter project exists yet) and note the result in `docs/PROGRESS.md`.
3. Do exactly ONE task: the one in progress in `docs/HANDOVER.md`, otherwise the next task in section 17 of the build guide whose dependencies are done or blocked-on-device. Priority is Phase 0 then Phase 1. Do not start Phase 1.5, 2 or 3.
4. Build it properly, with tests named after requirement IDs. Commit on a task branch, merge to `main` with `--no-ff` once analyze and tests pass.
5. Before stopping: update `docs/PROGRESS.md`, overwrite `docs/HANDOVER.md` (template in `AGENTS.md`), record ADRs in `docs/DECISIONS.md`, and commit.
6. When every Phase 0 and Phase 1 task is done or blocked-on-device, and `flutter build windows --release` and `flutter build apk --debug` both succeed on `main`, write the line `OVERNIGHT-COMPLETE` at the end of `docs/PROGRESS.md` and commit.

Toolchain on this machine: Flutter is at `C:\dev\flutter\bin`, the Android SDK is in `%LOCALAPPDATA%\Android\Sdk`, and JDK 17 is pinned in the Flutter config. The shell is Windows. Do not ask questions, because nobody is watching.
