"""Release asset validation and SHA-256 checksum utility [P1-28, ADR-061].

Validates canonical release asset filenames and generates/verifies SHA256SUMS.txt
in standard coreutils format without external dependencies.
"""

from __future__ import annotations

import argparse
import hashlib
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
    if not sums_file.is_file():
        return False, [f'Checksums file not found: {sums_file}']

    all_ok = True
    messages: list[str] = []
    lines = sums_file.read_text(encoding='utf-8').splitlines()

    for line in lines:
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        parts = line.split(maxsplit=1)
        if len(parts) != 2:
            messages.append(f'Invalid format in line: {line}')
            all_ok = False
            continue

        expected_digest, filename = parts[0].strip(), parts[1].strip().lstrip('*')
        target_file = directory / filename
        if not target_file.is_file():
            messages.append(f'{filename}: FAILED (file not found)')
            all_ok = False
            continue

        actual_digest = compute_sha256(target_file)
        if actual_digest.lower() == expected_digest.lower():
            messages.append(f'{filename}: OK')
        else:
            messages.append(
                f'{filename}: FAILED (checksum mismatch: expected {expected_digest}, got {actual_digest})'
            )
            all_ok = False

    return all_ok, messages


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
