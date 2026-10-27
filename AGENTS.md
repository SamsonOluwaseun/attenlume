# AGENTS.md

Operating rules for any AI coding agent working on Conference Companion (Claude Code, Codex, Antigravity, Cursor or others).

## Read first, in this order

1. `AGENTS.md` (this file)
2. `docs/BUILD_GUIDE.md` (the full specification, source of truth)
3. `docs/DESIGN_GUIDE.md` and `design/tokens.json` (brand, screens, tokens; the product is named **Attenlume**)
4. `docs/HANDOVER.md` (where the last agent stopped)
5. `docs/PROGRESS.md` (what is done)
6. `docs/DECISIONS.md` (decisions already made)

If `docs/HANDOVER.md` does not exist yet, start at task P0-01 in section 17 of the build guide.

## Every session

1. Run tests and static analysis before changing anything. Note the result in `docs/PROGRESS.md`.
2. Continue the task named in `docs/HANDOVER.md`, otherwise take the next task in section 17 whose dependencies are done.
3. Plan briefly, then build. One task per branch where practical.
4. Add tests named with the requirement ID they prove (for example `FR-REC-03`).
5. Reference IDs in commits: `feat(export): streaming zip writer [FR-EXP-04, P1-21]`.

## Rules

- Offline-first. No account, network, API key or AI model needed for the core app.
- Never claim something works without a passing test or a recorded real-device check. Mark untested platforms as unverified.
- Never invent benchmark numbers.
- Never delete or overwrite original recordings or photos automatically.
- Do not replace working code without an ADR in `docs/DECISIONS.md`.
- Check that every new package is maintained, supports iOS, Android and Windows as needed, and has a compatible licence.
- No secrets, tokens or personal data in the repo, logs or exports.
- UK English in all user-facing text.

## Unattended mode (overnight supervisor)

`tool/overnight.ps1` runs Claude Code, Google Antigravity and OpenAI Codex in turns, one task per run. When started by it:

- Nobody is watching. Do not ask questions. Put them under "Open questions for the owner" in `HANDOVER.md` and pick the safest option that keeps work moving.
- Work on a task branch, and when the task's tests and `flutter analyze` pass, merge it into `main` with `--no-ff` so the next agent starts from it. Never push to any remote.
- Tasks that need a real phone, Surface, Mac or signing (most Phase 0 spikes): build the spike harness and its automated parts, write the manual test steps, mark the task **blocked: needs real device** in `PROGRESS.md`, and move on. Never record a pass you did not observe.
- Phase 1 work may proceed on top of unverified spikes. Choose the documented default, record it as an ADR, and keep the platform code behind interfaces so it can change after device testing.
- Finish within about 90 minutes. If the task is bigger, commit a clean slice, hand over, and stop.
- Stay inside this repository and the Flutter/Android SDK folders. No system-wide changes.

## Before you stop (mandatory)

Do this when the task is done, or as soon as your context or token budget is running low:

1. Commit everything. Half-finished work goes on its task branch marked `WIP`. The default branch must still build.
2. Update `docs/PROGRESS.md` with what was done and test results.
3. Overwrite `docs/HANDOVER.md` using the template below.
4. Record any decision in `docs/DECISIONS.md`.

## HANDOVER.md template

```markdown
# Handover

Date and agent:
Branch:
Current task ID:
Status: in progress / blocked / done

## Done in this session

## Left to do on this task

## Exact next step

## Files touched

## Failing or skipped tests

## Open questions for the owner

## Commands to run
```
