#!/usr/bin/env python3
"""Export cumulative source updates for the working Mac iOS project [P1-43]."""

import argparse
from datetime import datetime, timezone
import hashlib
import io
import json
from pathlib import Path
import shutil
import subprocess
import zipfile

from sync_common import allowed, normalise, safe_path, sha


# Canonical source used to create the first Mac handoff. Keep this fixed:
# every pack remains usable even when earlier packs were never transferred.
BASELINE = 'b278d645bb2f6e90ebe010fc339fba32d452cd7e'


def git(repo, *args):
    return subprocess.check_output(
        ['git', '-c', f'safe.directory={repo.as_posix()}', '-C', str(repo), *args])


def capture(repo, revision=None):
    if revision:
        with zipfile.ZipFile(io.BytesIO(git(repo, 'archive', '--format=zip', revision))) as archive:
            return {name: normalise(archive.read(name)) for name in archive.namelist()
                    if not name.endswith('/') and allowed(name)}
    raw = git(repo, 'ls-files', '-z')
    result = {}
    for relative in raw.decode('utf-8').split('\0'):
        if not allowed(relative):
            continue
        path = safe_path(repo, relative)
        if path.is_symlink():
            raise ValueError(f'Symlink cannot be exported: {relative}')
        if not path.exists():  # Tracked deletion, represented by absence.
            continue
        content = path.read_bytes()
        result[relative] = normalise(content)
    # Agent-maintained local-only platform notes travel with the private pack.
    notes = safe_path(repo, 'docs/IOS_SYNC_NOTES.md')
    if notes.is_file():
        result['docs/IOS_SYNC_NOTES.md'] = normalise(notes.read_bytes())
    return result


def inventory(files):
    return {key: sha(value) for key, value in sorted(files.items())}


def file_sha(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def export(repo, output, check=False):
    repo, output = Path(repo).resolve(), Path(output).resolve()
    if output.is_relative_to(repo):
        raise ValueError('Export destination must be outside the source repository')
    incoming = capture(repo)
    baseline = capture(repo, BASELINE)
    base_hashes, new_hashes = inventory(baseline), inventory(incoming)
    digest = sha(json.dumps(new_hashes, sort_keys=True).encode())
    latest_path = output / 'LATEST.json'
    if check:
        latest = json.loads(latest_path.read_text(encoding='utf-8'))
        if latest['source_digest'] != digest:
            raise ValueError('iOS update pack is stale; run export_update.py')
        from compare_on_mac import validate_package
        validate_package(output / latest['package_id'])
        if file_sha(output / latest['archive']) != latest['archive_sha256']:
            raise ValueError('Update archive hash mismatch')
        print(f"Current: {latest['package_id']}")
        return output / latest['package_id']
    head = git(repo, 'rev-parse', 'HEAD').decode().strip()
    version = next(line.split(':', 1)[1].strip() for line in
                   incoming['pubspec.yaml'].decode().splitlines() if line.startswith('version:'))
    now = datetime.now(timezone.utc)
    package_id = f"{now:%Y%m%dT%H%M%S%fZ}_v{version}_{digest[:10]}"
    package = output / package_id
    package.mkdir(parents=True, exist_ok=False)
    for side, files in (('base', baseline), ('incoming', incoming)):
        for relative, content in files.items():
            path = safe_path(package / side, relative)
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
    changes = []
    for relative in sorted(set(base_hashes) | set(new_hashes)):
        if base_hashes.get(relative) != new_hashes.get(relative):
            changes.append({'path': relative, 'change': 'add' if relative not in base_hashes
                            else 'delete' if relative not in new_hashes else 'modify'})
    manifest = {'format': 1, 'package_id': package_id, 'version': version,
                'created_utc': now.isoformat(), 'baseline_commit': BASELINE,
                'source_commit': head, 'source_digest': digest,
                'tracked_working_changes': git(repo, 'status', '--porcelain',
                                              '--untracked-files=no').decode().splitlines(),
                'base_files': base_hashes, 'incoming_files': new_hashes, 'changes': changes,
                'ios_validation': 'Owner reports initial Mac build works; this update needs Mac checks.'}
    (package / 'UPDATE.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    helper_dir = Path(__file__).resolve().parent
    for name in ('compare_on_mac.py', 'sync_common.py', 'MAC_AI_MERGE.md'):
        shutil.copyfile(helper_dir / name, package / name)
    text = ['# Shared-source update', '', f'Package: `{package_id}`', '',
            f'Source commit: `{head}`; app version: `{version}`.', '',
            '**Do not replace your working Mac folder with incoming/.**',
            'Read MAC_AI_MERGE.md and run compare_on_mac.py against the actual Mac project.', '',
            'This is cumulative from the original shared source: skipped packs are safe.',
            'base/ is the common ancestor; incoming/ is the latest canonical source.',
            'Mac-only native iOS fixes are deliberately preserved for review.', '',
            '## Changes since original handoff', '', '| Change | File |', '| --- | --- |']
    text.extend(f"| {x['change']} | `{x['path']}` |" for x in changes)
    (package / 'README.md').write_text('\n'.join(text) + '\n', encoding='utf-8')
    checksums = []
    for path in sorted(package.rglob('*')):
        if path.is_file():
            checksums.append(f'{sha(path.read_bytes())}  {path.relative_to(package).as_posix()}')
    (package / 'SHA256SUMS.txt').write_text('\n'.join(checksums) + '\n', encoding='utf-8')
    archive = output / f'{package_id}.zip'
    with zipfile.ZipFile(archive, 'x', compression=zipfile.ZIP_DEFLATED) as z:
        for path in sorted(package.rglob('*')):
            if path.is_file():
                z.write(path, f'{package_id}/{path.relative_to(package).as_posix()}')
    # Publish the pointer only after the complete folder and archive exist.
    latest = {'package_id': package_id, 'source_digest': digest, 'archive': archive.name,
              'archive_sha256': file_sha(archive)}
    temp = output / 'LATEST.json.tmp'
    temp.write_text(json.dumps(latest, indent=2) + '\n', encoding='utf-8')
    temp.replace(latest_path)
    (output / 'README.md').write_text(
        '# Attenlume iOS updates\n\n'
        f'Latest transfer: [{archive.name}]({archive.name})\n\n'
        f'Unpacked copy: [{package_id}/MAC_AI_MERGE.md]({package_id}/MAC_AI_MERGE.md)\n\n'
        'Copy the latest ZIP or its unpacked folder to the Mac beside the working app.\n'
        'Ask the Mac AI to read MAC_AI_MERGE.md, compare the three versions and merge\n'
        'while preserving native iOS fixes and signing. Do not replace the Mac app folder.\n\n'
        'Every pack is cumulative; earlier transfers can be skipped. LATEST.json records\n'
        'the latest archive and its SHA-256. The original attenlume-ios is historical.\n\n'
        'After future development in the main attenlume repository, run:\n\n'
        '```powershell\npython tool/ios_sync/export_update.py\n'
        'python tool/ios_sync/export_update.py --check\n```\n', encoding='utf-8')
    print(f'Exported {len(incoming)} source files; {len(changes)} changes since initial baseline.')
    print(f'Copy to Mac: {archive}')
    return package


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    default_repo = Path(__file__).resolve().parents[2]
    parser.add_argument('--repo', type=Path, default=default_repo)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    output = args.output or args.repo.resolve().parent / 'attenlume-ios-updates'
    export(args.repo, output, args.check)


if __name__ == '__main__':
    main()
