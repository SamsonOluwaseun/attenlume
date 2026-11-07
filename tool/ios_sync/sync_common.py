"""Portable, dependency-free helpers for P1-43 source handoffs."""

import hashlib
from pathlib import Path, PurePosixPath


ROOT_FILES = {
    'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', 'build.yaml',
    'LICENSE', 'THIRD_PARTY_NOTICES.md', 'flutter_launcher_icons.yaml',
}
ROOT_DIRS = {
    'lib', 'assets', 'design', 'drift_schemas', 'test', 'integration_test',
    'android', 'windows', 'ios',
}


def allowed(relative):
    p = PurePosixPath(relative)
    if (not relative or p.is_absolute() or '..' in p.parts
            or '\\' in relative or ':' in relative):
        return False
    if any(part in {
        '.git', '.dart_tool', 'build', 'ephemeral', 'Pods', '.symlinks',
        '.gradle', 'xcuserdata', 'node_modules', '__pycache__', 'logs',
    } for part in p.parts):
        return False
    if (p.name.startswith('.env') or p.name in {'local.properties', 'key.properties', 'Generated.xcconfig',
                  'flutter_export_environment.sh'}
            or p.name.startswith('GeneratedPluginRegistrant.')
            or p.suffix.lower() in {'.jks', '.keystore', '.p12', '.mobileprovision', '.pyc', '.pem', '.key', '.secret'}):
        return False
    return (relative in ROOT_FILES or relative == 'docs/IOS_SYNC_NOTES.md' or p.parts[0] in ROOT_DIRS
            or relative in {'tool/gen_tokens.dart', 'tool/licence_audit.dart',
                            'tool/brand/prepare_icons.dart'}
            or relative.startswith('tool/ios_sync/')
            or relative.startswith('docs/user-guide/')
            or (relative.startswith('tool/guide/') and p.suffix in {'.js', '.json', '.md'}))


def protected(relative):
    # Mac owns its native runner, signing, icon generation and toolchain setup.
    return relative.startswith('ios/') or relative == 'flutter_launcher_icons.yaml'


def safe_path(root, relative):
    if not allowed(relative):
        raise ValueError(f'Not an allowed source path: {relative}')
    root = Path(root).resolve()
    path = root.joinpath(*PurePosixPath(relative).parts)
    if not path.resolve().is_relative_to(root):
        raise ValueError(f'Path escapes source root: {relative}')
    return path


def sha(data):
    return None if data is None else hashlib.sha256(data).hexdigest()


def normalise(data):
    """Ignore Git's LF/CRLF conversion, without changing opaque binary bytes."""
    if data is None or b'\0' in data:
        return data
    try:
        data.decode('utf-8')
    except UnicodeDecodeError:
        return data
    return data.replace(b'\r\n', b'\n')


def is_text(data):
    if data is None or b'\0' in data:
        return False
    try:
        data.decode('utf-8')
        return True
    except UnicodeDecodeError:
        return False
