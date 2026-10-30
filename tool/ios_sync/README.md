# Shared-source iOS updates (P1-43)

Develop shared Flutter behaviour once in the main attenlume repository. After
each development task, export the current source for the working Mac project:

```powershell
python tool/ios_sync/export_update.py
python tool/ios_sync/export_update.py --check
```

Run from the source repo. Requires Python 3.9+ and Git. Only Git-tracked,
allowlisted source/resources are exported: stage new task files first so they
are included, and commit completed work. Tracked edits/deletions are captured
and recorded; untracked files are excluded. Inspect the working tree first.

Output is in sibling **attenlume-ios-updates**, with a dated/versioned folder,
matching ZIP and LATEST.json pointing to the newest pack. Copy that ZIP/folder
to the Mac beside its existing project and give its AI MAC_AI_MERGE.md.
LATEST.json also records the archive SHA-256. The pack has per-file checksums.

Every pack carries the full canonical source baseline at the original handoff
commit and current source; earlier packs need not be imported first. The compare
helper uses Git's three-way text merge and proposes changes in a separate review
folder. It cannot apply changes to the app. Native ios/ changes are always
flagged for manual review; local fixes and signing are not overwritten.

The original attenlume-ios folder and handoff ZIP remain historical references.
They are not the current Mac working copy, and should not be repeatedly patched
by hand. The new updates folder makes its purpose clear without breaking old
transfer references. incoming/ is source for comparison, not an independent
build template: the Mac owns its working runner and generated native setup.

## Rules for developers on Windows

- Inspect ios/ and this workflow for each app task. Reuse shared Dart code;
  check every new dependency for iOS support. Describe required native changes
  and device checks in the task handover and docs/IOS_SYNC_NOTES.md.
- Preserve the fixed baseline. Do not choose the last exported pack as an
  ancestor unless the Mac has confirmed that exact pack was applied.
- After the task checks pass, stage all new source files and export. Run
  --check, and record the pack path/ID and Mac-only work. --check fails when
  tracked shared source has changed since the latest export.
- New rules are in AGENTS.md; CLAUDE.md follows it and the unattended prompt
  explicitly requires this export. There is no background network sync.
- If the Mac changes shared code, bring its diff back and merge it here before
  further overlapping work. Longer term, a common Git remote/branch with normal
  PR merges is the simplest transport; no remote/push is configured by this task.

## Verification

```powershell
python -m unittest discover -s tool/ios_sync/tests -v
```

Tests cover preserving Mac edits, nonoverlapping merges, overlapping/binary
conflicts, additions/deletions, native protection, transfer corruption and path
escape rejection. Python helpers use only the standard library and local Git.
