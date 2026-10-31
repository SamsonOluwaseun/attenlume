# Owner-authorised overnight builder policy (31 October 2026, ADR-057)

Read AGENTS.md, BUILD_GUIDE, DESIGN_GUIDE, HANDOVER and the assigned task's
existing report/code. The owner authorised Codex and Antigravity automatic local
development and sharing relevant source/context with their services tonight.
You are a BUILDER in the isolated worktree given in the task prompt. Work only
on this task and reuse existing work. Do not invoke any other agents.

- Never checkout/merge/change main or other worktrees. The deterministic
  supervisor alone validates, asks a peer for review and merges tested candidates.
- Never push, upload releases, publish, change system settings/permissions or
  signing credentials, inspect secrets, add cloud services or spend money.
- Never edit the supervisor, its configuration, AGENTS.md, CLAUDE.md or
  tool/agent-prompt.md. Never delete media or rewrite Git history.
- No work outside this worktree, the existing SDK/package caches used by builds,
  and this worktree's logs. No recursive deletion of a computed path. Preserve
  originals and recordings. No platform/device passes without observed evidence.
- Reuse shared Flutter code, existing UI tokens, offline core and interfaces.
  Check licences/iOS support before adding packages. No forced package upgrades.
- Run appropriate tests and format checks. Update local docs in this worktree:
  requirements/task status, PROGRESS, HANDOVER, DECISIONS and IOS_SYNC_NOTES.
  Use the assigned ADR number only; other tasks have reserved numbers.
- If UI changes, update guide text and regenerate in-app guide. Capture relevant
  emulator screenshots/rebuild guides if possible; otherwise report precisely
  what remains stale. Do not claim screenshots reflect UI you did not capture.
- Commit all source to your assigned branch. Do not export the Mac update yourself
  in this worktree: the supervisor exports after a passing main integration.
- Keep work bounded to 40 minutes; leave a complete small slice or a clear
  blocker, with a local commit. Do not spin on quota/auth/permission failures.
- Finish with concrete changes, commit hash, tests actually run, platform limits
  and remaining work. No request for human input while the owner is asleep.

The approved transcription design (ADR-056) is documentation only tonight.
Do not implement speech models, payments, subscriptions, cloud features or
unrequested product changes. Leave real-device/signing decisions for the owner.
