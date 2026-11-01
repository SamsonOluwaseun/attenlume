# Instructions for the AI on the Mac

The owner reports that iOS already works on this Mac. Preserve that working
project. This pack updates shared Flutter source from Windows; it is not a
replacement iOS project. Never overwrite the entire Mac project with incoming/.

## First inspect, then merge

1. Read the working project's AGENTS.md and handover. Locate the Flutter root
   containing pubspec.yaml. Read this pack's UPDATE.json and README.md.
   Confirm with the user's context which Mac project is intended if ambiguous.
2. Save current work on a local Git branch/commit or create a source backup.
   Preserve uncommitted work. Do not include media, credentials or caches in
   source control. Do not reset or clean the working tree.
3. Check this pack from its root: `shasum -a 256 -c SHA256SUMS.txt`.
4. With Python 3.9+ and Git available (Xcode command line tools), run:

   ```bash
   python3 compare_on_mac.py --project /actual/path/to/attenlume --review ../ios-merge-review-UNIQUE
   ```

   Replace both paths; choose a new review folder each run. The helper is
   read-only with respect to the app. It validates source hashes, compares
   `base/`, `incoming/` and the working Mac files, and stages proposals in the
   new review folder. It does not apply or delete any app file.
5. Read REPORT.md and REPORT.json. Use them as evidence, then review the code:

   | Action | What to do |
   | --- | --- |
   | unchanged / preserved_local | Keep the Mac file, including Mac-only edits |
   | already_current | No action: Mac already has the incoming content |
   | add / update | Review proposed file, then copy it into the working project |
   | merged | Inspect the three-way merge under proposed/, then apply if correct |
   | delete | Upstream removed a file unchanged on Mac; review references and remove only that source file |
   | conflict | Resolve manually using all three versions; never copy conflict markers into app code |
   | native_review | Deliberately merge the source change into working iOS configuration; preserve signing and native fixes |

6. Before applying each action, verify the file still has REPORT.json's
   local_sha256 (or is still absent). If not, rerun comparison. Keep existing
   Mac-native fixes, Apple team, bundle ID, entitlements, provisioning, Pods
   configuration, SwiftPM integration and local deployment target. Mac files
   not listed in the source inventories are untouched by the comparison.
7. Merge pubspec.yaml and pubspec.lock together. Restore packages on Mac,
   review iOS support/minimum versions for any new plugin, and run the licence
   audit. Include generated database code/migrations when shared schemas change.
   An Android-native feature may need a separate iOS implementation; inspect
   platform channels and guards. Do not label unavailable features as working.
8. Run the working Mac project's build process: flutter pub get, flutter
   analyze, flutter test, licence audit, an iOS simulator build and the relevant
   physical-device checks for changed capture/camera/storage/permissions code.
   Keep actual evidence; do not infer a device pass from a source merge.
9. Record package_id/source_commit in IOS_SYNC_HISTORY.md in the Mac project,
   along with files merged, Mac-only choices, test results and unresolved work.
   Update its handover and commit locally. No push or upload is requested.
10. Put a persistent rule in the Mac project's AGENTS.md: use these three-way
    update packs; preserve Mac iOS fixes; record imports; do not blindly replace
    shared files. If Mac changes shared Dart or dependencies, return a patch or
    source changes to Windows for review so later Android work includes them.

## Why the baseline stays fixed

base/ is canonical source at the original Android-to-Mac handoff commit, before
the handoff's iOS-specific fixes. incoming/ contains the latest canonical source.
The Mac's working tree is the third version, including initial iOS fixes and
later work. All packs are cumulative: skipping an earlier transfer cannot
silently lose its updates. Repeated/overlapping changes can need manual merging;
the tool never selects Windows over Mac just because it is newer.

Native files are references, not a fresh build template. Windows cannot inspect
your Mac remotely. If the Mac received a different initial version, inspect the
three versions carefully and document the correct ancestor before resolving
conflicts. Never substitute a guessed baseline.

## When both folders are in the same Mac workspace

Use the existing Mac `attenlume-ios` as the working app. Do not copy the historical
Windows handoff over it. Place `attenlume-ios-updates` beside it. The AI coding
session needs filesystem access to both folders. Read `LATEST.json` to select one
cumulative pack; earlier packs need not be merged first. If only the latest ZIP
was transferred, keep LATEST.json with it and extract the ZIP in the updates
folder. Do not rename or edit the immutable package contents.

Example layout:

```text
workspace/
  attenlume-ios/                 # existing working Flutter project
    pubspec.yaml
    ios/
  attenlume-ios-updates/
    LATEST.json
    <package_id>.zip
    <package_id>/                # extracted pack
      MAC_AI_MERGE.md
      UPDATE.json
      compare_on_mac.py
      base/
      incoming/
```

## Pasteable request to the Mac AI

```text
My existing working iOS Flutter project is in `attenlume-ios`. The sibling
`attenlume-ios-updates` folder contains cumulative updates from Android/Windows.
Merge the latest update into the working iOS project; do not replace the project.

1. Read `attenlume-ios-updates/LATEST.json` and use its `package_id`. If the named
   package folder is absent, verify the named ZIP against `archive_sha256` and
   extract it into the updates folder. Read the package's `MAC_AI_MERGE.md`,
   `UPDATE.json` and `incoming/docs/IOS_SYNC_NOTES.md`, plus the working app's rules.
2. Locate the working Flutter root containing `pubspec.yaml`. Preserve all current
   work with a local source checkpoint or backup; leave secrets/media untracked.
3. Verify the package checksums. Run `compare_on_mac.py` FROM THE UPDATE PACKAGE
   against the working Flutter root, with a new sibling review folder. Read
   REPORT.md/REPORT.json. Compare base/incoming/working versions; review proposals
   and resolve conflicts. Keep Mac-only fixes, signing, team/bundle identifiers,
   entitlements and deployment configuration. Never blindly copy incoming/ over
   attenlume-ios, and never treat Windows native files as iOS replacements.
4. Merge shared code, resources, tests and dependency files together. Include the
   transcription setup/activity-lookup fixes, opening-page Settings gear, camera
   zoom and support functionality where eligible. Keep iOS external-payment
   guards disabled unless a separate approved iOS payment design exists.
5. Run Flutter package restoration, analysis, tests, licence audit and an iOS
   simulator build using the working project's process. Check plugin minimum iOS
   versions/Pods as needed. If a physical device is available, test recording,
   photos/zoom, transcription/model lifecycle and text sharing. Clearly mark
   anything not verified; do not claim Windows checks prove iOS works.
6. Record package_id/source_commit, preserved Mac changes, resolved conflicts,
   results and remaining work in IOS_SYNC_HISTORY.md and the handover. Commit
   merged source locally. Do not push, publish or upload to App Store/TestFlight.
   Return a patch for any new shared-code fixes so Windows can receive them too.
```
