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

## Pasteable request to the Mac AI

“My current iOS app works. Read MAC_AI_MERGE.md in this transferred update pack,
compare its base and incoming source with my working app, then review and merge
the updates while preserving my iOS fixes and signing settings. Resolve conflicts,
run analysis/tests and the iOS build, and record the package ID and results.
Do not replace my whole project or publish anything.”
