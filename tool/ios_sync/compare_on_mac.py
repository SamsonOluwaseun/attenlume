#!/usr/bin/env python3
"""Plan a three-way source merge. Never modifies the working Mac project."""

import argparse
from collections import Counter
import json
from pathlib import Path
import subprocess
import tempfile

from sync_common import allowed, is_text, normalise, protected, safe_path, sha


def classify(base, incoming, local, relative):
    b, n, l = map(normalise, (base, incoming, local))
    if b == n:
        return ('preserved_local' if l != b else 'unchanged'), None
    if l == n:
        return 'already_current', None
    if protected(relative):
        return 'native_review', None
    if l == b:
        return ('delete' if n is None else 'add' if b is None else 'update'), incoming
    if not all(is_text(x) for x in (b, n, l)):
        return 'conflict', None
    # The common ancestor is real source, not the last file copied by date.
    with tempfile.TemporaryDirectory(prefix='attenlume-merge-') as directory:
        files = [Path(directory) / name for name in ('mac', 'base', 'incoming')]
        for path, content in zip(files, (l, b, n)):
            path.write_bytes(content)
        result = subprocess.run(
            ['git', 'merge-file', '-p', '-L', 'Mac working copy', '-L',
             'Original shared baseline', '-L', 'Windows incoming',
             *(str(path) for path in files)], capture_output=True,
        )
        if result.returncode < 0 or result.returncode > 127:
            raise RuntimeError(result.stderr.decode(errors='replace'))
        return ('merged' if result.returncode == 0 else 'conflict'), result.stdout


def validate_package(package):
    manifest = json.loads((package / 'UPDATE.json').read_text(encoding='utf-8'))
    if manifest.get('format') != 1:
        raise ValueError('Unsupported update format')
    for side in ('base', 'incoming'):
        for relative, expected in manifest[f'{side}_files'].items():
            path = safe_path(package / side, relative)
            if sha(path.read_bytes()) != expected:
                raise ValueError(f'Package hash mismatch: {side}/{relative}')
    return manifest


def plan(package, project, review):
    package, project, review = (Path(x).resolve() for x in (package, project, review))
    if review.is_relative_to(project) or review.is_relative_to(package):
        raise ValueError('Review must be a new folder outside the project and update pack')
    if not (project / 'pubspec.yaml').is_file():
        raise ValueError('Project must be the Flutter root containing pubspec.yaml')
    manifest = validate_package(package)
    review.mkdir(parents=True, exist_ok=False)
    results = []
    for relative in sorted(set(manifest['base_files']) | set(manifest['incoming_files'])):
        if not allowed(relative):
            raise ValueError(f'Unexpected source path: {relative}')
        base = (safe_path(package / 'base', relative).read_bytes()
                if relative in manifest['base_files'] else None)
        incoming = (safe_path(package / 'incoming', relative).read_bytes()
                    if relative in manifest['incoming_files'] else None)
        local_path = safe_path(project, relative)
        if local_path.exists() and not local_path.is_file():
            raise ValueError(f'Expected a file: {relative}')
        local = local_path.read_bytes() if local_path.is_file() else None
        action, proposed = classify(base, incoming, local, relative)
        if proposed is not None:
            destination = safe_path(review / 'proposed', relative)
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(proposed)
        results.append({'path': relative, 'action': action,
                        'local_sha256': sha(local), 'incoming_sha256': sha(incoming)})
    report = {'package_id': manifest['package_id'], 'project': str(project),
              'package': str(package), 'counts': dict(Counter(x['action'] for x in results)),
              'files': results}
    (review / 'REPORT.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    lines = ['# Mac merge review', '', 'No working project files were changed.', '',
             f"Update: `{manifest['package_id']}`", '', '## Counts', '']
    lines.extend(f'- {key}: {value}' for key, value in sorted(report['counts'].items()))
    lines.extend(['', '## Files to review', '', '| Action | File |', '| --- | --- |'])
    lines.extend(f"| {x['action']} | `{x['path']}` |" for x in results
                 if x['action'] not in {'unchanged', 'preserved_local', 'already_current'})
    lines.extend(['', 'Read MAC_AI_MERGE.md in the update pack before applying anything.',
                  'Conflict output may contain markers; native_review requires a manual merge.',
                  'Verify local_sha256 still matches before applying a proposal.', ''])
    (review / 'REPORT.md').write_text('\n'.join(lines), encoding='utf-8')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', required=True, type=Path)
    parser.add_argument('--review', required=True, type=Path)
    parser.add_argument('--package', type=Path, default=Path(__file__).resolve().parent)
    args = parser.parse_args()
    report = plan(args.package, args.project, args.review)
    print(json.dumps(report['counts'], indent=2))
    print(f'Review written to {args.review}; working project unchanged.')


if __name__ == '__main__':
    main()
