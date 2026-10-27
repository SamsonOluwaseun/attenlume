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
