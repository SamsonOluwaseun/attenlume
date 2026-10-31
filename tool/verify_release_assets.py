"""Release asset validation and SHA-256 checksum utility [P1-28, ADR-061].

Validates canonical release asset filenames and generates/verifies SHA256SUMS.txt
in standard coreutils format without external dependencies.
"""

from __future__ import annotations

import argparse
import hashlib
import re
from pathlib import Path
import sys

CANONICAL_ASSETS = (
    'attenlume-android.apk',
    'attenlume-windows-setup.exe',
)
CHECKSUMS_FILENAME = 'SHA256SUMS.txt'


def compute_sha256(path: Path) -> str:
    """Compute hex SHA-256 digest for a file."""
    h = hashlib.sha256()
    with path.open('rb') as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()


def generate_checksums(directory: Path) -> list[str]:
    """Generate SHA256SUMS.txt lines for canonical assets present in directory."""
    lines: list[str] = []
    for asset_name in CANONICAL_ASSETS:
        asset_path = directory / asset_name
        if asset_path.is_file():
            digest = compute_sha256(asset_path)
            lines.append(f'{digest}  {asset_name}\n')
        else:
            raise FileNotFoundError(f'Missing required release asset: {asset_path}')
    return lines


def write_checksums_file(directory: Path) -> Path:
    """Write SHA256SUMS.txt in directory for canonical assets."""
    lines = generate_checksums(directory)
    out_file = directory / CHECKSUMS_FILENAME
    out_file.write_text(''.join(lines), encoding='utf-8')
    return out_file


def verify_checksums_file(directory: Path) -> tuple[bool, list[str]]:
    """Verify SHA256SUMS.txt against files in directory.

    Returns (all_ok, list_of_status_messages).
    """
    sums_file = directory / CHECKSUMS_FILENAME
    messages: list[str] = []
    try:
        lines = sums_file.read_text(encoding='utf-8').splitlines()
    except (OSError, UnicodeError) as error:
        return False, [f'Cannot read checksums file: {error}']

    seen: set[str] = set()
    valid = True
    for number, line in enumerate(lines, 1):
        match = re.fullmatch(r'([0-9a-fA-F]{64}) [ *]([^\r\n]+)', line)
        if not match:
            messages.append(f'Line {number}: invalid SHA-256 manifest entry')
            valid = False
            continue
        expected_digest, filename = match.groups()
        if filename not in CANONICAL_ASSETS:
            messages.append(f'Line {number}: unexpected asset path: {filename!r}')
            valid = False
            continue
        if filename in seen:
            messages.append(f'Line {number}: duplicate asset: {filename}')
            valid = False
            continue
        seen.add(filename)
        target_file = directory / filename
        try:
            if target_file.is_symlink() or target_file.resolve().parent != directory.resolve():
                raise ValueError('asset must be a direct file within the release directory')
            actual_digest = compute_sha256(target_file)
        except (OSError, ValueError) as error:
            messages.append(f'{filename}: FAILED ({error})')
            valid = False
            continue
        if actual_digest == expected_digest.lower():
            messages.append(f'{filename}: OK')
        else:
            messages.append(f'{filename}: FAILED (checksum mismatch)')
            valid = False
    for filename in CANONICAL_ASSETS:
        if filename not in seen:
            messages.append(f'Missing manifest entry: {filename}')
            valid = False
    return valid, messages


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description='Release asset and checksums verifier.')
    subparsers = parser.add_subparsers(dest='command', required=True)

    gen_parser = subparsers.add_parser('generate', help='Generate SHA256SUMS.txt for canonical assets')
    gen_parser.add_argument('directory', type=Path, help='Directory containing release assets')

    ver_parser = subparsers.add_parser('verify', help='Verify SHA256SUMS.txt in directory')
    ver_parser.add_argument('directory', type=Path, help='Directory containing release assets and SHA256SUMS.txt')

    args = parser.parse_args(argv)
    target_dir: Path = args.directory

    if not target_dir.is_dir():
        print(f'Error: Directory not found: {target_dir}', file=sys.stderr)
        return 1

    if args.command == 'generate':
        try:
            out = write_checksums_file(target_dir)
            print(f'Generated checksums: {out}')
            return 0
        except Exception as e:
            print(f'Error generating checksums: {e}', file=sys.stderr)
            return 1

    if args.command == 'verify':
        ok, msgs = verify_checksums_file(target_dir)
        for msg in msgs:
            print(msg)
        return 0 if ok else 1

    return 1


if __name__ == '__main__':
    sys.exit(main())
